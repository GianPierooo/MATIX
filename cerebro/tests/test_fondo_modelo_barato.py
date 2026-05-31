"""El texto de FONDO usa siempre el modelo barato, nunca el auto ni el fuerte.

El repaso semanal lo dispara el scheduler (el usuario no está escribiendo),
así que debe generarse con el modelo barato del par para no disparar el
costo. Verificamos que `_sintetizar` le pasa ESE modelo al LLM.
"""
from __future__ import annotations

from app.briefing import repaso_semanal


async def test_repaso_usa_el_modelo_que_se_le_pasa(monkeypatch):
    visto: dict = {}

    async def fake_json(datos, *, model=None):
        visto["model"] = model
        return {"resumen": "todo bien", "focos": ["foco a"]}

    monkeypatch.setattr(repaso_semanal.llm, "repaso_semanal_json", fake_json)

    datos = {"tareas_completadas": 2, "eventos_que_hubo": 1}
    resumen, focos = await repaso_semanal._sintetizar(datos, 0, "gpt-4o-mini")

    assert visto["model"] == "gpt-4o-mini"  # el barato, no el fuerte ni auto
    assert resumen == "todo bien" and focos == ["foco a"]


async def test_modelo_fondo_es_el_barato_del_par(monkeypatch):
    from app.matix import modelos_llm

    async def fake_par(db):
        return ("gpt-4o-mini", "claude-sonnet-4-6")

    monkeypatch.setattr(modelos_llm, "par_barato_fuerte", fake_par)
    assert await modelos_llm.modelo_fondo(None) == "gpt-4o-mini"
