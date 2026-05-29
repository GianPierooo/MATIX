"""Subida de imágenes de apuntes al bucket `apuntes-img`.

El bucket es público (cualquiera con la URL puede leer) pero el
nombre se genera con `uuid4`, así que la URL es imposible de
adivinar. Es el mismo modelo que usamos para los APKs del bucket
`apks` — coherente con el resto del sistema.

Si en el futuro las imágenes pueden contener algo sensible
(documentos médicos, comprobantes), el bucket se cambia a privado
y servimos signed URLs por request. Ver `docs/Plan_Capa7.md`.
"""
from __future__ import annotations

import logging
import uuid

import httpx

from ..config import settings

logger = logging.getLogger("matix.vision.storage")

_BUCKET = "apuntes-img"

# Extensiones aceptadas + sus content-types. Si llega algo distinto
# rechazamos antes de tocar OpenAI o Storage.
_EXT_PERMITIDAS: dict[str, str] = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
}

# Tope de tamaño en bytes — 10 MB. Más que eso no aporta calidad
# de OCR y empieza a doler en costo de transferencia / OpenAI.
TAMANO_MAX_BYTES = 10 * 1024 * 1024


def _inferir_ext(content_type: str | None, nombre: str | None) -> str:
    """Decide la extensión del archivo a partir de content-type o
    del nombre original. Si ninguno alcanza, asume jpg."""
    if content_type:
        ct = content_type.lower()
        if "jpeg" in ct or "jpg" in ct:
            return "jpg"
        if "png" in ct:
            return "png"
        if "webp" in ct:
            return "webp"
    if nombre:
        partes = nombre.rsplit(".", 1)
        if len(partes) == 2 and partes[1].lower() in _EXT_PERMITIDAS:
            return partes[1].lower()
    return "jpg"


async def subir_imagen_apunte(
    contenido: bytes,
    *,
    content_type: str | None,
    nombre_original: str | None,
) -> dict[str, str]:
    """Sube los bytes al bucket `apuntes-img` y devuelve los datos
    listos para guardar como adjunto:

        {"url": "<público>", "tipo": "image/jpeg", "nombre": "<orig>.jpg"}

    Lanza `ValueError` si el tipo no es soportado, `RuntimeError`
    si la subida falla.
    """
    if len(contenido) == 0:
        raise ValueError("La imagen llegó vacía.")
    if len(contenido) > TAMANO_MAX_BYTES:
        mb = len(contenido) / (1024 * 1024)
        raise ValueError(
            f"La imagen pesa {mb:.1f} MB y el tope es "
            f"{TAMANO_MAX_BYTES // (1024 * 1024)} MB."
        )

    ext = _inferir_ext(content_type, nombre_original)
    if ext not in _EXT_PERMITIDAS:
        raise ValueError(
            f"Extensión no soportada: {ext}. Aceptamos JPG, PNG y WebP."
        )
    mime = _EXT_PERMITIDAS[ext]
    nombre_obj = f"{uuid.uuid4().hex}.{ext}"

    url_subida = (
        f"{settings.supabase_url}/storage/v1/object/{_BUCKET}/{nombre_obj}"
    )
    async with httpx.AsyncClient(timeout=30.0) as http:
        resp = await http.post(
            url_subida,
            content=contenido,
            headers={
                "Authorization": f"Bearer {settings.supabase_service_role_key}",
                "Content-Type": mime,
                "x-upsert": "true",
            },
        )
    if resp.status_code not in (200, 201):
        # No filtramos al cliente — solo log server-side.
        logger.warning(
            "Subida a Storage falló (%s): %s",
            resp.status_code,
            resp.text[:200],
        )
        raise RuntimeError(
            f"No pude subir la imagen al storage (status {resp.status_code})."
        )

    url_publica = (
        f"{settings.supabase_url}/storage/v1/object/public/"
        f"{_BUCKET}/{nombre_obj}"
    )
    return {
        "url": url_publica,
        "tipo": mime,
        "nombre": nombre_original or nombre_obj,
    }
