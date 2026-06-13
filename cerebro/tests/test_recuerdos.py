"""Memoria UNIFICADA `recuerdos` (Capa 3 · RAG transversal).

Todo PURO / con fakes: sin BD ni OpenAI reales. Cubre los composers de texto,
el formateo del bloque inyectado, el incremental por hash (salta re-embeber),
el umbral de recuperación, y el ruteo del hook de comandos (UI + IA convergen).
"""
from __future__ import annotations

import pytest

from app.matix import recuerdos as r


# ── Composers de texto (qué se embebe) ───────────────────────────────────────


def test_texto_tarea_incluye_estado_y_nota():
    t = {"titulo": "Subir build", "nota": "firmar APK", "completada": False}
    assert "Tarea (pendiente): Subir build" in r.texto_tarea(t)
    assert "firmar APK" in r.texto_tarea(t)
    assert "completada" in r.texto_tarea({**t, "completada": True})


def test_texto_proyecto_y_nota_y_evaluacion():
    p = r.texto_proyecto({"nombre": "Shadow Games", "linea_meta": "lanzar demo", "estado": "activo"})
    assert "Proyecto (activo): Shadow Games" in p and "Meta: lanzar demo" in p
    n = r.texto_nota({"titulo": "Idea", "etiquetas": ["ux", "juego"], "contenido": "mejorar onboarding"})
    assert "Nota: Idea" in n and "Etiquetas: ux, juego" in n and "mejorar onboarding" in n
    e = r.texto_evaluacion({"titulo": "Parcial 2", "tipo": "examen", "fecha": "2026-06-20"}, curso="Cálculo")
    assert "Evaluación (examen): Parcial 2" in e and "del curso Cálculo" in e


def test_hash_determinista_y_sensible():
    assert r._hash("abc") == r._hash("abc")
    assert r._hash("abc") != r._hash("abd")


# ── Bloque inyectado ─────────────────────────────────────────────────────────


def test_bloque_recuerdos_formatea_y_vacio():
    assert r.bloque_recuerdos([]) == ""
    filas = [
        {"fuente_tipo": "proyecto", "contenido": "Proyecto (activo): Shadow Games"},
        {"fuente_tipo": "tarea", "contenido": "Tarea (pendiente): subir  build\n con saltos"},
    ]
    out = r.bloque_recuerdos(filas)
    assert "MEMORIA DE TU VIDA" in out
    assert "[Proyecto] Proyecto (activo): Shadow Games" in out
    # Normaliza espacios/saltos en una línea.
    assert "[Tarea] Tarea (pendiente): subir build con saltos" in out


# ── Fakes de BD ──────────────────────────────────────────────────────────────


class _FakeDB:
    """BD mínima en memoria para indexar/recuperar sin red."""

    def __init__(self, hash_previo: str | None = None, rpc_filas=None):
        self._hash_previo = hash_previo
        self._rpc_filas = rpc_filas or []
        self.upserts: list[dict] = []
        self.borrados: list[dict] = []

    async def list(self, table, *, raw_filters=None, select=None, limit=None):
        if self._hash_previo is None:
            return []
        return [{"contenido_hash": self._hash_previo}]

    async def upsert(self, table, payload, *, on_conflict):
        self.upserts.append(payload)
        return payload

    async def delete_where(self, table, *, filters):
        self.borrados.append(filters)
        return 1

    async def rpc(self, function, payload=None):
        return self._rpc_filas

    async def get(self, table, row_id):
        return None


# ── Incremental por hash (núcleo del costo/rendimiento) ──────────────────────


async def test_indexar_salta_si_no_cambio(monkeypatch):
    contenido = "Proyecto (activo): Shadow Games"
    db = _FakeDB(hash_previo=r._hash(contenido))
    llamado = {"n": 0}

    async def fake_embebir(textos):
        llamado["n"] += 1
        return [[0.0] * 1536]

    monkeypatch.setattr(r.llm, "embebir_seguro", fake_embebir)
    est = await r.indexar(db, fuente_tipo="proyecto", fuente_id="p1", contenido=contenido)
    assert est == "sin_cambio"
    assert llamado["n"] == 0  # NO re-embebió
    assert db.upserts == []   # NO escribió


async def test_indexar_embebe_y_upserta_si_cambio(monkeypatch):
    db = _FakeDB(hash_previo=r._hash("viejo"))

    async def fake_embebir(textos):
        return [[0.1] * 1536]

    monkeypatch.setattr(r.llm, "embebir_seguro", fake_embebir)
    est = await r.indexar(db, fuente_tipo="tarea", fuente_id="t1", contenido="Tarea nueva")
    assert est == "indexado"
    assert len(db.upserts) == 1
    up = db.upserts[0]
    assert up["fuente_tipo"] == "tarea" and up["fuente_id"] == "t1"
    assert up["embedding"] is not None
    assert up["contenido_hash"] == r._hash("Tarea nueva")


async def test_indexar_sin_credito_guarda_sin_hash_para_reintentar(monkeypatch):
    db = _FakeDB(hash_previo=None)

    async def fake_embebir(textos):
        return None  # sin crédito de embeddings

    monkeypatch.setattr(r.llm, "embebir_seguro", fake_embebir)
    est = await r.indexar(db, fuente_tipo="tarea", fuente_id="t1", contenido="x")
    assert est == "sin_embedding"
    # hash vacío → la próxima vez REINTENTA (no queda "cacheado" sin vector).
    assert db.upserts[0]["contenido_hash"] == ""
    assert db.upserts[0]["embedding"] is None


async def test_indexar_vacio_olvida():
    db = _FakeDB()
    est = await r.indexar(db, fuente_tipo="nota", fuente_id="n1", contenido="   ")
    assert est == "vacio"
    assert db.borrados  # llamó a olvidar


async def test_indexar_nunca_lanza(monkeypatch):
    async def explota(textos):
        raise RuntimeError("boom")

    monkeypatch.setattr(r.llm, "embebir_seguro", explota)
    est = await r.indexar(_FakeDB(hash_previo=None), fuente_tipo="tarea", fuente_id="t", contenido="x")
    assert est == "error"  # tragó la excepción


# ── Recuperación con umbral ──────────────────────────────────────────────────


async def test_recuperar_filtra_por_umbral():
    filas = [
        {"fuente_tipo": "proyecto", "contenido": "cerca", "distancia": 0.30},
        {"fuente_tipo": "tarea", "contenido": "medio", "distancia": 0.70},
        {"fuente_tipo": "evento", "contenido": "lejos", "distancia": 0.95},
    ]
    db = _FakeDB(rpc_filas=filas)
    out = await r.recuperar(db, embedding=[0.0] * 1536, umbral=0.75)
    contenidos = [f["contenido"] for f in out]
    assert "cerca" in contenidos and "medio" in contenidos
    assert "lejos" not in contenidos  # 0.95 > 0.75 → descartado


async def test_recuperar_sin_consulta_ni_embedding():
    assert await r.recuperar(_FakeDB(), consulta="") == []


# ── Hook del dispatcher de comandos (ruteo UI + IA) ──────────────────────────


def test_hook_comando_rutea_index_y_forget(monkeypatch):
    idx: list = []
    olv: list = []
    monkeypatch.setattr(r, "indexar_entidad_async",
                        lambda db, tipo, fila, **kw: idx.append((tipo, fila.get("id"), kw.get("subtipo"))))
    monkeypatch.setattr(r, "olvidar_entidad_async",
                        lambda db, tipo, fid, **kw: olv.append((tipo, fid, kw.get("subtipo"))))

    r.hook_comando(None, "crear_tarea", {"ok": True, "datos": {"id": "t1", "titulo": "x"}})
    r.hook_comando(None, "editar_proyecto", {"ok": True, "datos": {"id": "p1"}})
    r.hook_comando(None, "crear_evaluacion", {"ok": True, "datos": {"id": "e1"}})
    r.hook_comando(None, "eliminar_evento", {"ok": True, "datos": {"id": "ev1"}})
    r.hook_comando(None, "eliminar_curso", {"ok": True, "datos": {"id": "c1"}})

    assert ("tarea", "t1", None) in idx
    assert ("proyecto", "p1", None) in idx
    assert ("universidad", "e1", "evaluacion") in idx
    assert ("universidad", "ev1", "evento") in olv
    assert ("universidad", "c1", "curso") in olv


def test_hook_comando_restaurar_reindexa(monkeypatch):
    # Restaurar de la papelera RE-INDEXA (la entidad vuelve a estar viva).
    idx: list = []
    monkeypatch.setattr(r, "indexar_entidad_async",
                        lambda db, tipo, fila, **kw: idx.append((tipo, fila.get("id"), kw.get("subtipo"))))
    r.hook_comando(None, "restaurar_tarea", {"ok": True, "datos": {"id": "t9", "eliminado_en": None}})
    r.hook_comando(None, "restaurar_evento", {"ok": True, "datos": {"id": "ev9"}})
    assert ("tarea", "t9", None) in idx
    assert ("universidad", "ev9", "evento") in idx


def test_umbral_default_es_conservador():
    # Coherente con la migración ("match razonable < ~0.6"): no permisivo.
    assert r.UMBRAL_DISTANCIA <= 0.65


def test_hook_comando_lote_de_tareas(monkeypatch):
    idx: list = []
    monkeypatch.setattr(r, "indexar_entidad_async",
                        lambda db, tipo, fila, **kw: idx.append((tipo, fila.get("id"))))
    r.hook_comando(None, "crear_tareas", {"ok": True, "datos": {"tareas": [{"id": "a"}, {"id": "b"}]}})
    assert idx == [("tarea", "a"), ("tarea", "b")]


def test_hook_comando_ignora_lo_no_mapeado(monkeypatch):
    llamado = {"n": 0}
    monkeypatch.setattr(r, "indexar_entidad_async", lambda *a, **k: llamado.__setitem__("n", llamado["n"] + 1))
    monkeypatch.setattr(r, "olvidar_entidad_async", lambda *a, **k: llamado.__setitem__("n", llamado["n"] + 1))
    # comando sin mapeo (p.ej. sesiones de clase, que se omiten a propósito)
    r.hook_comando(None, "crear_sesion_clase", {"ok": True, "datos": {"id": "s1"}})
    # comando OK pero sin id en datos
    r.hook_comando(None, "crear_tarea", {"ok": True, "datos": {}})
    assert llamado["n"] == 0


async def test_indexar_entidad_papelera_olvida_no_indexa(monkeypatch):
    # Editar/tocar una entidad en la papelera (eliminado_en) NO la resucita:
    # se olvida en vez de indexar.
    db = _FakeDB(hash_previo=None)
    llamado = {"emb": 0}

    async def fake_embebir(textos):
        llamado["emb"] += 1
        return [[0.0] * 1536]

    monkeypatch.setattr(r.llm, "embebir_seguro", fake_embebir)
    est = await r.indexar_entidad(
        db, "tarea", {"id": "t1", "titulo": "borrada", "eliminado_en": "2026-06-12T00:00:00Z"}
    )
    assert est == "eliminado"
    assert llamado["emb"] == 0  # no embebió
    assert db.upserts == []     # no indexó
    assert db.borrados          # olvidó


async def test_indexar_entidad_universidad_compone_fid(monkeypatch):
    db = _FakeDB(hash_previo=None)

    async def fake_embebir(textos):
        return [[0.0] * 1536]

    monkeypatch.setattr(r.llm, "embebir_seguro", fake_embebir)
    await r.indexar_entidad(db, "universidad", {"id": "abc", "titulo": "Parcial"}, subtipo="evaluacion")
    # fuente_id compuesto subtipo:id para no chocar entre cursos/evals/eventos.
    assert db.upserts[0]["fuente_id"] == "evaluacion:abc"
    assert db.upserts[0]["metadata"]["subtipo"] == "evaluacion"


# ── Inyección automática en el chat (helpers de chat.py) ─────────────────────


async def test_recall_automatico_guarda_casos_triviales():
    from app.matix import chat
    # db None → sin recall (no se puede recuperar nada).
    assert await chat._recall_automatico(None, "qué tengo pendiente?", None) == ""
    # mensaje muy corto → no amerita recall (ni su costo).
    assert await chat._recall_automatico(_FakeDB(), "ok", None) == ""


def test_bloque_historial_formatea_con_fecha():
    from app.matix import chat
    assert chat._bloque_historial([]) == ""
    out = chat._bloque_historial([
        {"contenido": "Usuario: hola\nMatix: qué tal", "fecha_texto": "ayer", "distancia": 0.3},
    ])
    assert "DE CONVERSACIONES PASADAS" in out
    assert "(ayer)" in out
