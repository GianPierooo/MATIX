"""Acciones concretas del agente.

6.0a registra UNA sola acción: `listar_carpeta` (nivel SEGURA). Devuelve solo
nombres de archivos/carpetas — NUNCA el contenido. Las entradas sensibles
(.env, llaves, .ssh…) se ocultan vía `seguridad.entrada_oculta`.

Patrón para añadir acciones después: define un handler `(args, ctx) -> dict`,
declara su `AccionDef` con su nivel de riesgo y regístralo en `crear_registro`.
"""
from __future__ import annotations

import os
from typing import Any

from .registro import AccionDef, Contexto, NivelRiesgo, Param, Registro
from .seguridad import entrada_oculta, ruta_permitida

# Tope de entradas por listado (evita payloads gigantes / DoS accidental).
MAX_ENTRADAS = 1000

# Nombres comunes → carpeta real bajo el home. Conveniencia para que el usuario
# diga "lista mi carpeta Documentos" sin la ruta completa. Sigue pasando por la
# allowlist/denylist: esto NO salta ningún rail, solo traduce el nombre.
_CARPETAS_COMUNES = {
    "documentos": "~/Documents",
    "documents": "~/Documents",
    "escritorio": "~/Desktop",
    "desktop": "~/Desktop",
    "descargas": "~/Downloads",
    "downloads": "~/Downloads",
}


def _resolver_nombre(ruta: str) -> str:
    bruto = (ruta or "").strip()
    clave = bruto.lower().strip("/\\")
    if not os.path.isabs(bruto) and clave in _CARPETAS_COMUNES:
        return _CARPETAS_COMUNES[clave]
    return bruto


def _listar_carpeta(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    veredicto = ruta_permitida(ruta, ctx.allowlist)
    if not veredicto.permitida:
        # Mensaje genérico: no revela estructura fuera de la allowlist.
        return {
            "ok": False,
            "tipo": "rechazada",
            "mensaje": "esa carpeta no está permitida",
            "motivo": veredicto.motivo,
        }

    real = os.path.realpath(os.path.expanduser(str(ruta)))
    if not os.path.isdir(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es una carpeta accesible"}

    entradas: list[dict[str, str]] = []
    truncado = False
    try:
        with os.scandir(real) as it:
            for entrada in it:
                if entrada_oculta(entrada.name):
                    continue
                try:
                    es_dir = entrada.is_dir()
                except OSError:
                    es_dir = False
                entradas.append(
                    {"nombre": entrada.name, "tipo": "carpeta" if es_dir else "archivo"}
                )
                if len(entradas) >= MAX_ENTRADAS:
                    truncado = True
                    break
    except PermissionError:
        return {"ok": False, "tipo": "sin_permiso", "mensaje": "el sistema no me deja leer esa carpeta"}

    entradas.sort(key=lambda e: (e["tipo"] != "carpeta", e["nombre"].lower()))
    return {
        "ok": True,
        "ruta": real,
        "entradas": entradas,
        "total": len(entradas),
        "truncado": truncado,
    }


LISTAR_CARPETA = AccionDef(
    nombre="listar_carpeta",
    descripcion=(
        "Lista los nombres de archivos y carpetas dentro de una ruta permitida. "
        "NO devuelve el contenido de los archivos."
    ),
    parametros=(Param("ruta", str, requerido=True, descripcion="Ruta de la carpeta a listar."),),
    nivel=NivelRiesgo.SEGURA,
    handler=_listar_carpeta,
)


def crear_registro() -> Registro:
    """Registro con todas las acciones de esta fase. Una sola por ahora."""
    reg = Registro()
    reg.registrar(LISTAR_CARPETA)
    return reg
