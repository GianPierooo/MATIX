"""Backup diario de la BD a Supabase Storage (operación).

Exporta las tablas CLAVE (los datos del usuario) a un bucket privado de
Storage, una vez al día, guardando los últimos N y rotando los viejos. Es una
red de seguridad operativa además del backup nativo de Supabase (ver
docs/Operacion.md). NO incluye tablas de embeddings pesadas (se reconstruyen).

La parte PURA (nombre del archivo, rotación) se testea sin red.
"""
from __future__ import annotations

import json
import logging
from datetime import date, datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from ..config import settings
from ..db import Postgrest

logger = logging.getLogger("matix.backup")
LIMA = ZoneInfo("America/Lima")

BUCKET = "backups"
HORA_BACKUP = 4  # 4 a. m. (Lima): baja actividad
PREFIJO = "matix-backup-"
RETENER = 14  # cuántos backups diarios guardar antes de rotar

# Tablas con los DATOS del usuario. Se excluyen las de embeddings (material_chunks,
# apuntes/memoria conversacional con vectores): son pesadas y reconstruibles.
TABLAS_CLAVE = (
    "proyectos",
    "arbol_nodos",
    "proyecto_detalles",
    "tareas",
    "subtareas",
    "eventos",
    "apuntes",
    "cursos",
    "sesiones_clase",
    "evaluaciones",
    "movimientos",
    "memoria",
    "cierres_dia",
    "config_horario",
)


# ── Lógica pura (testeable sin red) ──────────────────────────────────────────

def nombre_backup(d: date) -> str:
    """Nombre del archivo de backup del día. PURO."""
    return f"{PREFIJO}{d.isoformat()}.json"


def a_rotar(nombres: list[str], retener: int) -> list[str]:
    """Dado el listado de backups, devuelve los que sobran (los más viejos) para
    borrar, conservando los `retener` más recientes. Ordena por nombre (la fecha
    ISO ordena cronológicamente). PURO."""
    solo = sorted(n for n in nombres if n.startswith(PREFIJO))
    if len(solo) <= retener:
        return []
    return solo[: len(solo) - retener]


# ── Impuro: export + Storage ─────────────────────────────────────────────────

def _storage_headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {"apikey": key, "Authorization": f"Bearer {key}"}


def _storage_base() -> str:
    return f"{settings.supabase_url}/storage/v1"


async def _asegurar_bucket(cli: httpx.AsyncClient) -> None:
    """Crea el bucket privado si no existe (idempotente)."""
    r = await cli.post(
        f"{_storage_base()}/bucket",
        headers={**_storage_headers(), "Content-Type": "application/json"},
        json={"id": BUCKET, "name": BUCKET, "public": False},
    )
    if r.status_code not in (200, 201, 409):
        # 409 = ya existe. Otro código: log, pero seguimos (el upload dirá si falla).
        logger.warning("backup: crear bucket devolvió %s", r.status_code)


async def exportar(db: Postgrest, *, ahora: datetime | None = None) -> dict[str, Any]:
    """Exporta las tablas clave a un JSON y lo sube a Storage; luego rota. Best
    effort: una tabla que falle no aborta el resto."""
    ahora = ahora or datetime.now(timezone.utc)
    hoy = ahora.astimezone(LIMA).date()

    tablas: dict[str, Any] = {}
    for t in TABLAS_CLAVE:
        try:
            tablas[t] = await db.list(t, limit=10000)
        except Exception:  # noqa: BLE001
            logger.exception("backup: no pude leer la tabla %s", t)
            tablas[t] = []

    cuerpo = json.dumps(
        {
            "generado_en": ahora.isoformat(),
            "fecha": hoy.isoformat(),
            "tablas": tablas,
        },
        ensure_ascii=False,
    ).encode("utf-8")

    nombre = nombre_backup(hoy)
    async with httpx.AsyncClient(timeout=60.0) as cli:
        await _asegurar_bucket(cli)
        up = await cli.post(
            f"{_storage_base()}/object/{BUCKET}/{nombre}",
            headers={
                **_storage_headers(),
                "Content-Type": "application/json",
                "x-upsert": "true",
            },
            content=cuerpo,
        )
        if up.status_code not in (200, 201):
            raise RuntimeError(f"Storage rechazó el backup ({up.status_code}).")
        rotados = await _rotar(cli)

    return {
        "archivo": nombre,
        "tablas": len(tablas),
        "bytes": len(cuerpo),
        "rotados": rotados,
    }


async def _rotar(cli: httpx.AsyncClient) -> int:
    """Lista los backups y borra los que sobran (más allá de RETENER)."""
    r = await cli.post(
        f"{_storage_base()}/object/list/{BUCKET}",
        headers={**_storage_headers(), "Content-Type": "application/json"},
        json={"prefix": "", "limit": 1000,
              "sortBy": {"column": "name", "order": "asc"}},
    )
    if r.status_code != 200:
        return 0
    nombres = [o.get("name", "") for o in r.json()]
    viejos = a_rotar(nombres, RETENER)
    borrados = 0
    for n in viejos:
        d = await cli.delete(
            f"{_storage_base()}/object/{BUCKET}/{n}", headers=_storage_headers()
        )
        if d.status_code in (200, 204):
            borrados += 1
    return borrados


async def revisar_backup(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Tick diario: a la hora del backup, si no se hizo hoy, exporta. Dedup vía
    `planificacion_enviados` (tipo 'backup'). Best-effort: nunca lanza."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    if local.hour < HORA_BACKUP or local.hour >= HORA_BACKUP + 2:  # ventana de 2h
        return {"backup": 0}
    if not settings.supabase_service_role_key:
        return {"backup": 0, "sin_key": True}
    hoy = local.date().isoformat()
    ya = await db.list(
        "planificacion_enviados", filters={"tipo": "backup", "fecha": hoy}, limit=1
    )
    if ya:
        return {"backup": 0, "ya": True}
    res = await exportar(db, ahora=ahora)
    await db.insert("planificacion_enviados", {"tipo": "backup", "fecha": hoy})
    logger.info("backup: %s (%d tablas, %d bytes, %d rotados)",
                res["archivo"], res["tablas"], res["bytes"], res["rotados"])
    return {"backup": 1, **res}
