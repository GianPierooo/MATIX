"""Acción listar_carpeta: lista nombres dentro de la allowlist, oculta
secretos, nunca devuelve contenido, y rechaza fuera de la allowlist.

Usa el fixture `area` (bajo el home, no bajo AppData denylisted).
"""
from __future__ import annotations

import asyncio

from agente_pc.acciones import crear_registro
from agente_pc.registro import Contexto


def test_listar_carpeta_dentro_de_allowlist(area):
    (area / "a.txt").write_text("CONTENIDO-SECRETO-NO-LEER", encoding="utf-8")
    (area / "sub").mkdir()
    (area / ".env").write_text("TOKEN=x", encoding="utf-8")  # debe ocultarse
    (area / "id_rsa").write_text("clave", encoding="utf-8")  # debe ocultarse

    reg = crear_registro()
    ctx = Contexto(allowlist=[area])
    res = asyncio.run(reg.ejecutar("listar_carpeta", {"ruta": str(area)}, ctx))

    assert res["ok"] is True
    nombres = {e["nombre"] for e in res["entradas"]}
    assert nombres == {"a.txt", "sub"}  # .env e id_rsa ocultos
    # Nunca aparece el contenido del archivo, solo metadatos de nombre/tipo.
    assert "CONTENIDO-SECRETO-NO-LEER" not in str(res)
    tipos = {e["nombre"]: e["tipo"] for e in res["entradas"]}
    assert tipos["sub"] == "carpeta"
    assert tipos["a.txt"] == "archivo"


def test_listar_carpeta_fuera_de_allowlist_rechaza(area):
    permitida = area / "permitida"
    permitida.mkdir()
    reg = crear_registro()
    ctx = Contexto(allowlist=[permitida])
    # Pedimos el padre, que NO está permitido.
    res = asyncio.run(reg.ejecutar("listar_carpeta", {"ruta": str(area)}, ctx))
    assert res["ok"] is False
    assert res["tipo"] == "rechazada"


def test_listar_carpeta_sin_ruta_es_validacion(area):
    reg = crear_registro()
    ctx = Contexto(allowlist=[area])
    res = asyncio.run(reg.ejecutar("listar_carpeta", {}, ctx))
    assert res["ok"] is False
    assert res["tipo"] == "validacion"


def test_listar_carpeta_no_existe(area):
    reg = crear_registro()
    ctx = Contexto(allowlist=[area])
    objetivo = area / "no_existe"
    res = asyncio.run(reg.ejecutar("listar_carpeta", {"ruta": str(objetivo)}, ctx))
    assert res["ok"] is False
    assert res["tipo"] == "no_existe"
