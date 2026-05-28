"""Tests del modo tutor (Capa 3 Paso 2).

Probamos:

1. `leer_apunte` — devuelve contenido completo, valida id, filtra
   apuntes en papelera.
2. Flujo tutor end-to-end mockeando el modelo: cuando el usuario
   pide "resume mi apunte X", el orquestador `conversar` llama
   `buscar_apuntes` → `leer_apunte(id)` → devuelve un resumen.
   Verificamos que el id que llegó a `leer_apunte` es el del
   apunte sembrado (no inventó ni mezcló).

El test del flujo es lo que pidió el usuario explícitamente:
"al menos uno de que las preguntas o el resumen salgan del apunte
correcto". Acá mockeamos `llm.responder_con_tools` para que simule
las decisiones del modelo, pero las tools (`buscar_apuntes`,
`leer_apunte`) corren REAL — embeddings de OpenAI + Postgres.
Así verificamos la cadena infraestructura completa.
"""
from __future__ import annotations

import json
from uuid import uuid4

from httpx import AsyncClient

from app.db import Postgrest
from app.matix import chat as chat_module
from app.matix import llm
from app.matix.indexador import indexar_apunte
from app.matix.tools import ejecutar_tool


# ── leer_apunte (tool dispatcher) ────────────────────────────────────


async def test_leer_apunte_id_invalido(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(_fresh_db, "leer_apunte", {"apunte_id": "no-uuid"})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


async def test_leer_apunte_inexistente(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(
        _fresh_db, "leer_apunte", {"apunte_id": str(uuid4())}
    )
    assert r["ok"] is False
    assert r["tipo"] == "no_existe"


async def test_leer_apunte_devuelve_contenido_completo(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """A diferencia de `buscar_apuntes` que recorta a 600 chars,
    `leer_apunte` trae el contenido entero."""
    # Contenido bien más largo que 600 chars.
    contenido = (
        "Esto es un apunte de prueba sobre arquitectura por capas. "
        * 30  # ~1.7k chars
    )
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_tutor_largo",
                "contenido": contenido,
                "etiquetas": ["test"],
            },
        )
    ).json()
    aid = creado["id"]
    try:
        r = await ejecutar_tool(_fresh_db, "leer_apunte", {"apunte_id": aid})
        assert r["ok"], r
        assert r["datos"]["titulo"] == "_test_tutor_largo"
        # El contenido completo, no recortado.
        assert r["datos"]["contenido"] == contenido
        assert len(r["datos"]["contenido"]) > 600
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_leer_apunte_en_papelera_no_se_lee(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """Si el apunte está soft-deleted, `leer_apunte` lo trata como
    inexistente — Matix nunca debe leer contenido borrado."""
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={"titulo": "_test_tutor_papelera", "contenido": "secreto"},
        )
    ).json()
    aid = creado["id"]
    try:
        # Verificamos que en activo se lee bien.
        r1 = await ejecutar_tool(_fresh_db, "leer_apunte", {"apunte_id": aid})
        assert r1["ok"]
        assert r1["datos"]["contenido"] == "secreto"

        # Mandar a papelera.
        await client.delete(f"/api/v1/apuntes/{aid}")

        # Ahora no se puede leer.
        r2 = await ejecutar_tool(_fresh_db, "leer_apunte", {"apunte_id": aid})
        assert r2["ok"] is False
        assert r2["tipo"] == "en_papelera"
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


# ── Flujo end-to-end del tutor con modelo mockeado ──────────────────


async def test_flujo_tutor_resume_apunte_correcto(
    _fresh_db: Postgrest, client: AsyncClient, monkeypatch
) -> None:
    """Sembramos UN apunte con contenido específico. Mockeamos al
    modelo para que decida el flujo tutor:

        1. buscar_apuntes("arquitectura hexagonal")
        2. leer_apunte(id del top match)
        3. responder con resumen

    Verificamos que `leer_apunte` recibió EXACTAMENTE el id del
    apunte sembrado — no inventó otro ni mezcló.
    """
    # 1) Sembrar el apunte con contenido bien diferenciado.
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_tutor_arq_hex",
                "contenido": (
                    "Notas sobre arquitectura hexagonal. La idea "
                    "central es separar el dominio del mundo exterior "
                    "mediante puertos (interfaces) y adaptadores "
                    "(implementaciones). El dominio no conoce HTTP, "
                    "ni Postgres, ni Kafka — solo expone puertos que "
                    "los adaptadores implementan. Esto invierte la "
                    "dependencia: la infraestructura depende del "
                    "dominio, no al revés."
                ),
                "etiquetas": ["test"],
            },
        )
    ).json()
    aid_esperado = creado["id"]

    try:
        # 2) Indexar para que `buscar_apuntes` lo encuentre.
        await indexar_apunte(_fresh_db, creado)

        # 3) Track de los args con los que se llamaron las tools.
        args_por_tool: dict[str, list[dict]] = {}

        # 4) Simular las decisiones del modelo turno por turno.
        secuencia = [
            # Vuelta 1: el modelo decide buscar.
            {
                "tipo": "tool_calls",
                "tool_calls": [
                    {
                        "id": "call_buscar_1",
                        "nombre": "buscar_apuntes",
                        "args": {
                            "consulta": "arquitectura hexagonal puertos y adaptadores",
                            "top_k": 3,
                        },
                    }
                ],
                "raw": {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": "call_buscar_1",
                            "type": "function",
                            "function": {
                                "name": "buscar_apuntes",
                                "arguments": "{}",
                            },
                        }
                    ],
                },
            },
            # Vuelta 2: con el resultado de la búsqueda en mano, el
            # modelo decide leer el TOP match para obtener el
            # contenido completo. El id que pase ACÁ es lo que el
            # test verifica.
            None,  # se rellena dinámicamente más abajo
            # Vuelta 3: con el contenido completo, el modelo
            # responde el resumen.
            {
                "tipo": "texto",
                "contenido": (
                    "Resumen de tu apunte «_test_tutor_arq_hex»: "
                    "separación dominio/exterior vía puertos y "
                    "adaptadores; el dominio expone interfaces, la "
                    "infra las implementa; inversión de dependencias."
                ),
                "raw": {
                    "role": "assistant",
                    "content": "Resumen ...",
                },
            },
        ]

        idx = {"i": 0}

        async def fake_responder_con_tools(messages, tools, **kw):
            i = idx["i"]
            # Capturamos los args de las últimas tool_messages para
            # poder reaccionar dinámicamente.
            if i == 1:
                # Buscamos el último tool message en `messages` (el
                # resultado de buscar_apuntes). Extraemos el top
                # apunte_id de ahí y armamos la llamada a leer_apunte.
                ultimo_tool_msg = next(
                    m for m in reversed(messages) if m.get("role") == "tool"
                )
                resultado_busqueda = json.loads(ultimo_tool_msg["content"])
                primer_id = resultado_busqueda["datos"]["resultados"][0][
                    "apunte_id"
                ]
                secuencia[1] = {
                    "tipo": "tool_calls",
                    "tool_calls": [
                        {
                            "id": "call_leer_1",
                            "nombre": "leer_apunte",
                            "args": {"apunte_id": primer_id},
                        }
                    ],
                    "raw": {
                        "role": "assistant",
                        "tool_calls": [
                            {
                                "id": "call_leer_1",
                                "type": "function",
                                "function": {
                                    "name": "leer_apunte",
                                    "arguments": "{}",
                                },
                            }
                        ],
                    },
                }
            idx["i"] += 1
            return secuencia[i]

        monkeypatch.setattr(
            llm, "responder_con_tools", fake_responder_con_tools
        )

        # Wrap ejecutar_tool para registrar los args con los que
        # se llamó cada tool, sin alterar su comportamiento.
        from app.matix import tools as tools_module

        ejecutar_original = tools_module.ejecutar_tool

        async def ejecutar_espia(db, nombre, args):
            args_por_tool.setdefault(nombre, []).append(args)
            return await ejecutar_original(db, nombre, args)

        monkeypatch.setattr(chat_module, "ejecutar_tool", ejecutar_espia)

        # 5) Disparar el orquestador.
        resultado = await chat_module.conversar(
            _fresh_db,
            historial=[],
            mensaje="resumime mi apunte sobre arquitectura hexagonal",
        )

        # Verificaciones:
        # - El modelo usó buscar_apuntes y leer_apunte (en ese orden).
        assert resultado["tools_usadas"] == ["buscar_apuntes", "leer_apunte"]

        # - `leer_apunte` recibió EXACTAMENTE el id del apunte sembrado
        #   (no inventó, no agarró otro de la BD).
        assert "leer_apunte" in args_por_tool
        ids_leidos = [a["apunte_id"] for a in args_por_tool["leer_apunte"]]
        assert aid_esperado in ids_leidos, (
            f"esperaba que se leyera {aid_esperado}, "
            f"se leyeron: {ids_leidos}"
        )

        # - La respuesta final menciona el apunte (es una verificación
        #   semántica suave; lo importante ya quedó arriba).
        assert "_test_tutor_arq_hex" in resultado["respuesta"] or "arq_hex" in resultado["respuesta"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid_esperado}/permanente")
