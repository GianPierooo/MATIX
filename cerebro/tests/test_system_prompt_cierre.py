"""El cierre con gancho está, y NO reintroduce confirmaciones procedurales."""
from __future__ import annotations

from app.matix.system_prompt import system_prompt_fijo


def test_prompt_tiene_cierre_forward():
    p = system_prompt_fijo()
    assert "CIERRE CON GANCHO" in p
    # Propone un siguiente paso (forward), no permiso para lo hecho.
    bajo = p.lower()
    assert "siguiente paso" in bajo
    assert "hacia adelante" in bajo


def test_cierre_no_reintroduce_preguntas_procedurales():
    p = system_prompt_fijo()
    # El gancho aclara EXPLÍCITAMENTE que no es una pregunta-tonta procedural
    # ni un «¿hago esto?»; en los comandos se actúa de frente.
    assert "no es una pregunta-tonta procedural" in p.lower() \
        or "NO es una pregunta-tonta procedural" in p
    assert "¿hago esto?" in p
    # El sesgo a la acción sigue presente (no se contradicen).
    assert "SESGO A LA ACCIÓN" in p


def test_prompt_menciona_modo_finanzas_y_autoactivacion():
    p = system_prompt_fijo()
    # finanzas está entre los modos y se auto-activa al hablar de plata.
    assert "finanzas" in p.lower()
    assert "plata" in p.lower()
