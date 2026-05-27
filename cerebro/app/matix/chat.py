"""Orquestador de conversación con Matix.

Recibe un mensaje del usuario + historial previo y devuelve la
respuesta. Arma el system prompt en este orden:

1. Reglas + tono + descripción de las herramientas (fijos).
2. Documento Maestro literal (fijo).
3. Contexto vivo del hub (proyectos activos con ids, tareas próximas
   con ids, eventos, cursos con ids…).

(1) y (2) se mantienen idénticos entre turnos → OpenAI los cachea
automáticamente. (3) varía cada turno pero va al final, así no rompe
el prefijo cacheado.

A partir de Capa 2 Paso 2, este módulo también maneja el **loop de
tool calling**: si el modelo pide ejecutar una herramienta, la
corremos, le devolvemos el resultado, y volvemos a llamar al modelo
para que narre lo que hizo (o encadene la siguiente acción). El
loop está acotado por `_MAX_VUELTAS` para evitar que un modelo
descalibrado dispare herramientas en bucle.
"""
from __future__ import annotations

import json
from typing import Any

from ..db import Postgrest
from . import llm
from .contexto import contexto_vivo
from .system_prompt import system_prompt_fijo
from .tools import TABLAS_AFECTADAS, TOOL_DEFINITIONS, ejecutar_tool

# Tope de iteraciones del loop modelo↔tools. Generoso pero finito:
# 6 cubre el caso "ejecutar 3 tools, ver resultado, narrar" con
# margen. Si se alcanza, devolvemos lo último que dijo el modelo y
# cortamos.
_MAX_VUELTAS = 6


async def conversar(
    db: Postgrest,
    *,
    historial: list[dict],
    mensaje: str,
) -> dict[str, Any]:
    """Genera la respuesta de Matix a `mensaje`, considerando
    `historial` (lista de `{rol, contenido}` con `rol` en
    `user`/`assistant`).

    Devuelve un dict:

        {
            "respuesta": "<texto final para mostrarle al usuario>",
            "tools_usadas": ["crear_tarea", ...],   # nombres
            "tablas_cambiadas": ["tareas", ...],    # para invalidar UI
        }

    Si el modelo devuelve texto sin tools, `tools_usadas` y
    `tablas_cambiadas` son listas vacías.
    """
    fijo = system_prompt_fijo()
    contexto = await contexto_vivo(db)

    mensajes: list[dict] = [
        {"role": "system", "content": fijo},
        {"role": "system", "content": contexto},
    ]
    for m in historial:
        rol = m.get("rol") or m.get("role")
        if rol not in ("user", "assistant"):
            continue
        mensajes.append({"role": rol, "content": m["contenido"]})
    mensajes.append({"role": "user", "content": mensaje})

    tools_usadas: list[str] = []
    tablas_cambiadas: list[str] = []

    ultima_respuesta = ""

    for _ in range(_MAX_VUELTAS):
        salida = await llm.responder_con_tools(mensajes, TOOL_DEFINITIONS)

        if salida["tipo"] == "texto":
            ultima_respuesta = salida["contenido"]
            break

        # tipo == "tool_calls": metemos el mensaje del modelo (con
        # los tool_call_id) y a continuación una respuesta `tool`
        # por cada call. Luego volvemos a llamar al modelo.
        mensajes.append(salida["raw"])

        for call in salida["tool_calls"]:
            nombre = call["nombre"]
            args = call["args"]
            tools_usadas.append(nombre)

            resultado = await ejecutar_tool(db, nombre, args)

            if resultado.get("ok"):
                for tabla in TABLAS_AFECTADAS.get(nombre, []):
                    if tabla not in tablas_cambiadas:
                        tablas_cambiadas.append(tabla)

            mensajes.append(
                {
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(
                        resultado, ensure_ascii=False
                    ),
                }
            )
    else:
        # Se agotaron las vueltas sin que el modelo cerrara con
        # texto. Damos algo razonable.
        ultima_respuesta = (
            ultima_respuesta
            or "Hice varias acciones pero me enredé al narrarlas. "
            "Revisá el hub: lo último debería estar reflejado."
        )

    return {
        "respuesta": ultima_respuesta,
        "tools_usadas": tools_usadas,
        "tablas_cambiadas": tablas_cambiadas,
    }
