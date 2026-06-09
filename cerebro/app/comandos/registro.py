"""Registro de COMANDOS — el cimiento de la capa de comandos unificada (2.0 · Fase 1).

EL PRINCIPIO (no negociable):
  Cada capacidad del usuario = UN comando tipado con UN handler único. Ese
  handler es el ÚNICO lugar con lógica. Los endpoints REST de la app y las tools
  de la IA son ENVOLTORIOS DELGADOS que llaman al mismo comando. Nadie más tiene
  lógica propia → la IA hereda EXACTAMENTE la superficie de la UI, sin una capa
  paralela que se desincronice (que era la fuente de bugs como "la captura se
  creó como Evento").

CÓMO REPLICAR ESTO EN CADA FASE (la receta, para no improvisar):
  1. Crear `comandos/<seccion>.py` con un `registrar(reg)` que registra los
     `Comando` de esa sección. El handler tiene la lógica canónica (mover ahí lo
     que hoy está duplicado entre el router y la tool — no reescribir desde cero).
  2. Sumar ese `registrar` en `comandos/__init__.py`.
  3. En el router de la sección: reemplazar la lógica por `reg.ejecutar(...)` y
     mapear el resultado a HTTP (ok→body, error→status). Cero lógica en el router.
  4. En `tools.py`: el handler de la tool llama a `reg.ejecutar(...)` y le da
     forma al resultado para el LLM (envelope compacto). Cero lógica en la tool.
  5. Si dos caminos hacían lo mismo por código distinto, ahora convergen en el
     comando. Borrar la copia duplicada.

CONTRATO del handler: `async def handler(db, params: dict) -> dict`, devolviendo
el resultado CANÓNICO:
  - éxito: `{"ok": True, "datos": <entidad o efecto>}`  (usar `ok()`)
  - error: `{"ok": False, "tipo": "...", "mensaje": "..."}`  (usar `error()`)
`datos` lleva lo necesario para que TODOS los envoltorios construyan su salida
(el router suele devolver la fila completa; la tool extrae campos compactos).

NIVELES DE RIESGO (mismo patrón de 3 clases del teléfono/PC, reusable para el
gate de fases futuras): segura / consecuente / prohibida. En Fase 1 solo se
ANOTA el riesgo y se loggea cada invocación (cimiento del audit); el gate de
confirmación de acciones consecuentes es Fase 4 — aquí NO se cambia el
comportamiento actual (lo que hoy no pide confirmación, sigue sin pedirla).
"""
from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from ..db import Postgrest

logger = logging.getLogger("matix.comandos")


class Riesgo(str, Enum):
    """Clasificación de riesgo (reusa el patrón de teléfono/PC)."""

    SEGURA = "segura"           # lectura / sin efecto irreversible
    CONSECUENTE = "consecuente"  # muta estado (crear/editar/completar/borrar suave)
    PROHIBIDA = "prohibida"      # nunca se ejecuta por este canal (placeholder)


# ── Resultado canónico ───────────────────────────────────────────────────────


def ok(datos: dict[str, Any]) -> dict[str, Any]:
    return {"ok": True, "datos": datos}


def error(tipo: str, mensaje: str, **extra: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"ok": False, "tipo": tipo, "mensaje": mensaje}
    out.update(extra)
    return out


Handler = Callable[[Postgrest, "dict[str, Any]"], Awaitable["dict[str, Any]"]]


@dataclass(frozen=True)
class Comando:
    """Una acción del hub. `handler` es la ÚNICA fuente de su lógica."""

    nombre: str
    descripcion: str
    riesgo: Riesgo
    handler: Handler
    # Tablas del hub que el comando afecta (para que la app invalide sus
    # providers). Equivale a `TABLAS_AFECTADAS` de las tools, pero junto al
    # comando: una sola fuente.
    tablas: tuple[str, ...] = field(default_factory=tuple)


class RegistroComandos:
    """Catálogo de comandos. Se puebla una vez (en `comandos.__init__`)."""

    def __init__(self) -> None:
        self._cmds: dict[str, Comando] = {}

    def registrar(self, comando: Comando) -> None:
        if comando.nombre in self._cmds:
            raise ValueError(f"comando duplicado: {comando.nombre}")
        self._cmds[comando.nombre] = comando

    def get(self, nombre: str) -> Comando | None:
        return self._cmds.get(nombre)

    def existe(self, nombre: str) -> bool:
        return nombre in self._cmds

    def nombres(self) -> list[str]:
        return sorted(self._cmds)

    def tablas_de(self, nombre: str) -> tuple[str, ...]:
        c = self._cmds.get(nombre)
        return c.tablas if c else ()

    async def ejecutar(
        self,
        db: Postgrest,
        nombre: str,
        params: dict[str, Any] | None = None,
        *,
        origen: str = "?",
    ) -> dict[str, Any]:
        """Ejecuta un comando por nombre. SIEMPRE devuelve un dict canónico
        (nunca lanza al caller). Loggea cada invocación (cimiento del audit).

        `origen` identifica quién invoca ("ui", "ia", "captura", "bloque", …)
        para el log — útil para diagnosticar y, en Fase 4, para el gate."""
        cmd = self._cmds.get(nombre)
        if cmd is None:
            logger.warning("comando desconocido: %s (origen=%s)", nombre, origen)
            return error("desconocido", f"No existe el comando «{nombre}».")
        if cmd.riesgo is Riesgo.PROHIBIDA:
            logger.info("comando=%s origen=%s BLOQUEADO (prohibida)", nombre, origen)
            return error("prohibida", f"El comando «{nombre}» está prohibido.")
        try:
            res = await cmd.handler(db, params or {})
            if not isinstance(res, dict):
                res = error("interno", f"«{nombre}» no devolvió un resultado válido.")
        except Exception as e:  # noqa: BLE001 — el comando nunca tumba al caller
            logger.exception("comando «%s» reventó (origen=%s)", nombre, origen)
            res = error("interno", f"Algo falló en «{nombre}» ({type(e).__name__}).")
        es_ok = bool(res.get("ok"))
        logger.info(
            "comando=%s origen=%s riesgo=%s ok=%s%s",
            nombre, origen, cmd.riesgo.value, es_ok,
            "" if es_ok else f" tipo={res.get('tipo')}",
        )
        return res


# Singleton del registro. Se POBLA en `comandos/__init__.py` (importar desde ahí).
registro = RegistroComandos()
