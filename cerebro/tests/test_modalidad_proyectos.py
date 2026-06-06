"""Modalidad de trabajo de proyectos (migración 0039).

- Helper puro `es_continuo_intercalado(modalidad)`: NULL / vacío / valor explícito.
- Schema Pydantic: los nuevos campos (`horas_semana_estimadas`, `modalidad`,
  `nota_interna`) son opcionales y validan rangos.
- Contrato del planificador: un proyecto con modalidad `continuo_intercalado`
  (o sin modalidad) sigue siendo eligible para huecos profundos; uno con otra
  modalidad NO se mete como bloque rígido por defecto."""
from __future__ import annotations

from app.matix import horario as h
from app.schemas.proyectos import ProyectoCreate, ProyectoUpdate


# ── es_continuo_intercalado: helper puro ────────────────────────────────────


def test_modalidad_NULL_es_continuo_intercalado():
    # Default histórico: si la columna viene vacía, comportamiento actual.
    assert h.es_continuo_intercalado(None) is True
    assert h.es_continuo_intercalado("") is True
    assert h.es_continuo_intercalado("   ") is True


def test_modalidad_explicita_continuo_intercalado():
    assert h.es_continuo_intercalado("continuo_intercalado") is True
    # Tolerante a mayúsculas (vendrá del usuario y de Matix por chat).
    assert h.es_continuo_intercalado("Continuo_Intercalado") is True


def test_otras_modalidades_no_continuo_intercalado():
    """`slot_fijo` y `esporadico` NO son continuo intercalado: el planificador
    NO debe meter sus tareas como trabajo profundo automáticamente."""
    assert h.es_continuo_intercalado("slot_fijo") is False
    assert h.es_continuo_intercalado("esporadico") is False
    assert h.es_continuo_intercalado("cualquier_otra_cosa") is False


# ── Schema Pydantic: campos nuevos opcionales ───────────────────────────────


def test_proyecto_create_acepta_campos_nuevos():
    p = ProyectoCreate(
        nombre="Matix 1.0",
        horas_semana_estimadas=15,
        modalidad="continuo_intercalado",
        nota_interna="Estimación supuesta — confirmar en chat.",
    )
    assert p.horas_semana_estimadas == 15
    assert p.modalidad == "continuo_intercalado"
    assert "confirmar" in (p.nota_interna or "")


def test_proyecto_create_campos_nuevos_son_opcionales():
    """Proyectos viejos / nuevos sin estos campos NO rompen."""
    p = ProyectoCreate(nombre="X")
    assert p.horas_semana_estimadas is None
    assert p.modalidad is None
    assert p.nota_interna is None


def test_horas_semana_valida_rango():
    """0..168 (horas en una semana). Más es disparate."""
    import pytest
    from pydantic import ValidationError

    # Válido: 15h/semana.
    ProyectoCreate(nombre="X", horas_semana_estimadas=15)
    # Inválido: 200h/semana.
    with pytest.raises(ValidationError):
        ProyectoCreate(nombre="X", horas_semana_estimadas=200)
    with pytest.raises(ValidationError):
        ProyectoCreate(nombre="X", horas_semana_estimadas=-1)


def test_proyecto_update_tambien_acepta_campos():
    """PATCH /proyectos/{id} debe poder actualizar los nuevos campos."""
    u = ProyectoUpdate(modalidad="continuo_intercalado", horas_semana_estimadas=10)
    assert u.modalidad == "continuo_intercalado"
    assert u.horas_semana_estimadas == 10
