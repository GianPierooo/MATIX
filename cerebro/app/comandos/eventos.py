"""Comandos de EVENTOS / Calendario (2.0 · Fase 3).

Sigue el patrón de Fases 1-2: cada acción es UN comando con UN handler único, la
ÚNICA fuente de su lógica; el endpoint de la app y la tool de la IA son
envoltorios delgados sobre el MISMO handler. Consolida D4: formulario manual,
OCR de sílabo y la IA crean por `crear_evento` — una sola ruta, todas con acceso
a la recurrencia.

RECURRENCIA: la regla vive en la fila del evento (recurrencia_freq + …); la
expansión a ocurrencias la hace el motor ÚNICO `comandos/recurrencia.py` (el
mismo que usan el horario y las clases). No se materializan instancias.

EDITAR / BORRAR una serie recurrente — los tres alcances (estilo Google
Calendar), que es donde esto suele romperse, hecho a propósito:
  - "toda_serie" (default): edita/borra la regla entera. Comportamiento de
    siempre para eventos sueltos.
  - "solo_esta": detacha UNA ocurrencia. La fecha se agrega a
    `recurrencia_excepciones` de la serie (el motor la salta) y —al editar— se
    crea un evento ÚNICO con los cambios para ese día.
  - "esta_y_futuras": parte la serie. La original se corta el día anterior
    (recurrencia_hasta = fecha-1) y —al editar— nace una serie nueva desde la
    fecha con los cambios.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from ..db import Postgrest
from ..schemas.eventos import EventoCreate, EventoUpdate
from . import recurrencia
from .recurrencia import LIMA
from .registro import Comando, RegistroComandos, Riesgo, error, ok

TABLA = "eventos"

ALCANCES = ("toda_serie", "solo_esta", "esta_y_futuras")

# Campos que se clonan al detachar/partir una serie (NO recurrencia ni metadatos
# de sync/papelera, que son de la fila madre).
_CLONABLES = (
    "titulo", "descripcion", "ubicacion", "curso_id", "proyecto_id", "color",
    "todo_el_dia", "recordatorio_offset_min", "recordar_en",
)
_REC_CLONABLES = (
    "recurrencia_freq", "recurrencia_dias_semana", "recurrencia_fin_tipo",
    "recurrencia_hasta", "recurrencia_conteo",
)


# ── Helpers ───────────────────────────────────────────────────────────────────


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _uuid(raw: Any) -> str | None:
    try:
        return str(UUID(str(raw)))
    except (ValueError, TypeError):
        return None


def _err_validacion(e: ValidationError) -> dict[str, Any]:
    try:
        primero = e.errors()[0]
        campo = ".".join(str(x) for x in primero.get("loc", ())) or "campo"
        return error("validacion", f"«{campo}»: {primero.get('msg', 'inválido')}")
    except Exception:  # noqa: BLE001
        return error("validacion", "Datos inválidos.")


def _validar_regla(payload: dict[str, Any]) -> dict[str, Any] | None:
    """Valida los campos de recurrencia (si los hay). None = ok."""
    freq = payload.get("recurrencia_freq")
    if freq is None:
        return None
    if freq not in recurrencia.FREQS:
        return error("validacion", f"recurrencia_freq «{freq}» inválida (usa {recurrencia.FREQS}).")
    fin = payload.get("recurrencia_fin_tipo")
    if fin is not None and fin not in recurrencia.FIN_TIPOS:
        return error("validacion", f"recurrencia_fin_tipo «{fin}» inválido (usa {recurrencia.FIN_TIPOS}).")
    if fin == "hasta" and not payload.get("recurrencia_hasta"):
        return error("validacion", "Con fin 'hasta' necesito `recurrencia_hasta` (fecha YYYY-MM-DD).")
    if fin == "conteo" and not payload.get("recurrencia_conteo"):
        return error("validacion", "Con fin 'conteo' necesito `recurrencia_conteo` (nº de veces).")
    if freq == "semanal":
        dias = payload.get("recurrencia_dias_semana")
        if dias:
            for d in dias:
                try:
                    if not (1 <= int(d) <= 7):
                        raise ValueError
                except (ValueError, TypeError):
                    return error("validacion", "`recurrencia_dias_semana` van en ISO: 1=lunes … 7=domingo.")
    return None


def _fecha_ancla(evento: dict[str, Any]):
    ini = recurrencia._parse_dt(evento.get("inicia_en"))
    return ini.astimezone(LIMA).date() if ini else None


def _desplazar(iso: str | None, dias: int) -> str | None:
    """Desplaza un timestamp ISO `dias` días, preservando hora y duración."""
    dt = recurrencia._parse_dt(iso)
    if dt is None:
        return iso
    return (dt + timedelta(days=dias)).isoformat()


def _base_clonada(actual: dict[str, Any]) -> dict[str, Any]:
    return {c: actual.get(c) for c in _CLONABLES if actual.get(c) is not None}


def _aplicar_edits_no_rec(base: dict[str, Any], edits: dict[str, Any]) -> None:
    for k, v in edits.items():
        if not k.startswith("recurrencia"):
            base[k] = v


def _combinar_instancia(actual: dict[str, Any], edits: dict[str, Any], dias: int) -> dict[str, Any]:
    """Evento ÚNICO (sin recurrencia) para una ocurrencia detachada."""
    nuevo = _base_clonada(actual)
    nuevo["inicia_en"] = _desplazar(actual.get("inicia_en"), dias)
    if actual.get("termina_en"):
        nuevo["termina_en"] = _desplazar(actual.get("termina_en"), dias)
    _aplicar_edits_no_rec(nuevo, edits)
    return nuevo


def _combinar_serie(actual: dict[str, Any], edits: dict[str, Any], dias: int) -> dict[str, Any]:
    """Serie NUEVA (mantiene la recurrencia) desde la fecha del corte."""
    nuevo = _base_clonada(actual)
    for c in _REC_CLONABLES:
        if actual.get(c) is not None:
            nuevo[c] = actual.get(c)
    nuevo["inicia_en"] = _desplazar(actual.get("inicia_en"), dias)
    if actual.get("termina_en"):
        nuevo["termina_en"] = _desplazar(actual.get("termina_en"), dias)
    for k, v in edits.items():
        nuevo[k] = v
    return nuevo


async def _agregar_excepcion(db: Postgrest, actual: dict[str, Any], fecha) -> dict | None:
    exc = list(actual.get("recurrencia_excepciones") or [])
    f = fecha.isoformat()
    if f not in exc:
        exc.append(f)
    return await db.update(TABLA, actual["id"], {"recurrencia_excepciones": exc})


# ── Handlers ──────────────────────────────────────────────────────────────────


async def cmd_crear(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = EventoCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_none=True)
    err = _validar_regla(payload)
    if err:
        return err
    fila = await db.insert(TABLA, payload)
    return ok(fila)


async def cmd_editar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    evento_id = _uuid(params.get("evento_id"))
    if evento_id is None:
        return error("validacion", f"El id «{params.get('evento_id')}» no es un UUID válido.")
    alcance = params.get("alcance") or "toda_serie"
    if alcance not in ALCANCES:
        return error("validacion", f"alcance «{alcance}» inválido (usa {ALCANCES}).")
    fecha = recurrencia._parse_date(params.get("ocurrencia_fecha"))
    campos = {k: v for k, v in params.items()
              if k not in ("evento_id", "alcance", "ocurrencia_fecha")}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar del evento.")
    try:
        body = EventoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    edits = body.model_dump(mode="json", exclude_unset=True)
    err = _validar_regla(edits)
    if err:
        return err

    actual = await db.get(TABLA, evento_id)
    if actual is None:
        return error("no_existe", "Ese evento ya no está en el hub.")
    recurrente = recurrencia.es_recurrente(actual)

    # Camino simple: serie entera, o evento suelto (sin recurrencia).
    if alcance == "toda_serie" or not recurrente:
        fila = await db.update(TABLA, evento_id, edits)
        if fila is None:
            return error("no_existe", "Ese evento ya no está en el hub.")
        return ok(fila)

    # Alcances que tocan una ocurrencia concreta: requieren la fecha.
    if fecha is None:
        return error("validacion", "Para editar una sola ocurrencia dime la fecha (`ocurrencia_fecha` YYYY-MM-DD).")
    if actual.get("origen") == "google":
        return error("no_soportado", "Por ahora solo puedo editar TODA la serie de un evento de Google.")
    ancla = _fecha_ancla(actual)

    if alcance == "solo_esta":
        await _agregar_excepcion(db, actual, fecha)
        dias = (fecha - ancla).days if ancla else 0
        nuevo = _combinar_instancia(actual, edits, dias)
        fila = await db.insert(TABLA, nuevo)
        return ok({**fila, "_alcance": "solo_esta"})

    # esta_y_futuras
    if ancla is not None and fecha <= ancla:
        # Editar desde el ancla = toda la serie restante; no hace falta partir.
        fila = await db.update(TABLA, evento_id, edits)
        return ok(fila) if fila else error("no_existe", "Ese evento ya no está en el hub.")
    await db.update(TABLA, evento_id, {
        "recurrencia_fin_tipo": "hasta",
        "recurrencia_hasta": (fecha - timedelta(days=1)).isoformat(),
        "recurrencia_conteo": None,
    })
    dias = (fecha - ancla).days if ancla else 0
    nueva = _combinar_serie(actual, edits, dias)
    fila = await db.insert(TABLA, nueva)
    return ok({**fila, "_alcance": "esta_y_futuras"})


async def cmd_eliminar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Borrado SUAVE → papelera. Con alcance recurrente: "solo_esta" agrega una
    excepción; "esta_y_futuras" corta la serie."""
    evento_id = _uuid(params.get("evento_id"))
    if evento_id is None:
        return error("validacion", f"El id «{params.get('evento_id')}» no es un UUID válido.")
    alcance = params.get("alcance") or "toda_serie"
    if alcance not in ALCANCES:
        return error("validacion", f"alcance «{alcance}» inválido (usa {ALCANCES}).")
    fecha = recurrencia._parse_date(params.get("ocurrencia_fecha"))

    actual = await db.get(TABLA, evento_id)
    if actual is None:
        return error("no_existe", "Ese evento ya no está en el hub.")
    recurrente = recurrencia.es_recurrente(actual)

    if alcance == "toda_serie" or not recurrente:
        fila = await db.update(TABLA, evento_id, {"eliminado_en": _ahora_iso()})
        if fila is None:
            return error("no_existe", "Ese evento ya no está en el hub.")
        return ok({**fila, "alcance": "toda_serie"})

    if fecha is None:
        return error("validacion", "Para borrar una sola ocurrencia dime la fecha (`ocurrencia_fecha` YYYY-MM-DD).")
    if actual.get("origen") == "google":
        return error("no_soportado", "Por ahora solo puedo borrar TODA la serie de un evento de Google.")
    ancla = _fecha_ancla(actual)

    if alcance == "solo_esta":
        fila = await _agregar_excepcion(db, actual, fecha)
        return ok({**(fila or actual), "alcance": "solo_esta", "fecha": fecha.isoformat()})

    # esta_y_futuras
    if ancla is not None and fecha <= ancla:
        fila = await db.update(TABLA, evento_id, {"eliminado_en": _ahora_iso()})
    else:
        fila = await db.update(TABLA, evento_id, {
            "recurrencia_fin_tipo": "hasta",
            "recurrencia_hasta": (fecha - timedelta(days=1)).isoformat(),
            "recurrencia_conteo": None,
        })
    return ok({**(fila or actual), "alcance": "esta_y_futuras"})


async def cmd_restaurar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    evento_id = _uuid(params.get("evento_id"))
    if evento_id is None:
        return error("validacion", f"El id «{params.get('evento_id')}» no es un UUID válido.")
    # Restaurar limpia también los metadatos de Google (el evento allá ya se
    # borró cuando fue a papelera); el router re-empuja si hay conexión.
    fila = await db.update(TABLA, evento_id, {
        "eliminado_en": None,
        "external_id": None,
        "external_account": None,
        "google_updated_at": None,
    })
    if fila is None:
        return error("no_existe", "Ese evento ya no está en el hub.")
    return ok(fila)


async def cmd_consultar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Eventos con ≥1 ocurrencia en [desde, hasta]. Expande la recurrencia con
    el motor único (respeta fin/conteo/excepciones)."""
    desde = recurrencia._parse_date(params.get("desde"))
    hasta = recurrencia._parse_date(params.get("hasta"))
    if desde is None or hasta is None:
        return error("validacion", "Faltan `desde` / `hasta` en formato YYYY-MM-DD.")
    if hasta < desde:
        desde, hasta = hasta, desde
    eventos = await db.list(TABLA, raw_filters={"eliminado_en": "is.null"})
    out: list[dict[str, Any]] = []
    for e in eventos:
        ocs = recurrencia.ocurrencias_en_rango(e, desde, hasta)
        if not ocs:
            continue
        out.append({
            "id": e.get("id"),
            "titulo": e.get("titulo"),
            "inicia_en": e.get("inicia_en"),
            "termina_en": e.get("termina_en"),
            "todo_el_dia": bool(e.get("todo_el_dia")),
            "se_repite": recurrencia.es_recurrente(e),
            "ocurrencias": [d.isoformat() for d in ocs[:60]],
        })
    out.sort(key=lambda x: x.get("inicia_en") or "")
    return ok({
        "desde": desde.isoformat(),
        "hasta": hasta.isoformat(),
        "total": len(out),
        "eventos": out[:60],
    })


# ── Registro ──────────────────────────────────────────────────────────────────


def registrar(reg: RegistroComandos) -> None:
    """Registra los comandos de Eventos. Lo llama `comandos/__init__.py`."""
    reg.registrar(Comando(
        "crear_evento", "Agenda un evento (soporta recurrencia).",
        Riesgo.CONSECUENTE, cmd_crear, ("eventos",)))
    reg.registrar(Comando(
        "editar_evento", "Edita un evento (alcance: toda_serie / solo_esta / esta_y_futuras).",
        Riesgo.CONSECUENTE, cmd_editar, ("eventos",)))
    reg.registrar(Comando(
        "eliminar_evento", "Manda un evento a la papelera (con alcance para recurrentes).",
        Riesgo.CONSECUENTE, cmd_eliminar, ("eventos",)))
    reg.registrar(Comando(
        "restaurar_evento", "Restaura un evento de la papelera.",
        Riesgo.CONSECUENTE, cmd_restaurar, ("eventos",)))
    reg.registrar(Comando(
        "consultar_eventos", "Lista eventos con ocurrencias en un rango.",
        Riesgo.SEGURA, cmd_consultar, ()))
