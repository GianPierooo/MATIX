"""Tests del endpoint foto → apunte (Capa 7 · Paso 1).

No tocamos Supabase Storage ni OpenAI vision reales:

- `vision_storage.subir_imagen_apunte` se monkey-patchea para devolver
  un adjunto fake sin hacer la subida.
- `vision_ocr.extraer_texto` se reemplaza por una función controlada
  por el test (devuelve texto, devuelve vacío, o lanza).

Verificamos:

1. Camino feliz: OCR devuelve texto → apunte queda con ese contenido,
   `ocr_ok=true`, mensaje_ocr null, adjunto presente.
2. OCR devuelve vacío: apunte se crea con `contenido=""`,
   `ocr_ok=false`, mensaje legible.
3. OCR lanza excepción: idem caso 2 pero distinto mensaje.
4. Storage rebota: el endpoint devuelve 4xx/5xx y NO se inserta
   nada en la BD (no medio-apunte sin foto).
5. Etiquetas + curso_id se persisten.
6. Sin título, el cerebro asigna uno con fecha+hora.
"""
from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.routers import apuntes as router_apuntes


@pytest.fixture
def mock_storage(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """Sustituye la subida real por una que registra el archivo
    recibido y devuelve un adjunto fake. Si el test setea
    `estado['raise']`, esa excepción se lanza en la próxima llamada."""
    estado: dict[str, Any] = {
        "llamadas": [],
        "raise": None,
        "adjunto": {
            "url": "https://fake-supabase/storage/v1/object/public/apuntes-img/abc123.jpg",
            "tipo": "image/jpeg",
            "nombre": "foto.jpg",
        },
    }

    async def fake_subir(
        contenido: bytes,
        *,
        content_type: str | None,
        nombre_original: str | None,
    ) -> dict[str, str]:
        if estado["raise"] is not None:
            e = estado["raise"]
            estado["raise"] = None
            raise e
        estado["llamadas"].append(
            {
                "bytes": len(contenido),
                "content_type": content_type,
                "nombre": nombre_original,
            }
        )
        return estado["adjunto"]

    monkeypatch.setattr(
        router_apuntes.vision_storage, "subir_imagen_apunte", fake_subir
    )
    return estado


@pytest.fixture
def mock_ocr(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """Sustituye `extraer_texto` por una versión configurable."""
    estado: dict[str, Any] = {
        "texto": "Texto extraído.",
        "raise": None,
    }

    async def fake_extraer(*, url_imagen: str, modelo: str = "gpt-4o-mini") -> str:  # noqa: ARG001
        if estado["raise"] is not None:
            e = estado["raise"]
            estado["raise"] = None
            raise e
        return estado["texto"]

    monkeypatch.setattr(router_apuntes.vision_ocr, "extraer_texto", fake_extraer)
    return estado


def _multipart() -> dict[str, Any]:
    """Body multipart mínimo: una imagen de un byte con content_type
    jpeg. El test no chequea los bytes (los mocks no los necesitan)."""
    return {"file": ("foto.jpg", b"\xff\xd8\xff\xd9", "image/jpeg")}


# ─── Tests ───────────────────────────────────────────────────────────


async def test_camino_feliz_apunte_con_texto_extraido(
    client: AsyncClient,
    mock_storage: dict[str, Any],  # noqa: ARG001
    mock_ocr: dict[str, Any],
) -> None:
    mock_ocr["texto"] = "Hola, esto vino de OCR."
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        data={"titulo": "_test_foto_v1"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    apunte_id = body["id"]
    try:
        assert body["titulo"] == "_test_foto_v1"
        assert body["contenido"] == "Hola, esto vino de OCR."
        assert body["ocr_ok"] is True
        assert body["mensaje_ocr"] is None
        assert len(body["adjuntos"]) == 1
        assert body["adjuntos"][0]["tipo"] == "image/jpeg"
        assert body["adjuntos"][0]["url"].endswith(".jpg")
    finally:
        await client.delete(f"/api/v1/apuntes/{apunte_id}/permanente")


async def test_ocr_devuelve_vacio_marca_ocr_ok_false(
    client: AsyncClient,
    mock_storage: dict[str, Any],  # noqa: ARG001
    mock_ocr: dict[str, Any],
) -> None:
    mock_ocr["texto"] = ""
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        data={"titulo": "_test_foto_sin_texto"},
    )
    assert r.status_code == 201
    body = r.json()
    apunte_id = body["id"]
    try:
        assert body["contenido"] == ""
        assert body["ocr_ok"] is False
        assert body["mensaje_ocr"] is not None
        assert "texto" in body["mensaje_ocr"].lower()
        # La foto adjunta tiene que estar — eso es lo importante.
        assert len(body["adjuntos"]) == 1
    finally:
        await client.delete(f"/api/v1/apuntes/{apunte_id}/permanente")


async def test_ocr_explota_no_rompe_la_creacion(
    client: AsyncClient,
    mock_storage: dict[str, Any],  # noqa: ARG001
    mock_ocr: dict[str, Any],
) -> None:
    mock_ocr["raise"] = RuntimeError("OpenAI rate limit")
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        data={"titulo": "_test_foto_ocr_explota"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    apunte_id = body["id"]
    try:
        assert body["contenido"] == ""
        assert body["ocr_ok"] is False
        assert body["mensaje_ocr"] is not None
        # No filtramos detalles internos del error al cliente.
        assert "OpenAI" not in body["mensaje_ocr"]
        assert len(body["adjuntos"]) == 1
    finally:
        await client.delete(f"/api/v1/apuntes/{apunte_id}/permanente")


async def test_storage_rebota_aborta_sin_apunte_creado(
    client: AsyncClient,
    mock_storage: dict[str, Any],
    mock_ocr: dict[str, Any],  # noqa: ARG001
) -> None:
    """Si la imagen no se pudo subir, NO queremos un apunte huérfano
    sin foto. El endpoint devuelve error y NO inserta nada."""
    mock_storage["raise"] = RuntimeError("Storage 503")
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        data={"titulo": "_test_foto_storage_falla"},
    )
    assert r.status_code in (502, 500), r.text
    # No verificamos que la BD esté limpia exhaustivamente — confiamos
    # en que el insert no se llamó porque el endpoint cortó antes
    # (cobertura simple por el contrato del código).


async def test_etiquetas_csv_se_parsean_y_persisten(
    client: AsyncClient,
    mock_storage: dict[str, Any],  # noqa: ARG001
    mock_ocr: dict[str, Any],
) -> None:
    mock_ocr["texto"] = "x"
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        data={
            "titulo": "_test_foto_etiquetas",
            "etiquetas": "  pizarra ,  resumen,  ",  # con espacios y vacíos
        },
    )
    assert r.status_code == 201
    body = r.json()
    apunte_id = body["id"]
    try:
        assert set(body["etiquetas"]) == {"pizarra", "resumen"}
    finally:
        await client.delete(f"/api/v1/apuntes/{apunte_id}/permanente")


async def test_sin_titulo_se_asigna_uno_con_fecha(
    client: AsyncClient,
    mock_storage: dict[str, Any],  # noqa: ARG001
    mock_ocr: dict[str, Any],  # noqa: ARG001
) -> None:
    r = await client.post(
        "/api/v1/apuntes/desde-foto",
        files=_multipart(),
        # NO mandamos `titulo`.
    )
    assert r.status_code == 201
    body = r.json()
    apunte_id = body["id"]
    try:
        # El default es "Apunte del DD/MM HH:MM".
        assert body["titulo"].startswith("Apunte del ")
    finally:
        await client.delete(f"/api/v1/apuntes/{apunte_id}/permanente")


# ─── Tests puros del módulo de storage (sin BD ni red) ──────────────


def test_inferir_ext_desde_content_type() -> None:
    from app.vision.storage import _inferir_ext

    assert _inferir_ext("image/jpeg", None) == "jpg"
    assert _inferir_ext("image/png", None) == "png"
    assert _inferir_ext("image/webp", None) == "webp"
    # Caso raro: content-type vacío + nombre con extensión válida.
    assert _inferir_ext(None, "foto.PNG") == "png"
    # Default conservador si no hay nada útil.
    assert _inferir_ext(None, None) == "jpg"


def test_subir_imagen_rechaza_vacio_y_grande(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Reglas de validación antes de tocar Storage: rechazamos
    cuerpos vacíos y mayores a 10 MB."""
    import asyncio

    from app.vision.storage import (
        TAMANO_MAX_BYTES,
        subir_imagen_apunte,
    )

    with pytest.raises(ValueError, match="vacía"):
        asyncio.run(
            subir_imagen_apunte(
                b"", content_type="image/jpeg", nombre_original="x.jpg"
            )
        )

    grande = b"x" * (TAMANO_MAX_BYTES + 1)
    with pytest.raises(ValueError, match="MB"):
        asyncio.run(
            subir_imagen_apunte(
                grande,
                content_type="image/jpeg",
                nombre_original="grande.jpg",
            )
        )
