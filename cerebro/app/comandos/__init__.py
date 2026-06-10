"""Capa de comandos (2.0 · Fase 1).

`registro` es el singleton con todos los comandos del hub. Se puebla aquí, una
sola vez, llamando al `registrar(reg)` de cada sección. Para sumar una sección
nueva (Fase 2+): importar su módulo y llamar a su `registrar(registro)`.

Uso desde un envoltorio (router o tool):
    from ..comandos import registro
    res = await registro.ejecutar(db, "crear_tarea", params, origen="ui")
"""
from __future__ import annotations

from . import eventos as _eventos
from . import planificador as _planificador
from . import proyectos as _proyectos
from . import tareas as _tareas
from . import universidad as _universidad
from .registro import Comando, RegistroComandos, Riesgo, error, ok, registro

# Poblar el registro. Cada sección registra sus comandos aquí.
_tareas.registrar(registro)
_universidad.registrar(registro)
_eventos.registrar(registro)
_proyectos.registrar(registro)
_planificador.registrar(registro)

__all__ = ["registro", "RegistroComandos", "Comando", "Riesgo", "ok", "error"]
