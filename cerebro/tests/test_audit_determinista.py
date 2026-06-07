"""Auditoría: los flujos que DEBEN ser deterministas no llaman al modelo.

Test estático: el código fuente de los módulos deterministas no contiene
llamadas de generación al LLM (`llm.responder`, `responder_con_tools`,
`_chat_json`, `clasificar_*`). Atrapa regresiones — si alguien mete una
llamada al modelo en, p. ej., el rollover, el gate se pone rojo.

Embeddings (`embebir`) NO cuentan como "llamada de juicio": son vectores
deterministas para RAG, no generación de texto. Por eso no se prohíben aquí.
"""
from __future__ import annotations

import pathlib

# Módulos cuyos FLUJOS deben ser 100% deterministas (cero juicio del modelo).
_MODULOS_DETERMINISTAS = [
    "app/matix/rollover.py",
    "app/matix/horario.py",
    "app/matix/rendicion_cuentas.py",
    "app/matix/evolucion_proyecto.py",
    "app/briefing/armar.py",
    "app/briefing/cierre.py",
    "app/matix/seleccion_tools.py",
]

# Patrones que delatan una llamada de GENERACIÓN al modelo.
_PROHIBIDOS = (
    "llm.responder",
    "responder_con_tools",
    "_chat_json",
    "clasificar_captura_json",
    "extraer_tareas_json",
    "desglosar_tarea_json",
)

_RAIZ = pathlib.Path(__file__).resolve().parents[1]


def test_flujos_deterministas_no_llaman_al_modelo():
    fallos = []
    for rel in _MODULOS_DETERMINISTAS:
        ruta = _RAIZ / rel
        assert ruta.exists(), f"no existe {rel}"
        fuente = ruta.read_text(encoding="utf-8")
        for pat in _PROHIBIDOS:
            if pat in fuente:
                fallos.append(f"{rel} contiene «{pat}»")
    assert not fallos, "Flujos deterministas con llamada al LLM: " + "; ".join(fallos)


def test_chat_si_usa_el_modelo():
    """Sanity inverso: el chat (juicio) SÍ debe usar el modelo — si esto deja
    de ser cierto, algo se rompió en el chat, no en el audit."""
    fuente = (_RAIZ / "app/matix/chat.py").read_text(encoding="utf-8")
    assert "responder_con_tools" in fuente
