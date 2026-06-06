"""Registry tipado de acciones del agente.

Esta es LA base del "muchas más acciones": añadir una acción nueva = registrar
un `AccionDef`; el transporte (cliente.py) y el cerebro no cambian. Cada acción
declara su nombre, parámetros tipados, nivel de riesgo y handler.

Niveles de riesgo:
  - SEGURA: lectura inocua (p. ej. listar nombres). Se ejecuta directo.
  - CONSECUENTE: cambia algo (mover/escribir/borrar). Requerirá confirmación;
    en 6.0a NO se ejecuta todavía (no hay canal de confirmación).
  - PROHIBIDA: nunca se ejecuta. Placeholder defensivo.
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
        self, nombre: str, args: dict[str, Any], ctx: Contexto
    ) -> dict[str, Any]:
        accion = self.get(nombre)
        if accion is None:
            return _err("desconocida", f"no existe la acción «{nombre}»")
        if accion.nivel is NivelRiesgo.PROHIBIDA:
            return _err("prohibida", f"la acción «{nombre}» está prohibida")
        if accion.nivel is not NivelRiesgo.SEGURA:
            # 6.0a solo ejecuta acciones SEGURAS. El canal de confirmación para
            # acciones consecuentes llega en una fase posterior.
            return _err(
                "requiere_confirmacion",
                f"«{nombre}» es consecuente y aún no hay canal de confirmación",
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
