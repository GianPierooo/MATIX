"""Memoria conversacional · recall semántico sobre el historial de chat.

Tienda vectorial SEPARADA (no es la memoria personal de hechos ni la biblioteca
de material): aquí viven los mensajes reales de las conversaciones, troceados y
embebidos, para buscar "qué hablamos la otra vez".

Piezas:
  - `conversacion_actual` · sesión por inactividad (single-user, server-side).
  - `persistir_turno`      · guarda el intercambio en `mensajes_chat`.
  - `indexar_turno`        · async: trocea + embebe + guarda en
                             `memoria_conversacional` (no bloquea el chat).
  - `buscar_en_historial`  · top-k por similitud, EXCLUYENDO la conversación
                             actual, con la fecha en lenguaje natural (Lima).

La parte PURA (chunking, fecha en palabras, armado del resultado) está al final
y se testea sin BD ni red.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import llm

_LIMA = ZoneInfo("America/Lima")

# Lapso de inactividad que abre una nueva conversación (sesión).
_GAP_SESION_HORAS = 6

# Presupuesto de caracteres por chunk (~400 tokens). Un intercambio típico
# entra en uno; charlas largas se parten en ventanas.
_MAX_CHARS_CHUNK = 1500

_DIAS_ES = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
_MESES_ES = [
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
    "septiembre", "octubre", "noviembre", "diciembre",
]


# ── Sesión por inactividad (server-side) ────────────────────────────────────

async def conversacion_actual(db: Postgrest, *, ahora: datetime | None = None) -> str:
    """Devuelve el id de la conversación activa. Si pasaron más de
    `_GAP_SESION_HORAS` desde el último mensaje, abre una nueva. Single-user: la
    sesión se decide por tiempo, sin que la app mande un id."""
    ahora = ahora or datetime.now(timezone.utc)
    filas = await db.list("conversaciones", order="ultimo_mensaje_en.desc", limit=1)
    if filas:
        ultima = filas[0]
        prev = _parse_dt(ultima.get("ultimo_mensaje_en"))
        if prev is not None and (ahora - prev).total_seconds() <= _GAP_SESION_HORAS * 3600:
            await db.update("conversaciones", ultima["id"], {"ultimo_mensaje_en": ahora.isoformat()})
            return str(ultima["id"])
    nueva = await db.insert("conversaciones", {})
    return str(nueva["id"])


# ── Persistencia + indexado ─────────────────────────────────────────────────

async def persistir_turno(
    db: Postgrest, *, conversacion_id: str, mensaje_usuario: str, respuesta: str
) -> None:
    """Guarda el intercambio (usuario + Matix) en `mensajes_chat`. Rápido; se
    hace inline en el turno. Best-effort: si falla, no rompe el chat."""
    for rol, contenido in (("user", mensaje_usuario), ("assistant", respuesta)):
        if contenido and contenido.strip():
            await db.insert(
                "mensajes_chat",
                {"conversacion_id": conversacion_id, "rol": rol, "contenido": contenido},
            )


async def indexar_turno(
    db: Postgrest,
    *,
    conversacion_id: str,
    mensaje_usuario: str,
    respuesta: str,
    fecha: datetime | None = None,
) -> int:
    """Trocea el intercambio, lo embebe y lo guarda en `memoria_conversacional`.
    Pensado para correr en una tarea aparte (no bloquea la respuesta).
    Devuelve cuántos chunks indexó."""
    fecha = fecha or datetime.now(timezone.utc)
    mensajes = [
        {"rol": "user", "contenido": mensaje_usuario, "creado_en": fecha},
        {"rol": "assistant", "contenido": respuesta, "creado_en": fecha},
    ]
    chunks = construir_chunks(mensajes)
    if not chunks:
        return 0
    embeddings = await llm.embebir([c["contenido"] for c in chunks])
    for c, emb in zip(chunks, embeddings):
        await db.insert(
            "memoria_conversacional",
            {
                "conversacion_id": conversacion_id,
                "contenido": c["contenido"],
                "fecha": c["fecha"].isoformat() if isinstance(c["fecha"], datetime) else c["fecha"],
                "n_mensajes": c["n_mensajes"],
                "embedding": emb,
            },
        )
    return len(chunks)


def indexar_turno_async(
    db: Postgrest, *, conversacion_id: str, mensaje_usuario: str, respuesta: str
) -> None:
    """Dispara el indexado en segundo plano: el chat responde ya, el embedding
    corre después. Errores se tragan (no deben tumbar el turno)."""
    async def _correr() -> None:
        try:
            await indexar_turno(
                db,
                conversacion_id=conversacion_id,
                mensaje_usuario=mensaje_usuario,
                respuesta=respuesta,
            )
        except Exception:  # noqa: BLE001
            # Indexado best-effort: el recall es un plus, nunca rompe el chat.
            pass

    asyncio.create_task(_correr())


# ── Búsqueda (recall por herramienta) ───────────────────────────────────────

async def buscar_en_historial(
    db: Postgrest,
    *,
    consulta: str,
    top_k: int = 5,
    excluir_conversacion: str | None = None,
    ahora: datetime | None = None,
    embedding: list[float] | None = None,
) -> list[dict[str, Any]]:
    """Busca en el historial por similitud semántica. Excluye la conversación
    actual (ya está en contexto). Devuelve `{contenido, fecha_texto, distancia}`
    con la fecha en lenguaje natural (Lima).

    `embedding` opcional: si el caller YA embebió la consulta (p.ej. el recall
    automático del chat, que embebe el mensaje una sola vez para varias tiendas),
    se reutiliza y NO se vuelve a embeber."""
    if embedding is None:
        embs = await llm.embebir_seguro([consulta])
        if not embs:
            return []  # sin crédito de embeddings → sin recall, el chat sigue
        embedding = embs[0]
    filas = await db.rpc(
        "buscar_memoria_conversacional",
        {
            "query_embedding": embedding,
            "excluir_conversacion": excluir_conversacion,
            "match_count": top_k,
        },
    )
    return formatear_recuerdos(filas, ahora=ahora)


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD ni red)
# ════════════════════════════════════════════════════════════════════════════

def construir_chunks(
    mensajes: list[dict[str, Any]], *, max_chars: int = _MAX_CHARS_CHUNK
) -> list[dict[str, Any]]:
    """Agrupa mensajes consecutivos en chunks coherentes (un intercambio o una
    ventana de ~max_chars), NO un embedding por mensaje suelto. Cada chunk lleva
    la fecha de su PRIMER mensaje (cuándo se habló de eso).

    Cada mensaje: `{rol, contenido, creado_en}`. Devuelve
    `[{contenido, fecha, n_mensajes}]`.
    """
    chunks: list[dict[str, Any]] = []
    actual: list[str] = []
    fecha_inicio: Any = None
    largo = 0
    n = 0

    def _flush() -> None:
        nonlocal actual, fecha_inicio, largo, n
        if actual:
            chunks.append(
                {"contenido": "\n".join(actual), "fecha": fecha_inicio, "n_mensajes": n}
            )
        actual, fecha_inicio, largo, n = [], None, 0, 0

    for m in mensajes:
        contenido = (m.get("contenido") or "").strip()
        if not contenido:
            continue
        etiqueta = "Matix" if m.get("rol") == "assistant" else "Usuario"
        linea = f"{etiqueta}: {contenido}"
        # Si agregar esta línea desborda el presupuesto y ya hay algo, corta.
        if actual and largo + len(linea) > max_chars:
            _flush()
        if fecha_inicio is None:
            fecha_inicio = m.get("creado_en")
        actual.append(linea)
        largo += len(linea) + 1
        n += 1

    _flush()
    return chunks


def describir_fecha(fecha: datetime, *, ahora: datetime | None = None) -> str:
    """Fecha en lenguaje natural y en Lima: 'hoy', 'ayer', 'el martes 3 de
    junio de 2026', 'hace 2 semanas (el …)'. Para que Matix diga cuándo fue."""
    ahora = (ahora or datetime.now(timezone.utc)).astimezone(_LIMA)
    f = fecha.astimezone(_LIMA)
    dias = (ahora.date() - f.date()).days
    fecha_larga = (
        f"{_DIAS_ES[f.weekday()]} {f.day} de {_MESES_ES[f.month - 1]} de {f.year}"
    )
    if dias <= 0:
        return "hoy"
    if dias == 1:
        return "ayer"
    if dias < 7:
        return f"el {fecha_larga} (hace {dias} días)"
    if dias < 30:
        semanas = dias // 7
        return f"el {fecha_larga} (hace {semanas} semana{'s' if semanas > 1 else ''})"
    meses = dias // 30
    return f"el {fecha_larga} (hace {meses} mes{'es' if meses > 1 else ''})"


def formatear_recuerdos(
    filas: list[dict[str, Any]], *, ahora: datetime | None = None
) -> list[dict[str, Any]]:
    """Arma el resultado de la búsqueda con la fecha en palabras. Convierte
    `{contenido, fecha, distancia}` (de la RPC) en `{contenido, fecha_texto,
    distancia}` listo para que el modelo lo cite."""
    salida: list[dict[str, Any]] = []
    for fila in filas:
        f = _parse_dt(fila.get("fecha"))
        salida.append(
            {
                "contenido": fila.get("contenido", ""),
                "fecha_texto": describir_fecha(f, ahora=ahora) if f else "sin fecha",
                "distancia": fila.get("distancia"),
            }
        )
    return salida


def _parse_dt(valor: Any) -> datetime | None:
    """Parsea un timestamptz de Supabase (ISO, con 'Z' u offset) a aware UTC."""
    if isinstance(valor, datetime):
        return valor if valor.tzinfo else valor.replace(tzinfo=timezone.utc)
    if not isinstance(valor, str) or not valor:
        return None
    s = valor.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
