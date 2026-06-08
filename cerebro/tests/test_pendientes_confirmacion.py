"""Pendientes de confirmación in-app: las MISMAS tareas/eventos pasados sin
resolver que considera el motor de notis, expuestos por endpoint para que la UI
no dependa solo del push (MagicOS y similares pueden no entregar).

Test directo de la función (sin TestClient con auth real): inyecta una FakeDB y
verifica el filtrado. La conformidad del wrapper FastAPI está cubierta por la
integración real en conftest (cuando hay .env.test)."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

from app.routers.push import pendientes_confirmacion


class FakeDB:
    def __init__(self, tablas):
        self.tablas = tablas

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        return list(self.tablas.get(tabla, []))


def test_tareas_pendientes_no_completadas_y_vencidas():
    ahora = datetime.now(timezone.utc)
    venc = (ahora - timedelta(hours=2)).isoformat()
    futuro = (ahora + timedelta(hours=2)).isoformat()
    db = FakeDB({
        "tareas": [
            # SÍ: no completada, plazo pasado.
            {"id": "t1", "titulo": "Estudiar cálculo", "completada": False,
             "vence_en": venc, "eliminado_en": None},
            # NO: futura.
            {"id": "t2", "titulo": "Futura", "completada": False,
             "vence_en": futuro, "eliminado_en": None},
            # NO: completada.
            {"id": "t3", "titulo": "Hecha", "completada": True,
             "vence_en": venc, "eliminado_en": None},
        ],
        "eventos": [],
    })
    out = asyncio.run(pendientes_confirmacion(db))
    ids = [t["id"] for t in out["tareas"]]
    assert ids == ["t1"]
    assert out["tareas"][0]["vencio_hace_min"] >= 110


def test_eventos_pendientes_fuera_de_casa_terminados_sin_asistencia():
    ahora = datetime.now(timezone.utc)
    termino_hoy = (ahora - timedelta(minutes=30)).isoformat()
    futuro = (ahora + timedelta(hours=1)).isoformat()
    db = FakeDB({
        "tareas": [],
        "eventos": [
            # SÍ: fuera de casa, terminó hoy, sin asistencia.
            {"id": "e1", "titulo": "Clase de cálculo", "ubicacion": "La uni",
             "inicia_en": termino_hoy, "termina_en": termino_hoy,
             "todo_el_dia": False, "asistencia": None, "eliminado_en": None},
            # NO: ya confirmada.
            {"id": "e2", "titulo": "Gym", "ubicacion": "Smart Fit",
             "inicia_en": termino_hoy, "termina_en": termino_hoy,
             "asistencia": "asistio", "eliminado_en": None},
            # NO: sin ubicación (en casa).
            {"id": "e3", "titulo": "Zoom", "ubicacion": "",
             "inicia_en": termino_hoy, "termina_en": termino_hoy,
             "asistencia": None, "eliminado_en": None},
            # NO: futuro (todavía no termina).
            {"id": "e4", "titulo": "Próximo", "ubicacion": "X",
             "inicia_en": futuro, "termina_en": futuro,
             "asistencia": None, "eliminado_en": None},
        ],
    })
    out = asyncio.run(pendientes_confirmacion(db))
    ids = [e["id"] for e in out["eventos"]]
    assert ids == ["e1"]
    assert out["eventos"][0]["titulo"] == "Clase de cálculo"
    assert out["eventos"][0]["ubicacion"] == "La uni"


def test_eventos_viejos_no_persiguen_al_usuario():
    """Lo de hace 3+ días no entra (no agobies): el cierre del día es para hoy
    (con margen de ayer)."""
    ahora = datetime.now(timezone.utc)
    viejo = (ahora - timedelta(days=5)).isoformat()
    db = FakeDB({
        "tareas": [],
        "eventos": [
            {"id": "viejo", "titulo": "Algo viejo", "ubicacion": "X",
             "inicia_en": viejo, "termina_en": viejo,
             "asistencia": None, "eliminado_en": None},
        ],
    })
    out = asyncio.run(pendientes_confirmacion(db))
    assert out["eventos"] == []
