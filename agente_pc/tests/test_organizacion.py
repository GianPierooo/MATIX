"""Acciones consecuentes (6.1): mover/renombrar/crear_carpeta/organizar.

Foco de seguridad: el gate `confirmado` es obligatorio, no se sobreescribe, el
path traversal y los destinos fuera de la allowlist se rechazan, y organizar
revalida cada paso. Usa el fixture `area`.
"""
from __future__ import annotations

import asyncio
import os

from agente_pc.acciones import crear_registro
from agente_pc.registro import Contexto


def _run(nombre, args, ctx, **kw):
    return asyncio.run(crear_registro().ejecutar(nombre, args, ctx, **kw))


# ── Niveles: ops de UN archivo son DIRECTAS; solo organizar confirma ─────────


def test_mover_sin_confirmar_ejecuta_directo(area):
    # mover es SEGURA (reversible, no sobreescribe) → se ejecuta DIRECTO,
    # sin gate de confirmación.
    (area / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("mover_archivo", {"origen": str(area / "f.txt"), "destino": str(area / "g.txt")}, ctx)
    assert res["ok"] is True
    assert not (area / "f.txt").exists()
    assert (area / "g.txt").exists()


def test_ops_de_un_archivo_son_directas(area):
    # mover/copiar/renombrar/crear_carpeta NO exigen confirmado (SEGURA).
    from agente_pc.registro import NivelRiesgo
    reg = crear_registro()
    for nombre in ("mover_archivo", "copiar_archivo", "renombrar_archivo", "crear_carpeta"):
        assert reg.get(nombre).nivel is NivelRiesgo.SEGURA, nombre
    # organizar (lote) SÍ confirma: sin confirmado el registry corta antes.
    assert reg.get("organizar_aplicar").nivel is NivelRiesgo.CONSECUENTE
    ctx = Contexto(allowlist=[area])
    res = _run("organizar_aplicar", {"carpeta": str(area), "criterio": "por tipo"}, ctx)
    assert res["tipo"] == "requiere_confirmacion"


# ── mover_archivo ────────────────────────────────────────────────────────────


def test_mover_ok(area):
    (area / "f.txt").write_text("hola", encoding="utf-8")
    destino = area / "sub"
    destino.mkdir()
    ctx = Contexto(allowlist=[area])
    res = _run("mover_archivo", {"origen": str(area / "f.txt"), "destino": str(destino)}, ctx, confirmado=True)
    assert res["ok"] is True
    assert (destino / "f.txt").exists()
    assert not (area / "f.txt").exists()


def test_mover_no_sobreescribe(area):
    (area / "f.txt").write_text("uno", encoding="utf-8")
    (area / "g.txt").write_text("dos", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("mover_archivo", {"origen": str(area / "f.txt"), "destino": str(area / "g.txt")}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "destino_existe"
    assert (area / "g.txt").read_text(encoding="utf-8") == "dos"  # intacto


def test_mover_destino_fuera_rechaza(area):
    sub = area / "permitida"
    sub.mkdir()
    (sub / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[sub])
    # destino sube fuera de la allowlist
    res = _run("mover_archivo", {"origen": str(sub / "f.txt"), "destino": str(area / "f.txt")}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "rechazada"
    assert (sub / "f.txt").exists()  # no se movió


def test_mover_traversal_rechaza(area):
    (area / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    destino = os.path.join(str(area), "..", "..", "escapado.txt")
    res = _run("mover_archivo", {"origen": str(area / "f.txt"), "destino": destino}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "rechazada"


# ── copiar_archivo ───────────────────────────────────────────────────────────


def test_copiar_ok(area):
    (area / "f.txt").write_text("hola", encoding="utf-8")
    destino = area / "sub"
    destino.mkdir()
    ctx = Contexto(allowlist=[area])
    res = _run("copiar_archivo", {"origen": str(area / "f.txt"), "destino": str(destino)}, ctx)
    assert res["ok"] is True
    # La copia existe Y el original sigue ahí (reversible).
    assert (destino / "f.txt").read_text(encoding="utf-8") == "hola"
    assert (area / "f.txt").exists()


def test_copiar_no_sobreescribe(area):
    (area / "f.txt").write_text("uno", encoding="utf-8")
    (area / "g.txt").write_text("dos", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("copiar_archivo", {"origen": str(area / "f.txt"), "destino": str(area / "g.txt")}, ctx)
    assert res["ok"] is False
    assert res["tipo"] == "destino_existe"
    assert (area / "g.txt").read_text(encoding="utf-8") == "dos"  # intacto


def test_copiar_origen_inexistente(area):
    ctx = Contexto(allowlist=[area])
    res = _run("copiar_archivo", {"origen": str(area / "no.txt"), "destino": str(area / "x.txt")}, ctx)
    assert res["ok"] is False and res["tipo"] == "no_existe"


def test_copiar_destino_fuera_rechaza(area):
    sub = area / "permitida"
    sub.mkdir()
    (sub / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[sub])
    res = _run("copiar_archivo", {"origen": str(sub / "f.txt"), "destino": str(area / "f.txt")}, ctx)
    assert res["ok"] is False and res["tipo"] == "rechazada"


# ── renombrar_archivo ────────────────────────────────────────────────────────


def test_renombrar_ok(area):
    (area / "viejo.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("renombrar_archivo", {"ruta": str(area / "viejo.txt"), "nuevo_nombre": "nuevo.txt"}, ctx, confirmado=True)
    assert res["ok"] is True
    assert (area / "nuevo.txt").exists()
    assert not (area / "viejo.txt").exists()


def test_renombrar_con_separador_rechaza(area):
    (area / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("renombrar_archivo", {"ruta": str(area / "f.txt"), "nuevo_nombre": "sub/otro.txt"}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "nombre_invalido"


def test_renombrar_traversal_rechaza(area):
    (area / "f.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("renombrar_archivo", {"ruta": str(area / "f.txt"), "nuevo_nombre": ".."}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "nombre_invalido"


# ── crear_carpeta ────────────────────────────────────────────────────────────


def test_crear_carpeta_ok(area):
    ctx = Contexto(allowlist=[area])
    res = _run("crear_carpeta", {"ruta": str(area / "nueva")}, ctx, confirmado=True)
    assert res["ok"] is True
    assert (area / "nueva").is_dir()


def test_crear_carpeta_ya_existe(area):
    (area / "ya").mkdir()
    ctx = Contexto(allowlist=[area])
    res = _run("crear_carpeta", {"ruta": str(area / "ya")}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "ya_existe"


def test_crear_carpeta_fuera_rechaza(area):
    sub = area / "permitida"
    sub.mkdir()
    ctx = Contexto(allowlist=[sub])
    res = _run("crear_carpeta", {"ruta": str(area / "nueva")}, ctx, confirmado=True)
    assert res["ok"] is False
    assert res["tipo"] == "rechazada"


# ── organizar_aplicar (multi-paso) ───────────────────────────────────────────


def test_organizar_por_tipo_ejecuta(area):
    (area / "a.txt").write_text("x", encoding="utf-8")
    (area / "b.jpg").write_bytes(b"\xff\xd8")
    (area / "c.pdf").write_bytes(b"%PDF")
    ctx = Contexto(allowlist=[area])
    res = _run("organizar_aplicar", {"carpeta": str(area), "criterio": "por tipo"}, ctx, confirmado=True)
    assert res["ok"] is True
    assert (area / "Documentos" / "a.txt").exists()
    assert (area / "Imágenes" / "b.jpg").exists()
    assert (area / "Documentos" / "c.pdf").exists()
    assert res["total_movidos"] == 3
    # No quedaron sueltos en la raíz.
    assert not (area / "a.txt").exists()


def test_organizar_preview_igual_a_ejecucion(area):
    # El plan que muestra planificar_organizacion == lo que ejecuta aplicar.
    (area / "foto.jpg").write_bytes(b"\xff\xd8")
    (area / "nota.txt").write_text("x", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    plan = _run("planificar_organizacion", {"carpeta": str(area), "criterio": "por tipo"}, ctx)
    destinos_plan = {os.path.basename(os.path.dirname(p["destino"])) for p in plan["plan"]}
    res = _run("organizar_aplicar", {"carpeta": str(area), "criterio": "por tipo"}, ctx, confirmado=True)
    destinos_real = {os.path.basename(os.path.dirname(m["destino"])) for m in res["movidos"]}
    assert destinos_plan == destinos_real


def test_organizar_no_sobreescribe_conflicto(area):
    (area / "a.txt").write_text("nuevo", encoding="utf-8")
    # Ya hay un Documentos/a.txt: el archivo suelto debe OMITIRSE, no pisar.
    (area / "Documentos").mkdir()
    (area / "Documentos" / "a.txt").write_text("existente", encoding="utf-8")
    ctx = Contexto(allowlist=[area])
    res = _run("organizar_aplicar", {"carpeta": str(area), "criterio": "por tipo"}, ctx, confirmado=True)
    assert res["ok"] is True
    assert any(o["motivo"] == "el destino ya existe" for o in res["omitidos"])
    assert (area / "Documentos" / "a.txt").read_text(encoding="utf-8") == "existente"
