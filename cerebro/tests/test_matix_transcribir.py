"""Tests del endpoint `/matix/transcribir`.

No invocamos a Whisper real (costoso y no-determinista). Sí
verificamos auth, validación de tamaño y la forma del payload.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.routers.matix import _mime_audio


def test_mime_audio_infiere_por_extension() -> None:
    # La app graba .m4a; aunque el multipart llegue como octet-stream
    # genérico, mandamos a Whisper un mime de audio correcto.
    assert _mime_audio("matix-123.m4a", "application/octet-stream") == "audio/mp4"
    assert _mime_audio("voz.m4a", None) == "audio/mp4"
    assert _mime_audio("nota.mp3", None) == "audio/mpeg"
    assert _mime_audio("clip.wav", "application/octet-stream") == "audio/wav"


def test_mime_audio_respeta_content_type_valido() -> None:
    # Extensión desconocida pero content-type de audio válido: lo usamos.
    assert _mime_audio("audio.raw", "audio/ogg") == "audio/ogg"
    # Sin extensión útil ni content-type → default seguro.
    assert _mime_audio("audio", None) == "audio/mp4"
    assert _mime_audio("audio", "application/octet-stream") == "audio/mp4"


async def test_transcribir_sin_auth(client_anon: AsyncClient) -> None:
    r = await client_anon.post("/api/v1/matix/transcribir")
    assert r.status_code == 401


async def test_transcribir_falta_archivo(client: AsyncClient) -> None:
    # Sin `file` en el form → FastAPI valida y devuelve 422.
    r = await client.post("/api/v1/matix/transcribir")
    assert r.status_code == 422


async def test_transcribir_audio_vacio(client: AsyncClient) -> None:
    # Mandamos un file vacío explícito → 400 con mensaje claro.
    files = {"file": ("vacio.m4a", b"", "audio/mp4")}
    r = await client.post("/api/v1/matix/transcribir", files=files)
    assert r.status_code == 400
    assert "vacío" in r.text or "vacio" in r.text


async def test_transcribir_audio_demasiado_grande(client: AsyncClient) -> None:
    # 25 MB > 24 MB tope → 413 sin pegarle a OpenAI.
    grande = b"\x00" * (25 * 1024 * 1024)
    files = {"file": ("grande.m4a", grande, "audio/mp4")}
    r = await client.post("/api/v1/matix/transcribir", files=files)
    assert r.status_code == 413
