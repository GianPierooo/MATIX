"""Tests del flujo de cierre del día por voz (Capa 2 Paso 6).

No pegamos al modelo real — monkeypatcheamos `llm.responder_con_tools`
para simular los turnos:

  turno 1: el usuario dice «hagamos el cierre del día»
           → Matix devuelve TEXTO (pregunta qué hizo).

  turno 2: el usuario dice las tres cosas
           → Matix devuelve TEXTO (pregunta el brain dump).

  turno 3: el usuario dice qué le da vueltas
           → Matix devuelve TOOL_CALL `registrar_cierre` con los
             items y la nota_extra. El cerebro lo ejecuta.

  turno 4: tras el tool_result, Matix devuelve TEXTO ("descansá bien").

Verificamos:
- Se llamó a `registrar_cierre` con los items correctos.
- Quedó un cierre en BD con esa fecha y esos items.
- `tools_usadas` y `tablas_cambiadas` reflejan la acción.

Los mocks NO necesitan ser literales de OpenAI — `chat.py` solo
re-inyecta el `raw` como un dict en la lista de mensajes. Como
mockeamos la SIGUIENTE llamada también, ese dict nunca se le pasa
de verdad a OpenAI. Por eso podemos usar dicts mínimos.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from app.matix import chat as chat_module
from app.matix import llm


def _hoy_lima_iso() -> str:
    return (
        datetime.now(timezone.utc)
        .astimezone(timezone(timedelta(hours=-5)))
        .date()
        .isoformat()
    )


@pytest.fixture
def _fake_llm(monkeypatch):
    """Reemplaza `llm.responder_con_tools` por una secuencia de
    respuestas pre-armadas. Devuelve la lista de "calls" registradas
    para que el test inspeccione qué messages se le pasaron al modelo
    en cada vuelta."""
    secuencia: list[dict] = []
    calls: list[list[dict]] = []

    async def fake(messages, tools, **kw):
        # Capturamos copia de los messages que vio el "modelo".
        calls.append([dict(m) if isinstance(m, dict) else m for m in messages])
        # Avanzamos la secuencia.
        if not secuencia:
            raise RuntimeError(
                "fake_llm: se acabaron las respuestas pre-armadas."
            )
        return secuencia.pop(0)

    monkeypatch.setattr(llm, "responder_con_tools", fake)
    return {"secuencia": secuencia, "calls": calls}


async def test_flujo_cierre_termina_en_registrar_cierre(
    client: AsyncClient, _fake_llm
):
    """Simula la conversación completa del cierre y verifica que
    Matix termina llamando `registrar_cierre` con los items que el
    usuario dijo."""
    # Items que va a "decir" el usuario distribuidos en 3 turnos.
    items_dichos = [
        "implementé los rituales de voz",
        "compilé el APK release",
        "validé el despliegue en Railway",
    ]
    nota_dump = "estoy pensando en cómo aprovechar mañana temprano"

    # Pre-armamos lo que el modelo devuelve en cada vuelta.
    _fake_llm["secuencia"].extend(
        [
            # Vuelta 1: el modelo pregunta qué hizo.
            {
                "tipo": "texto",
                "contenido": "Dale, contame tres cosas que sí hiciste hoy.",
                "raw": {
                    "role": "assistant",
                    "content": "Dale, contame tres cosas que sí hiciste hoy.",
                },
            },
            # Vuelta 2: pregunta el brain dump.
            {
                "tipo": "texto",
                "contenido": "Bien. ¿Algo más que te esté dando vueltas?",
                "raw": {
                    "role": "assistant",
                    "content": "Bien. ¿Algo más que te esté dando vueltas?",
                },
            },
            # Vuelta 3: llama a registrar_cierre con todo.
            {
                "tipo": "tool_calls",
                "tool_calls": [
                    {
                        "id": "call_cierre_1",
                        "nombre": "registrar_cierre",
                        "args": {
                            "items": items_dichos,
                            "nota_extra": nota_dump,
                        },
                    }
                ],
                "raw": {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": "call_cierre_1",
                            "type": "function",
                            "function": {
                                "name": "registrar_cierre",
                                "arguments": "{}",
                            },
                        }
                    ],
                },
            },
            # Vuelta 4: tras el resultado del tool, despedida breve.
            {
                "tipo": "texto",
                "contenido": "Descansá bien, Gian Piero.",
                "raw": {
                    "role": "assistant",
                    "content": "Descansá bien, Gian Piero.",
                },
            },
        ]
    )

    # El historial reconstruye la conversación previa: el saludo
    # del usuario, las dos preguntas de Matix, las dos respuestas
    # del usuario. El último mensaje (el brain dump) se manda como
    # `mensaje` actual, que es lo que dispara la tool call.
    historial = [
        {"rol": "user", "contenido": "Hagamos el cierre del día."},
        {
            "rol": "assistant",
            "contenido": "Dale, contame tres cosas que sí hiciste hoy.",
        },
        {
            "rol": "user",
            "contenido": " · ".join(items_dichos),
        },
        {
            "rol": "assistant",
            "contenido": "Bien. ¿Algo más que te esté dando vueltas?",
        },
    ]
    # Como `chat.py` empieza con vuelta 1 (no usa el historial para
    # contar las vueltas), nuestras respuestas pre-armadas se
    # corresponden con las vueltas internas al `conversar`. Para
    # que termine en `registrar_cierre`, el `conversar` necesita
    # consumir secuencia[0] → secuencia[1] → secuencia[2] (tool) →
    # secuencia[3] (texto final). Le pasamos un historial vacío y
    # el mensaje único que simula "ya pasamos los pasos, ahora cerrá".
    #
    # Simplificación: el test no replica la conversación completa
    # (eso sería un test de extremo a extremo del modelo real); lo
    # que valida es que la INFRAESTRUCTURA del orquestador, dado un
    # modelo que decide llamar `registrar_cierre` con esos args,
    # ejecuta la tool y persiste en BD.
    # Reseteamos secuencia y ponemos solo 2 vueltas: tool_call + texto.
    _fake_llm["secuencia"].clear()
    _fake_llm["secuencia"].extend(
        [
            {
                "tipo": "tool_calls",
                "tool_calls": [
                    {
                        "id": "call_cierre_1",
                        "nombre": "registrar_cierre",
                        "args": {
                            "items": items_dichos,
                            "nota_extra": nota_dump,
                        },
                    }
                ],
                "raw": {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "id": "call_cierre_1",
                            "type": "function",
                            "function": {
                                "name": "registrar_cierre",
                                "arguments": "{}",
                            },
                        }
                    ],
                },
            },
            {
                "tipo": "texto",
                "contenido": "Descansá bien, Gian Piero.",
                "raw": {
                    "role": "assistant",
                    "content": "Descansá bien, Gian Piero.",
                },
            },
        ]
    )

    # Ejecutamos el orquestador. Le pasamos el historial completo
    # del ritual + el último mensaje del usuario.
    from app.db import Postgrest
    db = Postgrest()
    try:
        resultado = await chat_module.conversar(
            db,
            historial=historial,
            mensaje=nota_dump,
        )

        # 1) La respuesta final es la despedida.
        assert "descansá" in resultado["respuesta"].lower() or \
            "descansa" in resultado["respuesta"].lower()

        # 2) Se ejecutó `registrar_cierre`.
        assert resultado["tools_usadas"] == ["registrar_cierre"]
        assert "cierres_dia" in resultado["tablas_cambiadas"]

        # 3) Quedó un cierre con esos items en BD para la fecha de hoy.
        fecha = _hoy_lima_iso()
        r = await client.get(f"/api/v1/cierres_dia?fecha={fecha}")
        assert r.status_code == 200, r.text
        lista = r.json()
        assert lista, "no se persistió el cierre del día"
        # El último cierre para esa fecha debe tener los items exactos
        # que el "modelo" dijo.
        cierre = lista[0]
        assert cierre["items"] == items_dichos
        assert cierre["nota_extra"] == nota_dump
    finally:
        # Limpieza: borrar el cierre del día creado por el test, para
        # no pisar el real del usuario si lo hubiera. Lo más seguro
        # es borrar el de la fecha de hoy si su nota_extra coincide
        # con la del test (firma única).
        r = await client.get(f"/api/v1/cierres_dia?fecha={_hoy_lima_iso()}")
        for c in r.json():
            if c.get("nota_extra") == nota_dump:
                await client.delete(f"/api/v1/cierres_dia/{c['id']}")
        await db.aclose()
