"""Registry tipado de acciones del agente.

Esta es LA base del "muchas más acciones": añadir una acción nueva = registrar
un `AccionDef`; el transporte (cliente.py) y el cerebro no cambian. Cada acción
declara su nombre, parámetros tipados, nivel de riesgo y handler.

Niveles de riesgo:
  - SEGURA: lectura inocua (listar/buscar/leer). Se ejecuta directo.
  - CONSECUENTE: cambia algo (mover/renombrar/crear). Se ejecuta SOLO si el
    envelope trae `confirmado=true` (gate del lado agente, defensa en
    profundidad sobre el gate del cerebro/app). Nunca por iniciativa del modelo.
  - PROHIBIDA: nunca se ejecuta. Placeholder defensivo (p. ej. borrar).
"""
from __future__ import annotations

import inspect
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class NivelRiesgo(str, Enum):
    SEGURA = "segura"
    CONSECUENTE = "consecuente"
    PROHIBIDA = "prohibida"


@dataclass(frozen=True)
class Param:
    nombre: str
    tipo: type
    requerido: bool = True
    descripcion: str = ""


Handler = Callable[
    ["dict[str, Any]", "Contexto"], "dict[str, Any] | Awaitable[dict[str, Any]]"
]


@dataclass(frozen=True)
class AccionDef:
    nombre: str
    descripcion: str
    parametros: tuple[Param, ...]
    nivel: NivelRiesgo
    handler: Handler


@dataclass
class Contexto:
    """Lo que un handler necesita para ejecutar. Se inyecta en cada llamada."""

    allowlist: list = field(default_factory=list)
    # Tope de lectura de texto en bytes (leer_archivo). Default 256 KB.
    max_lectura_bytes: int = 256 * 1024
    # Fase 6.2 — apps. `apps` es un mapa OPCIONAL de overrides explícitos
    # (nombre→exe), de AGENTE_PC_APPS_ALLOWLIST si el usuario fijó rutas. Ya NO
    # es un gate: en modo permisivo, cualquier app que el usuario nombre se
    # resuelve dinámicamente (`resolver_app`). La denylist dura (shells/sistema/
    # instaladores) sigue siendo el rail innegociable.
    apps: dict = field(default_factory=dict)
    # Resolver dinámico de nombre→exe (inyectable para tests). None → el real de
    # `apps.resolver_app_dinamica`. El handler resuelve el default (evita ciclo).
    resolver_app: Any = None
    # Procesos lanzados en ESTA sesión (nombre→[pid]). Lo llena abrir_app y lo
    # consume cerrar_app (solo cierra lo que abrió, jamás procesos ajenos).
    procesos: dict = field(default_factory=dict)
    # Inyección del lanzador/terminador de procesos (para tests sin spawn real).
    # None → se usan los reales de `apps.py`. El handler resuelve el default,
    # así Contexto no importa apps (evita ciclo de imports).
    lanzador: Any = None
    terminador: Any = None
    # Fase 6.3 — control de pantalla. Master switch (OFF por defecto), tope de
    # acciones por sesión, estado de la sesión, e inyectables (capturador /
    # controlador / indicador) para tests sin tocar el mouse/pantalla reales.
    control_pantalla: bool = False
    max_acciones_pantalla: int = 40
    pantalla_sesion: dict = field(default_factory=lambda: {"activa": False, "acciones": 0})
    capturador: Any = None
    controlador: Any = None
    indicador: Any = None


def _err(tipo: str, mensaje: str) -> dict[str, Any]:
    return {"ok": False, "tipo": tipo, "mensaje": mensaje}


class Registro:
    def __init__(self) -> None:
        self._acciones: dict[str, AccionDef] = {}

    def registrar(self, accion: AccionDef) -> None:
        if accion.nombre in self._acciones:
            raise ValueError(f"acción duplicada: {accion.nombre}")
        self._acciones[accion.nombre] = accion

    def get(self, nombre: str) -> AccionDef | None:
        return self._acciones.get(nombre)

    def nombres(self) -> list[str]:
        return sorted(self._acciones)

    def validar(self, accion: AccionDef, args: dict[str, Any]) -> tuple[bool, str]:
        for p in accion.parametros:
            presente = p.nombre in args and args[p.nombre] not in (None, "")
            if p.requerido and not presente:
                return False, f"falta el parámetro «{p.nombre}»"
            if p.nombre in args and args[p.nombre] is not None:
                if not isinstance(args[p.nombre], p.tipo):
                    return False, f"«{p.nombre}» debe ser {p.tipo.__name__}"
        return True, ""

    async def ejecutar(
        self,
        nombre: str,
        args: dict[str, Any],
        ctx: Contexto,
        *,
        confirmado: bool = False,
    ) -> dict[str, Any]:
        accion = self.get(nombre)
        if accion is None:
            return _err("desconocida", f"no existe la acción «{nombre}»")
        if accion.nivel is NivelRiesgo.PROHIBIDA:
            return _err("prohibida", f"la acción «{nombre}» está prohibida")
        if accion.nivel is NivelRiesgo.CONSECUENTE and not confirmado:
            # Gate del lado agente: una acción consecuente NO se ejecuta sin la
            # marca de confirmación que solo viaja por el canal de ejecución
            # confirmada del cerebro (tras el OK explícito del usuario en la
            # app). Falla cerrado: ante la duda, no muta nada.
            return _err(
                "requiere_confirmacion",
                f"«{nombre}» es consecuente y no llegó confirmada",
            )
        ok, motivo = self.validar(accion, args or {})
        if not ok:
            return _err("validacion", motivo)
        try:
            resultado = accion.handler(args or {}, ctx)
            if inspect.isawaitable(resultado):
                resultado = await resultado
            if not isinstance(resultado, dict):
                return _err("interno", "el handler no devolvió un dict")
            return resultado
        except Exception as e:  # noqa: BLE001 — nunca propagar al transporte
            return _err("interno", f"falló «{nombre}»: {type(e).__name__}")
