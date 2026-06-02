"""Muestras de voz para entrenar el wake word "oye matix" con la voz real
del usuario (Capa 2 · Wake word personalizado).

La app graba clips cortos (positivos = "oye matix"; negativos = frases que
NO deben dispararla) en WAV 16 kHz mono y los sube uno a uno. Aquí los
guardamos en un bucket PRIVADO de Supabase Storage (`wakeword-muestras`)
usando la `service_role` key, que vive solo en el servidor — la app nunca
la ve (regla de seguridad del proyecto).

Estructura de objetos (plana, en la raíz del bucket):

    positivo-001.wav, positivo-002.wav, …
    negativo-001.wav, negativo-002.wav, …

Plana a propósito: el listado de Storage en la raíz devuelve todos los
objetos sin tener que recorrer carpetas. `x-upsert` hace que regrabar el
mismo índice sobrescriba (la última sesión gana). El `.zip` reagrupa por
tipo en carpetas (`positivo/…`, `negativo/…`) para que el notebook de
Colab separe positivos de negativos de un vistazo.
"""
from __future__ import annotations

import io
import re
import zipfile

import httpx

from ..config import settings

BUCKET = "wakeword-muestras"

# Tipos válidos de muestra. `positivo` = "oye matix"; `negativo` = cualquier
# otra cosa que NO debe disparar (frases parecidas, ruido, otras palabras).
TIPOS = ("positivo", "negativo")

# Tope por clip: 2 MB. Un WAV de ~2 s a 16 kHz mono 16-bit pesa ~64 KB; 2 MB
# deja margen de sobra y corta cualquier archivo anómalo.
MAX_CLIP_BYTES = 2 * 1024 * 1024


class StorageNoConfigurado(RuntimeError):
    """Falta `supabase_url` o `supabase_service_role_key` en el entorno."""


def _base_url() -> str:
    url = (settings.supabase_url or "").rstrip("/")
    key = settings.supabase_service_role_key
    if not url or not key:
        raise StorageNoConfigurado(
            "Storage de Supabase no configurado (faltan SUPABASE_URL o "
            "SUPABASE_SERVICE_ROLE_KEY en el cerebro)."
        )
    return url


def _headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {"Authorization": f"Bearer {key}", "apikey": key}


def nombre_objeto(tipo: str, indice: int) -> str:
    """`positivo-007.wav`. Índice acolchado a 3 dígitos para orden estable."""
    if tipo not in TIPOS:
        raise ValueError(f"tipo inválido: {tipo!r} (usa {TIPOS})")
    return f"{tipo}-{indice:03d}.wav"


async def subir(tipo: str, indice: int, datos: bytes) -> str:
    """Sube un clip al bucket (upsert) y devuelve el nombre del objeto."""
    obj = nombre_objeto(tipo, indice)
    url = f"{_base_url()}/storage/v1/object/{BUCKET}/{obj}"
    async with httpx.AsyncClient(timeout=30.0) as cli:
        r = await cli.post(
            url,
            headers={
                **_headers(),
                "Content-Type": "audio/wav",
                "x-upsert": "true",
            },
            content=datos,
        )
    if r.status_code not in (200, 201):
        raise RuntimeError(f"Storage rechazó la subida ({r.status_code}): {r.text}")
    return obj


async def listar() -> list[str]:
    """Lista los nombres de objeto en la raíz del bucket (orden asc)."""
    url = f"{_base_url()}/storage/v1/object/list/{BUCKET}"
    async with httpx.AsyncClient(timeout=30.0) as cli:
        r = await cli.post(
            url,
            headers={**_headers(), "Content-Type": "application/json"},
            json={
                "prefix": "",
                "limit": 1000,
                "offset": 0,
                "sortBy": {"column": "name", "order": "asc"},
            },
        )
    if r.status_code != 200:
        raise RuntimeError(f"Storage list falló ({r.status_code}): {r.text}")
    items = r.json() or []
    # Solo objetos reales .wav (Storage puede colar un placeholder de carpeta).
    return [
        it["name"]
        for it in items
        if it.get("name", "").endswith(".wav")
    ]


async def conteo() -> dict[str, int]:
    """{'positivo': n, 'negativo': m, 'total': n+m}."""
    nombres = await listar()
    pos = sum(1 for n in nombres if n.startswith("positivo-"))
    neg = sum(1 for n in nombres if n.startswith("negativo-"))
    return {"positivo": pos, "negativo": neg, "total": pos + neg}


async def _descargar(obj: str) -> bytes:
    url = f"{_base_url()}/storage/v1/object/{BUCKET}/{obj}"
    async with httpx.AsyncClient(timeout=60.0) as cli:
        r = await cli.get(url, headers=_headers())
    if r.status_code != 200:
        raise RuntimeError(f"Storage download {obj} falló ({r.status_code})")
    return r.content


_RE_NOMBRE = re.compile(r"^(positivo|negativo)-(\d+)\.wav$")


def _arcname(obj: str) -> str:
    """`positivo-007.wav` → `positivo/007.wav` (carpetas para Colab)."""
    m = _RE_NOMBRE.match(obj)
    if not m:
        return obj
    return f"{m.group(1)}/{m.group(2)}.wav"


async def zip_todos() -> bytes:
    """Empaqueta todos los clips en un zip en memoria, reagrupados por tipo."""
    nombres = await listar()
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
        for obj in nombres:
            datos = await _descargar(obj)
            zf.writestr(_arcname(obj), datos)
    return buf.getvalue()


async def borrar_todos() -> int:
    """Vacía el bucket (para empezar una grabación desde cero). Devuelve
    cuántos objetos se borraron."""
    nombres = await listar()
    if not nombres:
        return 0
    url = f"{_base_url()}/storage/v1/object/{BUCKET}"
    async with httpx.AsyncClient(timeout=30.0) as cli:
        r = await cli.request(
            "DELETE",
            url,
            headers={**_headers(), "Content-Type": "application/json"},
            json={"prefixes": nombres},
        )
    if r.status_code != 200:
        raise RuntimeError(f"Storage borrar falló ({r.status_code}): {r.text}")
    return len(nombres)
