"""Registry: registro, validación de params y enforcement de niveles de riesgo."""
from __future__ import annotations

import asyncio

import pytest

from agente_pc.registro import AccionDef, Contexto, NivelRiesgo, Param, Registro


def _accion(nivel: NivelRiesgo, handler=None) -> AccionDef:
    async def _eco(args, ctx):
        return {"ok": True, "eco": args}

    return AccionDef(
        nombre="demo",
        descripcion="demo",
        parametros=(Param("x", str, requerido=True),),
        nivel=nivel,
        handler=handler or _eco,
    )


def test_registrar_y_obtener():
    r = Registro()
    a = _accion(NivelRiesgo.SEGURA)
    r.registrar(a)
    assert r.get("demo") is a
    assert r.nombres() == ["demo"]


def test_registrar_duplicada_falla():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.SEGURA))
    with pytest.raises(ValueError):
        r.registrar(_accion(NivelRiesgo.SEGURA))


def test_accion_desconocida():
    r = Registro()
    res = asyncio.run(r.ejecutar("nope", {}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "desconocida"


def test_prohibida_nunca_ejecuta():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.PROHIBIDA))
    res = asyncio.run(r.ejecutar("demo", {"x": "y"}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "prohibida"


def test_consecuente_requiere_confirmacion():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.CONSECUENTE))
    res = asyncio.run(r.ejecutar("demo", {"x": "y"}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "requiere_confirmacion"


def test_valida_param_requerido():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.SEGURA))
    res = asyncio.run(r.ejecutar("demo", {}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "validacion"


def test_valida_tipo_de_param():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.SEGURA))
    res = asyncio.run(r.ejecutar("demo", {"x": 123}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "validacion"


def test_segura_happy_path():
    r = Registro()
    r.registrar(_accion(NivelRiesgo.SEGURA))
    res = asyncio.run(r.ejecutar("demo", {"x": "hola"}, Contexto()))
    assert res["ok"] is True
    assert res["eco"] == {"x": "hola"}


def test_handler_que_revienta_no_propaga():
    async def _boom(args, ctx):
        raise RuntimeError("boom")

    r = Registro()
    r.registrar(
        AccionDef("demo", "d", (Param("x", str),), NivelRiesgo.SEGURA, _boom)
    )
    res = asyncio.run(r.ejecutar("demo", {"x": "a"}, Contexto()))
    assert res["ok"] is False
    assert res["tipo"] == "interno"
