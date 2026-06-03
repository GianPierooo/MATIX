"""Perfil profundo de proyectos (Paso 1: capa de conocimiento).

Conocimiento ESTRUCTURADO por proyecto: objetivo, estado, fase, horizonte, y
detalles que se acumulan con fecha (componentes, próximos pasos, blockers,
notas, decisiones). Pensado para que más adelante un planificador diario lea
componentes + próximos pasos + estado. NO genera subtareas ni nudges acá.

No se mezcla con la memoria personal (hechos sueltos) ni con el recall de
conversaciones: esto es el perfil de cada proyecto.

La parte PURA (siguiente pregunta de la entrevista, armado del perfil) está al
final y se testea sin BD.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest

_LIMA = ZoneInfo("America/Lima")
_MESES = [
    "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic",
]

TIPOS_DETALLE = ("componente", "proximo_paso", "blocker", "nota", "decision")

# Guion de la entrevista de bootstrap. Orden = prioridad. `clase` indica si la
# respuesta va a un campo escalar del proyecto o a un detalle (tabla hija).
# `{nombre}` se rellena con el nombre del proyecto.
PREGUNTAS_ENTREVISTA: list[dict[str, str]] = [
    {"campo": "objetivo", "clase": "scalar",
     "pregunta": "¿Cuál es el objetivo de fondo de «{nombre}» y por qué te importa?"},
    {"campo": "estado_actual", "clase": "scalar",
     "pregunta": "¿En qué punto está «{nombre}» hoy?"},
    {"campo": "fase_actual", "clase": "scalar",
     "pregunta": "¿En qué fase o bloque de «{nombre}» estás ahora?"},
    {"campo": "componente", "clase": "detalle",
     "pregunta": "¿En qué partes o subobjetivos se divide «{nombre}»? Dímelas y las anoto."},
    {"campo": "proximo_paso", "clase": "detalle",
     "pregunta": "¿Qué es lo siguiente concreto que tienes que hacer en «{nombre}»?"},
    {"campo": "blocker", "clase": "detalle",
     "pregunta": "¿Hay algo que te esté trabando en «{nombre}»? Si no hay, dime «nada»."},
    {"campo": "horizonte", "clase": "scalar",
     "pregunta": "¿Para cuándo lo quieres o en qué horizonte lo ves (corto, medio o largo plazo)?"},
]

# campo de detalle → clave (lista) en el perfil armado.
_CAMPO_A_LISTA = {
    "componente": "componentes",
    "proximo_paso": "proximos_pasos",
    "blocker": "blockers",
}


# ── Resolución de proyecto ──────────────────────────────────────────────────

async def resolver_proyecto(
    db: Postgrest, *, proyecto_id: str | None = None, nombre: str | None = None
) -> dict[str, Any]:
    """Encuentra el proyecto por id o por nombre (aprox). Devuelve
    `{estado: 'ok'|'ninguno'|'varios', proyecto?, ambiguos?}`."""
    if proyecto_id:
        p = await db.get("proyectos", proyecto_id)
        return {"estado": "ok", "proyecto": p} if p else {"estado": "ninguno"}
    if not nombre:
        return {"estado": "ninguno"}
    objetivo = _norm(nombre)
    todos = await db.list("proyectos")
    matches = [p for p in todos if objetivo in _norm(p.get("nombre", ""))]
    if not matches:
        return {"estado": "ninguno"}
    nombres = {p["nombre"] for p in matches}
    if len(nombres) > 1:
        return {"estado": "varios", "ambiguos": sorted(nombres)}
    return {"estado": "ok", "proyecto": matches[0]}


# ── Lectura / escritura del perfil ──────────────────────────────────────────

async def ver_perfil(db: Postgrest, proyecto: dict[str, Any]) -> dict[str, Any]:
    """Arma el perfil completo (escalares + detalles agrupados)."""
    detalles = await db.list(
        "proyecto_detalles",
        filters={"proyecto_id": proyecto["id"]},
        order="creado_en.asc",
    )
    return armar_perfil(proyecto, detalles)


async def actualizar_perfil(
    db: Postgrest, *, proyecto_id: str, campos: dict[str, Any]
) -> dict[str, Any] | None:
    """Actualiza los campos escalares del perfil (objetivo, estado_actual,
    fase_actual, horizonte) + marca cuándo se tocó."""
    permitidos = {"objetivo", "estado_actual", "fase_actual", "horizonte"}
    payload = {k: v for k, v in campos.items() if k in permitidos and v is not None}
    if not payload:
        return await db.get("proyectos", proyecto_id)
    payload["perfil_actualizado_en"] = datetime.now(timezone.utc).isoformat()
    return await db.update("proyectos", proyecto_id, payload)


async def anotar_detalle(
    db: Postgrest, *, proyecto_id: str, tipo: str, contenido: str, estado: str = "abierto"
) -> dict[str, Any]:
    """Agrega un detalle (componente, próximo paso, blocker, nota, decisión)."""
    fila = await db.insert(
        "proyecto_detalles",
        {"proyecto_id": proyecto_id, "tipo": tipo, "contenido": contenido, "estado": estado},
    )
    await db.update(
        "proyectos", proyecto_id,
        {"perfil_actualizado_en": datetime.now(timezone.utc).isoformat()},
    )
    return fila


async def actualizar_detalle(
    db: Postgrest, *, detalle_id: str, contenido: str | None = None, estado: str | None = None
) -> dict[str, Any] | None:
    payload: dict[str, Any] = {}
    if contenido is not None:
        payload["contenido"] = contenido
    if estado is not None:
        payload["estado"] = estado
    if not payload:
        return await db.get("proyecto_detalles", detalle_id)
    return await db.update("proyecto_detalles", detalle_id, payload)


async def borrar_detalle(db: Postgrest, *, detalle_id: str) -> bool:
    return await db.delete("proyecto_detalles", detalle_id)


# ── Entrevista de bootstrap ─────────────────────────────────────────────────

async def iniciar_entrevista(db: Postgrest, *, proyecto: dict[str, Any]) -> dict[str, Any]:
    """Arranca (o reinicia) la entrevista de un proyecto y devuelve la primera
    pregunta pendiente."""
    await _guardar_entrevista(db, proyecto["id"], "en_curso", [])
    return await continuar_entrevista(db, proyecto=proyecto)


async def continuar_entrevista(
    db: Postgrest, *, proyecto: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Devuelve la siguiente pregunta pendiente. Si no se pasa proyecto, toma la
    entrevista en curso. Marca la pregunta como hecha (para no repetirla)."""
    if proyecto is None:
        filas = await db.list(
            "entrevistas_perfil",
            filters={"estado": "en_curso"},
            order="actualizado_en.desc",
            limit=1,
        )
        if not filas:
            return {"estado": "sin_entrevista"}
        proyecto = await db.get("proyectos", filas[0]["proyecto_id"])
        if not proyecto:
            return {"estado": "sin_entrevista"}

    entrevista = await _get_entrevista(db, proyecto["id"])
    preguntados = list(entrevista.get("preguntados") or []) if entrevista else []

    perfil = await ver_perfil(db, proyecto)
    pregunta = siguiente_pregunta(perfil, preguntados)

    if pregunta is None:
        await _guardar_entrevista(db, proyecto["id"], "completada", preguntados)
        return {"estado": "completada", "proyecto": proyecto["nombre"]}

    preguntados.append(pregunta["campo"])
    await _guardar_entrevista(db, proyecto["id"], "en_curso", preguntados)
    return {
        "estado": "pregunta",
        "proyecto": proyecto["nombre"],
        "proyecto_id": proyecto["id"],
        "campo": pregunta["campo"],
        "clase": pregunta["clase"],
        "pregunta": pregunta["pregunta"],
        "progreso": estado_entrevista(perfil, preguntados),
    }


async def _get_entrevista(db: Postgrest, proyecto_id: str) -> dict[str, Any] | None:
    filas = await db.list("entrevistas_perfil", filters={"proyecto_id": proyecto_id}, limit=1)
    return filas[0] if filas else None


async def _guardar_entrevista(
    db: Postgrest, proyecto_id: str, estado: str, preguntados: list[str]
) -> None:
    # La PK es proyecto_id (no `id`), así que reescribimos la fila (borrar+
    # insertar) en vez de usar el update-por-id genérico.
    await db.delete_where("entrevistas_perfil", filters={"proyecto_id": proyecto_id})
    await db.insert(
        "entrevistas_perfil",
        {"proyecto_id": proyecto_id, "estado": estado, "preguntados": preguntados},
    )


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def armar_perfil(proyecto: dict[str, Any], detalles: list[dict[str, Any]]) -> dict[str, Any]:
    """Combina el proyecto + sus detalles (excluyendo archivados) en un perfil
    estructurado, con los detalles agrupados por tipo."""
    grupos: dict[str, list[dict[str, Any]]] = {
        "componentes": [], "proximos_pasos": [], "blockers": [], "notas": [], "decisiones": [],
    }
    clave = {
        "componente": "componentes", "proximo_paso": "proximos_pasos",
        "blocker": "blockers", "nota": "notas", "decision": "decisiones",
    }
    for d in detalles:
        if d.get("estado") == "archivado":
            continue
        destino = clave.get(d.get("tipo"))
        if destino:
            grupos[destino].append(d)
    return {
        "id": proyecto.get("id"),
        "nombre": proyecto.get("nombre"),
        "objetivo": proyecto.get("objetivo"),
        "estado_actual": proyecto.get("estado_actual"),
        "fase_actual": proyecto.get("fase_actual"),
        "horizonte": proyecto.get("horizonte"),
        **grupos,
    }


def siguiente_pregunta(
    perfil: dict[str, Any], preguntados: list[str]
) -> dict[str, str] | None:
    """La siguiente pregunta pendiente de la entrevista, o None si está
    completa. Una pregunta se salta si ya se respondió (el campo tiene dato) o
    si ya se preguntó antes (para no insistir con lo opcional vacío)."""
    ya = set(preguntados)
    for q in PREGUNTAS_ENTREVISTA:
        campo = q["campo"]
        if campo in ya:
            continue
        if _campo_satisfecho(perfil, campo, q["clase"]):
            continue
        return {"campo": campo, "clase": q["clase"], "pregunta": q["pregunta"].format(nombre=perfil.get("nombre", ""))}
    return None


def estado_entrevista(perfil: dict[str, Any], preguntados: list[str]) -> dict[str, Any]:
    """Resumen del avance: cuántas preguntas resueltas y cuáles faltan."""
    ya = set(preguntados)
    faltan = [
        q["campo"]
        for q in PREGUNTAS_ENTREVISTA
        if q["campo"] not in ya and not _campo_satisfecho(perfil, q["campo"], q["clase"])
    ]
    total = len(PREGUNTAS_ENTREVISTA)
    return {"resueltas": total - len(faltan), "total": total, "faltan": faltan, "completa": not faltan}


def armar_perfil_texto(perfil: dict[str, Any]) -> str:
    """Perfil en texto para mostrarle al usuario («muéstrame qué sabes de X»).
    Incluye id de cada detalle para poder corregir/borrar."""
    L: list[str] = [f"Perfil de «{perfil.get('nombre', '')}»:"]
    _agrega(L, "Objetivo", perfil.get("objetivo"))
    _agrega(L, "Estado actual", perfil.get("estado_actual"))
    _agrega(L, "Fase actual", perfil.get("fase_actual"))
    _agrega(L, "Horizonte", perfil.get("horizonte"))
    _lista(L, "Componentes", perfil.get("componentes"))
    _lista(L, "Próximos pasos", perfil.get("proximos_pasos"), con_estado=True)
    _lista(L, "Blockers", perfil.get("blockers"), con_estado=True)
    _lista(L, "Notas", perfil.get("notas"))
    _lista(L, "Decisiones", perfil.get("decisiones"))
    if len(L) == 1:
        L.append("Todavía no tengo nada anotado de este proyecto.")
    return "\n".join(L)


def _campo_satisfecho(perfil: dict[str, Any], campo: str, clase: str) -> bool:
    if clase == "scalar":
        return bool((perfil.get(campo) or "").strip()) if isinstance(perfil.get(campo), str) else bool(perfil.get(campo))
    lista = perfil.get(_CAMPO_A_LISTA.get(campo, ""), [])
    return bool(lista)


def _agrega(L: list[str], etiqueta: str, valor: Any) -> None:
    if valor and str(valor).strip():
        L.append(f"- {etiqueta}: {str(valor).strip()}")


def _lista(L: list[str], etiqueta: str, items: Any, *, con_estado: bool = False) -> None:
    if not items:
        return
    L.append(f"- {etiqueta}:")
    for d in items:
        marca = ""
        if con_estado and d.get("estado") in ("hecho", "resuelto"):
            marca = f" [{d['estado']}]"
        fecha = _fecha_corta(d.get("creado_en"))
        sufijo = f" ({fecha})" if fecha else ""
        L.append(f"  · {d.get('contenido', '')}{marca}{sufijo}  id={d.get('id')}")


def _fecha_corta(iso: Any) -> str:
    if not isinstance(iso, str) or not iso:
        return ""
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return ""
    f = dt.astimezone(_LIMA)
    return f"{f.day} {_MESES[f.month - 1]}"


def _norm(s: str) -> str:
    r = (s or "").lower().strip()
    con, sin = "áàäâãéèëêíìïîóòöôõúùüûñ", "aaaaaeeeeiiiiooooouuuun"
    for i in range(len(con)):
        r = r.replace(con[i], sin[i])
    return r
