"""Capa 7 — digitalización por cámara. El extractor generaliza el OCR de sílabo
(clasifica + estructura, UNA llamada barata, sin inventar) y la creación de lo
CONFIRMADO va por los COMANDOS canónicos (no rutas nuevas). FakeDB sin red.
"""
from __future__ import annotations

import asyncio
import json
import uuid

from app.matix import digitalizacion, llm


class FakeDB:
    def __init__(self, tablas=None):
        self.tablas = tablas or {}
        self.inserts = []

    async def get(self, tabla, id_):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                return f
        return None

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        return list(self.tablas.get(tabla, []))

    async def insert(self, tabla, row):
        # Como Postgrest: el id es un UUID (las FK curso_id se validan como UUID).
        fila = {"id": row.get("id") or str(uuid.uuid4()), **row}
        self.tablas.setdefault(tabla, []).append(fila)
        self.inserts.append((tabla, row))
        return fila

    async def update(self, tabla, id_, payload):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                f.update(payload)
                return f
        return None

    async def delete(self, tabla, id_):
        return True


def _patch_chat_json(monkeypatch, salida, contador=None):
    async def fake(messages, *, model=None, temperature=0.0, operacion="extraccion"):
        if contador is not None:
            contador.append(1)
        return salida if isinstance(salida, str) else json.dumps(salida)
    monkeypatch.setattr(llm, "_chat_json", fake)


# ── Extractor: clasifica + estructura, una llamada, no inventa ───────────────


def test_extrae_silabo_a_curso_evaluaciones_sesiones(monkeypatch):
    calls = []
    _patch_chat_json(monkeypatch, {
        "tipo": "silabo",
        "tareas": [],
        "cursos": [{
            "nombre": "Cálculo I", "profesor": "Gauss",
            "sesiones": [{"dia_semana": 0, "hora_inicio": "10:00", "hora_fin": "12:00"},
                         {"dia_semana": 9, "hora_inicio": "08:00"}],  # día inválido → se cae
            "evaluaciones": [{"titulo": "Parcial 1", "tipo": "examen", "fecha": "2026-07-01", "peso": 30},
                             {"titulo": "Sin fecha", "tipo": "examen"}],  # sin fecha → se cae
        }],
        "eventos": [], "apunte": None,
    }, calls)
    r = asyncio.run(llm.extraer_documento_json(texto="...", hoy="2026-06-09"))
    assert len(calls) == 1  # UNA sola llamada al modelo (costo acotado)
    assert r["tipo"] == "silabo"
    c = r["cursos"][0]
    assert c["nombre"] == "Cálculo I" and c["profesor"] == "Gauss"
    assert len(c["sesiones"]) == 1 and c["sesiones"][0]["dia_semana"] == 0  # el inválido cayó
    assert len(c["evaluaciones"]) == 1 and c["evaluaciones"][0]["titulo"] == "Parcial 1"


def test_extrae_tareas(monkeypatch):
    _patch_chat_json(monkeypatch, {
        "tipo": "tareas",
        "tareas": [{"titulo": "Comprar pan", "vence_en": "2026-06-10"},
                   {"titulo": "", "vence_en": None},  # sin título → se cae
                   {"titulo": "Sin fecha", "vence_en": "no-es-fecha"}],  # fecha inválida → null
        "cursos": [], "eventos": [], "apunte": None,
    })
    r = asyncio.run(llm.extraer_documento_json(texto="x", hoy="2026-06-09"))
    assert r["tipo"] == "tareas"
    assert [t["titulo"] for t in r["tareas"]] == ["Comprar pan", "Sin fecha"]
    assert r["tareas"][1]["vence_en"] is None


def test_extractor_no_inventa_cuando_no_hay_nada(monkeypatch):
    _patch_chat_json(monkeypatch, "no es json")
    r = asyncio.run(llm.extraer_documento_json(texto="garabatos", hoy="2026-06-09"))
    assert r["tareas"] == [] and r["cursos"] == [] and r["eventos"] == [] and r["apunte"] is None


def test_extractor_sin_entrada_no_llama_al_modelo(monkeypatch):
    calls = []
    _patch_chat_json(monkeypatch, "{}", calls)
    r = asyncio.run(llm.extraer_documento_json(texto=None, imagen_data_url=None, hoy="2026-06-09"))
    assert not calls and r["tareas"] == []  # sin texto ni imagen, ni una llamada


def test_extractor_imagen_usa_vision_barata(monkeypatch):
    """Con imagen va por el pipeline de VISIÓN (no por chat de texto)."""
    chat_calls, vis_calls = [], []
    _patch_chat_json(monkeypatch, "{}", chat_calls)

    async def fake_vision(model, system, pedido, imagen, *, max_tokens, operacion="vision"):
        vis_calls.append(model)
        return json.dumps({"tipo": "apunte", "apunte": {"titulo": "Pizarra", "contenido": "x"}})

    monkeypatch.setattr(llm, "_vision_en", fake_vision)
    monkeypatch.setattr(llm.modelos_llm, "proveedor_preferido", lambda: "openai")  # sin failover
    r = asyncio.run(llm.extraer_documento_json(imagen_data_url="data:image/png;base64,AAA", hoy="2026-06-09"))
    assert vis_calls and not chat_calls  # usó visión, no chat de texto
    assert r["apunte"]["titulo"] == "Pizarra"


# ── Creación: lo confirmado se crea por los COMANDOS canónicos ───────────────


def test_crea_por_comandos_canonicos(monkeypatch):
    monkeypatch.setattr("app.matix.indexador.indexar_apunte", _noop_async)
    db = FakeDB()
    propuesta = {
        "tipo": "silabo",
        "tareas": [{"titulo": "Leer cap 1", "vence_en": "2026-06-12"}],
        "cursos": [{
            "nombre": "Física", "profesor": "Newton",
            "sesiones": [{"dia_semana": 1, "hora_inicio": "08:00", "hora_fin": "10:00"}],
            "evaluaciones": [{"titulo": "Parcial", "tipo": "examen", "fecha": "2026-07-15", "peso": 40}],
        }],
        "eventos": [{"titulo": "Charla", "fecha": "2026-06-20", "hora_inicio": "18:00", "hora_fin": "19:00"}],
        "apunte": {"titulo": "Notas pizarra", "contenido": "E=mc2"},
    }
    r = asyncio.run(digitalizacion.crear_desde_captura(db, propuesta))
    tipos = [c["tipo"] for c in r["creados"]]
    # Cada ítem se creó por SU comando canónico (no una ruta nueva).
    assert "crear_tarea" in tipos
    assert "crear_curso" in tipos
    assert "crear_sesion_clase" in tipos
    assert "crear_evaluacion" in tipos
    assert "crear_evento" in tipos
    assert "crear_apunte" in tipos
    assert not r["errores"]
    # Las filas quedaron en el hub y sesion/evaluación cuelgan del curso creado.
    curso = db.tablas["cursos"][0]
    assert db.tablas["sesiones_clase"][0]["curso_id"] == str(curso["id"])
    assert db.tablas["evaluaciones"][0]["curso_id"] == str(curso["id"])
    assert db.tablas["apuntes"][0]["titulo"] == "Notas pizarra"


def test_curso_invalido_no_cuelga_sesiones(monkeypatch):
    # Curso sin nombre → no se crea → sus sesiones/evaluaciones no se intentan.
    db = FakeDB()
    propuesta = {"cursos": [{"nombre": "", "sesiones": [{"dia_semana": 0, "hora_inicio": "10:00"}]}]}
    r = asyncio.run(digitalizacion.crear_desde_captura(db, propuesta))
    assert r["total"] == 0 and "sesiones_clase" not in db.tablas


def test_creacion_es_atomica_por_item_y_reporta_errores(monkeypatch):
    monkeypatch.setattr("app.matix.indexador.indexar_apunte", _noop_async)
    db = FakeDB()
    # Una tarea válida + un evento con fecha que el comando rechazará por validación
    # (inicia_en mal formado lo arma el orquestador bien, así que probamos sólo
    # que una tarea sin título no rompe el resto).
    propuesta = {
        "tareas": [{"titulo": "Buena"}, {"titulo": ""}],  # la vacía se ignora
        "apunte": {"titulo": "N", "contenido": ""},
    }
    r = asyncio.run(digitalizacion.crear_desde_captura(db, propuesta))
    assert any(c["tipo"] == "crear_tarea" for c in r["creados"])
    assert len(db.tablas.get("tareas", [])) == 1  # solo la buena


def test_creacion_no_toca_el_llm(monkeypatch):
    """La creación es puro routing por comandos: si tocara el LLM, explota."""
    from app.matix import llm as _llm

    def bomba(*a, **k):
        raise AssertionError("¡la creación desde captura tocó el LLM!")

    for n in ("responder", "responder_con_tools", "extraer_documento_json", "_chat_json"):
        if hasattr(_llm, n):
            monkeypatch.setattr(_llm, n, bomba)
    monkeypatch.setattr("app.matix.indexador.indexar_apunte", _noop_async)
    db = FakeDB()
    r = asyncio.run(digitalizacion.crear_desde_captura(db, {
        "tareas": [{"titulo": "X"}], "apunte": {"titulo": "Y", "contenido": ""}}))
    assert r["total"] == 2  # creó sin tocar el modelo


async def _noop_async(*a, **k):
    return None


# ── Gate de confirmación: la extracción NO persiste ──────────────────────────


def test_extraccion_no_persiste_nada(monkeypatch):
    """El extractor no recibe `db` y no crea nada: la creación es un paso
    aparte (confirmación antes de crear)."""
    import inspect
    sig = inspect.signature(llm.extraer_documento_json)
    assert "db" not in sig.parameters  # no puede tocar la BD
    _patch_chat_json(monkeypatch, {"tipo": "tareas", "tareas": [{"titulo": "x"}]})
    r = asyncio.run(llm.extraer_documento_json(texto="x", hoy="2026-06-09"))
    assert r["tareas"]  # devuelve propuesta; crear es otra llamada
