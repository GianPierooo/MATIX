"""Asistencia a eventos fuera de casa: detección, contenido, tasa y el feed al
motor de evolución. Lógica PURA sin BD ni FCM; una prueba de integración con
FakeDB verifica el silencio nocturno y el dedup."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.matix import asistencia_eventos as a

LIMA = a.LIMA


def _ev(**kwargs):
    base = {
        "id": "e1",
        "titulo": "Cálculo",
        "ubicacion": "La uni",
        "inicia_en": None,
        "termina_en": None,
        "todo_el_dia": False,
        "eliminado_en": None,
        "asistencia": None,
        "asistencia_preguntada_en": None,
    }
    base.update(kwargs)
    return base


# ── PURO ─────────────────────────────────────────────────────────────────────

def test_fuera_de_casa_requiere_ubicacion():
    assert a.evento_fuera_de_casa(_ev(ubicacion="Gym")) is True
    assert a.evento_fuera_de_casa(_ev(ubicacion="")) is False
    assert a.evento_fuera_de_casa(_ev(ubicacion=None)) is False


def test_debe_preguntar_tras_terminar_en_ventana():
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)  # 12:00 Lima
    # Terminó hace 10 min → dentro de la ventana post (2h).
    ev = _ev(termina_en=(ahora - timedelta(minutes=10)).isoformat())
    assert a.debe_preguntar(ev, ahora=ahora) is True


def test_no_pregunta_si_aun_no_termina_o_muy_viejo():
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)
    futuro = _ev(termina_en=(ahora + timedelta(minutes=30)).isoformat())
    assert a.debe_preguntar(futuro, ahora=ahora) is False
    viejo = _ev(termina_en=(ahora - timedelta(hours=5)).isoformat())
    assert a.debe_preguntar(viejo, ahora=ahora) is False


def test_no_pregunta_si_en_casa_o_borrado_o_todo_el_dia():
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)
    fin = (ahora - timedelta(minutes=10)).isoformat()
    assert a.debe_preguntar(_ev(ubicacion="", termina_en=fin), ahora=ahora) is False
    assert a.debe_preguntar(
        _ev(termina_en=fin, eliminado_en="2026-06-08T00:00:00Z"), ahora=ahora) is False
    assert a.debe_preguntar(_ev(termina_en=fin, todo_el_dia=True), ahora=ahora) is False


def test_dedup_no_repregunta_dentro_de_la_ventana():
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)
    fin = (ahora - timedelta(minutes=10)).isoformat()
    # Ya preguntado hace 1h → no re-preguntar (cooldown 6h).
    ev = _ev(termina_en=fin,
             asistencia_preguntada_en=(ahora - timedelta(hours=1)).isoformat())
    assert a.debe_preguntar(ev, ahora=ahora) is False
    # Preguntado hace 7h → sí (pasó el cooldown; útil para recurrentes diarios).
    ev2 = _ev(termina_en=fin,
              asistencia_preguntada_en=(ahora - timedelta(hours=7)).isoformat())
    assert a.debe_preguntar(ev2, ahora=ahora) is True


def test_fin_ocurrencia_recurrente_usa_la_hora_de_hoy():
    # Evento semanal que cae HOY: la hora de fin se aplica a la fecha de hoy.
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)  # lunes 12:00 Lima
    hoy_local = ahora.astimezone(LIMA).date()
    ev = _ev(
        inicia_en="2026-06-01T15:00:00+00:00",   # 10:00 Lima
        termina_en="2026-06-01T16:45:00+00:00",  # 11:45 Lima
        recurrencia_freq="semanal",
        recurrencia_dias_semana=[hoy_local.isoweekday()],
        recurrencia_fin_tipo="nunca",
    )
    fin = a.fin_ocurrencia(ev, ahora=ahora)
    assert fin is not None
    fin_local = fin.astimezone(LIMA)
    assert (fin_local.date(), fin_local.hour, fin_local.minute) == (hoy_local, 11, 45)


def test_contenido_pregunta_directa_sin_reproche():
    c = a.armar_contenido_asistencia(_ev(titulo="Gym"))
    assert c["titulo"] == "¿Fuiste a Gym?"
    assert c["acciones"] == ["si_fui", "no_fui", "reprogramar"]
    # Activa, no avergüenza: nada de "otra vez", "no hiciste".
    txt = (c["titulo"] + " " + c["cuerpo"]).lower()
    assert "otra vez" not in txt and "no hiciste" not in txt


def test_tasa_asistencia_y_combinar():
    assert a.tasa_asistencia(3, 4) == 0.75
    assert a.tasa_asistencia(0, 0) is None
    # combinar: la PEOR señal manda (conservador, no infla el set).
    assert a.combinar_tasas(0.9, 0.4) == 0.4
    assert a.combinar_tasas(0.5, None) == 0.5
    assert a.combinar_tasas(None, None) is None


# ── Integración (FakeDB) ─────────────────────────────────────────────────────

class FakeDB:
    def __init__(self, tablas):
        self.tablas = tablas
        self.updates = []

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        return list(self.tablas.get(tabla, []))

    async def update(self, tabla, id_, payload):
        self.updates.append((tabla, id_, payload))
        return {"id": id_, **payload}

    async def delete(self, tabla, id_):
        pass


def test_revisar_asistencia_respeta_silencio_nocturno(monkeypatch):
    import asyncio
    # 02:00 Lima = 07:00 UTC → dentro del silencio (22–08): no manda nada,
    # ni siquiera el modo máximo.
    ahora = datetime(2026, 6, 8, 7, 0, tzinfo=timezone.utc)
    fin = (ahora - timedelta(minutes=10)).isoformat()
    db = FakeDB({
        "config_nudges": [{"silencio_inicio": 22, "silencio_fin": 8,
                           "intensidad": "maximo"}],
        "eventos": [_ev(termina_en=fin)],
        "device_tokens": [{"id": "t", "token": "tok"}],
    })
    enviados = []
    monkeypatch.setattr(a, "enviar_push",
                        lambda *aa, **kw: enviados.append(kw) or "mid")
    r = asyncio.run(a.revisar_asistencia(db, ahora=ahora))
    assert r.get("silencio") is True
    assert enviados == []


def test_revisar_asistencia_envia_y_marca_preguntada(monkeypatch):
    import asyncio
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)  # 12:00 Lima, en ventana
    fin = (ahora - timedelta(minutes=10)).isoformat()
    db = FakeDB({
        "config_nudges": [{"silencio_inicio": 22, "silencio_fin": 8,
                           "intensidad": "intenso"}],
        "eventos": [_ev(termina_en=fin)],
        "device_tokens": [{"id": "t", "token": "tok"}],
    })
    enviados = []
    monkeypatch.setattr(a, "enviar_push",
                        lambda *aa, **kw: enviados.append(kw) or "mid")
    r = asyncio.run(a.revisar_asistencia(db, ahora=ahora))
    assert r["asistencia"] == 1
    assert enviados and enviados[0]["data"]["tipo"] == "asistencia_evento"
    assert enviados[0]["data"]["intensidad"] == "intenso"
    # Marcó preguntada_en para dedupear el próximo tick.
    assert any(t == "eventos" and "asistencia_preguntada_en" in p
               for t, _, p in db.updates)
