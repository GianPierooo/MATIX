"""Tests del flujo de sesión de estudio (Capa 3 Paso 3).

Lo que valida este suite:

1. Cuando el usuario dice "tomame examen de mi apunte sobre X" la
   sesión arranca **desde el apunte correcto** — buscar_apuntes
   recibe la consulta, leer_apunte recibe el id del top match (no
   inventa otro), y el modelo recibe el contenido completo para
   formular la primera pregunta.

2. Que tras feedback + nueva pregunta, el segundo turno NO repite
   buscar_apuntes/leer_apunte (ya tiene el contenido en historial)
   — confirma que el flujo no es despilfarrador con tokens.

Mockeamos `llm.responder_con_tools` para simular las decisiones del
modelo; las tools corren reales (`buscar_apuntes` pega a OpenAI
para el embedding, `leer_apunte` pega a Supabase). Eso valida la
infraestructura completa de la sesión.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.db import Postgrest
from app.matix import chat as chat_module
from app.matix import llm
from app.matix.indexador import indexar_apunte


async def test_sesion_arranca_desde_apunte_correcto(
    _fresh_db: Postgrest, client: AsyncClient, monkeypatch
) -> None:
    """El usuario pide examen sobre un tema; verificamos que
    leer_apunte recibe el id del apunte sembrado (no otro)."""
    # 1) Sembrar apunte con contenido específico.
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_sesion_continuidad",
                "contenido": (
                    "Una función f es continua en a si: el límite cuando "
                    "x tiende a a existe, f(a) está definida, y ambos "
                    "coinciden. Las discontinuidades pueden ser "
                    "removibles (el límite existe pero f(a) ≠ lim), "
                    "de salto (límites laterales distintos) o "
                    "esenciales (el límite no existe)."
                ),
                "etiquetas": ["test", "calculo"],
            },
        )
    ).json()
    aid_esperado = creado["id"]

    try:
        await indexar_apunte(_fresh_db, creado)

        # 2) Track de tools llamadas.
        args_por_tool: dict[str, list[dict]] = {}

        # 3) Simulación de las vueltas del modelo durante la apertura
        #    de la sesión:
        #       v1: decide buscar_apuntes
        #       v2: con el match en mano, decide leer_apunte
        #       v3: con el contenido completo, formula la primera
        #           pregunta (texto). Acá el orquestador devuelve.
        secuencia: list[dict] = [
            {
                "tipo": "tool_calls",
                "tool_calls": [
                    {
                        "id": "c1",
                        "nombre": "buscar_apuntes",
                        "args": {
                            "consulta": "continuidad de funciones",
                            "top_k": 3,
                        },
                    }
                ],
                "raw": {"role": "assistant", "tool_calls": [
                    {"id": "c1", "type": "function",
                     "function": {"name": "buscar_apuntes",
                                  "arguments": "{}"}}
                ]},
            },
            None,  # se rellena dinámico cuando sepamos el id del top match
            {
                "tipo": "texto",
                "contenido": (
                    "Dale, te voy a tomar examen de «_test_sesion_continuidad». "
                    "Una pregunta a la vez. Empezamos suave: ¿qué tres "
                    "condiciones tiene que cumplir una función para ser "
                    "continua en un punto?"
                ),
                "raw": {"role": "assistant", "content": "..."},
            },
        ]

        idx = {"i": 0}
        import json as _json

        async def fake_responder_con_tools(messages, tools, **kw):
            i = idx["i"]
            # Antes de devolver la vuelta 2, leemos el resultado de
            # la búsqueda (último tool message) y armamos la llamada
            # a leer_apunte con el id del top match.
            if i == 1:
                ultimo_tool = next(
                    m for m in reversed(messages) if m.get("role") == "tool"
                )
                resultado = _json.loads(ultimo_tool["content"])
                primer_id = resultado["datos"]["resultados"][0]["apunte_id"]
                secuencia[1] = {
                    "tipo": "tool_calls",
                    "tool_calls": [
                        {
                            "id": "c2",
                            "nombre": "leer_apunte",
                            "args": {"apunte_id": primer_id},
                        }
                    ],
                    "raw": {"role": "assistant", "tool_calls": [
                        {"id": "c2", "type": "function",
                         "function": {"name": "leer_apunte",
                                      "arguments": "{}"}}
                    ]},
                }
            idx["i"] += 1
            return secuencia[i]

        monkeypatch.setattr(
            llm, "responder_con_tools", fake_responder_con_tools
        )

        # Espiar ejecutar_tool sin alterar su comportamiento.
        from app.matix import tools as tools_module
        ejecutar_original = tools_module.ejecutar_tool

        async def espia(db, nombre, args):
            args_por_tool.setdefault(nombre, []).append(args)
            return await ejecutar_original(db, nombre, args)

        monkeypatch.setattr(chat_module, "ejecutar_tool", espia)

        # 4) Disparar como si el usuario hubiera dicho la frase
        #    típica de inicio de sesión.
        resultado = await chat_module.conversar(
            _fresh_db,
            historial=[],
            mensaje="tomame examen de mi apunte sobre continuidad",
        )

        # ─── Verificaciones ───────────────────────────────────────

        # El flujo correcto es: buscar_apuntes → leer_apunte → texto.
        # Si el modelo intentara saltarse leer_apunte o llamara a
        # otra tool inesperada, este assert lo agarra.
        assert resultado["tools_usadas"] == ["buscar_apuntes", "leer_apunte"]

        # leer_apunte fue llamado con el id del apunte sembrado.
        assert "leer_apunte" in args_por_tool
        ids_leidos = [a["apunte_id"] for a in args_por_tool["leer_apunte"]]
        assert aid_esperado in ids_leidos, (
            f"esperaba que leyera el apunte sembrado {aid_esperado}, "
            f"leyó: {ids_leidos}"
        )

        # La primera pregunta llegó al usuario (texto no vacío).
        assert resultado["respuesta"]
        # Y es UNA pregunta (terminada en '?') — la regla de "una
        # por turno" la enforce el system prompt; acá verificamos
        # que la respuesta del fake tiene esa forma.
        assert "?" in resultado["respuesta"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid_esperado}/permanente")


async def test_sesion_no_re_lee_apunte_en_segundo_turno(
    _fresh_db: Postgrest, client: AsyncClient, monkeypatch
) -> None:
    """Una vez cargado el apunte, los turnos siguientes (respuesta
    del usuario → feedback + nueva pregunta) NO deberían reabrir
    buscar_apuntes ni leer_apunte. Si lo hicieran, sería un
    despilfarro de tokens y latencia."""
    # Simulamos el segundo turno: el historial ya tiene el resultado
    # de la primera pregunta. El modelo solo debería devolver texto
    # con feedback + la próxima pregunta. NO tools.
    secuencia = [
        {
            "tipo": "texto",
            "contenido": (
                "Bien, las tres condiciones están correctas: límite "
                "existe, f(a) definida, y coinciden. Tu apunte lo "
                "dice así. Ahora dale: ¿qué tipo de discontinuidad "
                "tendría f(x) = sin(1/x) cerca de 0?"
            ),
            "raw": {"role": "assistant", "content": "..."},
        },
    ]
    idx = {"i": 0}

    async def fake(messages, tools, **kw):
        idx["i"] += 1
        return secuencia[0]

    monkeypatch.setattr(llm, "responder_con_tools", fake)

    # Historial simula: usuario inició sesión, Matix cargó el apunte
    # y preguntó, usuario respondió. Ahora el siguiente turno.
    historial = [
        {"rol": "user", "contenido": "tomame examen de continuidad"},
        {
            "rol": "assistant",
            "contenido": (
                "Dale. ¿Qué condiciones tiene que cumplir una función "
                "para ser continua en un punto?"
            ),
        },
    ]
    resultado = await chat_module.conversar(
        _fresh_db,
        historial=historial,
        mensaje=(
            "el límite tiene que existir, f(a) tiene que estar "
            "definida, y los dos tienen que coincidir"
        ),
    )

    # Sin tools usadas — el modelo respondió texto directo.
    assert resultado["tools_usadas"] == []
    # La respuesta termina con la próxima pregunta.
    assert "?" in resultado["respuesta"]
