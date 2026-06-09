"""Fase 6.3 — rails LOCALES del control de pantalla en el agente.

El controlador/capturador/indicador se INYECTAN (fakes): NO se toca el mouse ni
la pantalla reales. Cubre: master switch OFF→rechaza, sesión requerida, tope de
acciones, kill switch (failsafe) aborta la sesión, validación de acción,
audit sin contenido, y el gate consecuente (confirmado) vía el Registro.
"""
from __future__ import annotations

import asyncio

from agente_pc import pantalla
from agente_pc.acciones import crear_registro
from agente_pc.registro import Contexto, NivelRiesgo


class _ControladorFake:
    def __init__(self, resultado=None) -> None:
        self.acciones: list = []
        self.resultado = resultado or {"ok": True}

    def __call__(self, accion: dict) -> dict:
        self.acciones.append(accion)
        return self.resultado


class _CapturadorFake:
    def __init__(self) -> None:
        self.veces = 0

    def __call__(self) -> dict:
        self.veces += 1
        return {"ok": True, "imagen": "data:image/jpeg;base64,Zg==", "ancho": 1280, "alto": 720}


class _IndicadorFake:
    def __init__(self) -> None:
        self.mostrado = 0
        self.ocultado = 0

    def mostrar(self) -> None:
        self.mostrado += 1

    def ocultar(self) -> None:
        self.ocultado += 1


def _ctx(control=True, max_acc=40, ctrl=None, cap=None, ind=None) -> Contexto:
    return Contexto(
        control_pantalla=control,
        max_acciones_pantalla=max_acc,
        controlador=ctrl,
        capturador=cap,
        indicador=ind,
    )


_CLICK = {"tipo": "click", "x": 100, "y": 200}


# ── Master switch OFF (el rail más fuerte) ───────────────────────────────────


def test_control_off_rechaza_todo():
    ctx = _ctx(control=False)
    for nombre, args in [
        ("pantalla_control_iniciar", {}),
        ("pantalla_capturar", {}),
        ("pantalla_accion", {"accion": _CLICK}),
    ]:
        # llamamos al handler vía el registry (con confirmado para los consecuentes)
        r = asyncio.run(crear_registro().ejecutar(nombre, args, ctx, confirmado=True))
        assert not r["ok"] and r["tipo"] == "control_desactivado", nombre


# ── Sesión requerida ─────────────────────────────────────────────────────────


def test_accion_sin_sesion_rechazada():
    ctx = _ctx(control=True, ctrl=_ControladorFake())
    r = pantalla._pantalla_accion({"accion": _CLICK}, ctx)
    assert not r["ok"] and r["tipo"] == "sin_sesion"


def test_capturar_sin_sesion_rechazado():
    ctx = _ctx(control=True, cap=_CapturadorFake())
    r = pantalla._pantalla_capturar({}, ctx)
    assert not r["ok"] and r["tipo"] == "sin_sesion"


# ── Sesión: iniciar muestra indicador, acción cuenta, terminar oculta ────────


def test_sesion_feliz_iniciar_actuar_terminar():
    ctrl = _ControladorFake()
    cap = _CapturadorFake()
    ind = _IndicadorFake()
    ctx = _ctx(control=True, ctrl=ctrl, cap=cap, ind=ind)

    assert pantalla._pantalla_control_iniciar({}, ctx)["ok"]
    assert ind.mostrado == 1
    assert ctx.pantalla_sesion["activa"] is True

    assert pantalla._pantalla_capturar({}, ctx)["ok"]
    assert cap.veces == 1

    r = pantalla._pantalla_accion({"accion": _CLICK}, ctx)
    assert r["ok"] and r["tipo"] == "accion_hecha"
    assert ctrl.acciones == [_CLICK]
    assert ctx.pantalla_sesion["acciones"] == 1

    fin = pantalla._pantalla_control_terminar({}, ctx)
    assert fin["ok"] and ind.ocultado == 1
    assert ctx.pantalla_sesion["activa"] is False


# ── Tope de acciones por sesión (anti-runaway) ───────────────────────────────


def test_tope_de_acciones_aborta_la_sesion():
    ctrl = _ControladorFake()
    ctx = _ctx(control=True, max_acc=2, ctrl=ctrl, ind=_IndicadorFake())
    pantalla._pantalla_control_iniciar({}, ctx)
    assert pantalla._pantalla_accion({"accion": _CLICK}, ctx)["ok"]
    assert pantalla._pantalla_accion({"accion": _CLICK}, ctx)["ok"]
    # La 3ra supera el tope (2) → abort, sesión cerrada.
    r = pantalla._pantalla_accion({"accion": _CLICK}, ctx)
    assert not r["ok"] and r["tipo"] == "tope_acciones"
    assert ctx.pantalla_sesion["activa"] is False
    assert len(ctrl.acciones) == 2  # la 3ra NO se ejecutó


# ── Kill switch (failsafe) corta la sesión ───────────────────────────────────


def test_kill_switch_aborta_la_sesion():
    ctrl = _ControladorFake(resultado={"ok": False, "tipo": "abortado_killswitch",
                                       "mensaje": "mouse a la esquina"})
    ctx = _ctx(control=True, ctrl=ctrl, ind=_IndicadorFake())
    pantalla._pantalla_control_iniciar({}, ctx)
    r = pantalla._pantalla_accion({"accion": _CLICK}, ctx)
    assert not r["ok"] and r["tipo"] == "abortado_killswitch"
    assert ctx.pantalla_sesion["activa"] is False  # sesión cortada


# ── Validación de acciones ───────────────────────────────────────────────────


def test_validar_accion_rechaza_basura():
    casos = [
        {"tipo": "ejecutar", "cmd": "rm -rf /"},   # tipo inexistente
        {"tipo": "click", "x": -5, "y": 10},        # coord inválida
        {"tipo": "tecla", "tecla": "ctrl"},          # tecla no permitida (combo)
        {"tipo": "escribir", "texto": 123},          # texto no string
        "no soy dict",
    ]
    for c in casos:
        ok, _ = pantalla.validar_accion(c)
        assert not ok, c


def test_accion_invalida_no_se_ejecuta():
    ctrl = _ControladorFake()
    ctx = _ctx(control=True, ctrl=ctrl, ind=_IndicadorFake())
    pantalla._pantalla_control_iniciar({}, ctx)
    r = pantalla._pantalla_accion({"accion": {"tipo": "tecla", "tecla": "f4"}}, ctx)
    assert not r["ok"] and r["tipo"] == "accion_invalida"
    assert ctrl.acciones == []


# ── Audit: el resumen NO lleva el texto tecleado ─────────────────────────────


def test_resumen_no_filtra_texto():
    r = pantalla.resumen_accion({"tipo": "escribir", "texto": "mi-clave-secreta"})
    assert "clave" not in r and "secreta" not in r
    assert "chars" in r


# ── Acción confirmada (gate) es one-shot, sin sesión, pero exige master switch ─


def test_accion_confirmada_one_shot():
    ctrl = _ControladorFake()
    ctx = _ctx(control=True, ctrl=ctrl, ind=_IndicadorFake())
    # NO iniciamos sesión: la confirmada es one-shot.
    r = pantalla._pantalla_accion_confirmada({"accion": _CLICK}, ctx)
    assert r["ok"] and r["tipo"] == "accion_confirmada_hecha"
    assert ctrl.acciones == [_CLICK]


def test_accion_confirmada_requiere_master_switch():
    ctx = _ctx(control=False, ctrl=_ControladorFake())
    r = pantalla._pantalla_accion_confirmada({"accion": _CLICK}, ctx)
    assert not r["ok"] and r["tipo"] == "control_desactivado"


# ── Gate consecuente vía el Registro ─────────────────────────────────────────


def test_pantalla_accion_es_consecuente():
    reg = crear_registro()
    assert reg.get("pantalla_accion").nivel is NivelRiesgo.CONSECUENTE
    assert reg.get("pantalla_capturar").nivel is NivelRiesgo.CONSECUENTE
    assert reg.get("pantalla_control_iniciar").nivel is NivelRiesgo.CONSECUENTE
    ctrl = _ControladorFake()
    ctx = _ctx(control=True, ctrl=ctrl, ind=_IndicadorFake())
    pantalla._pantalla_control_iniciar({}, ctx)
    # Sin confirmado: el registry corta antes de ejecutar.
    r = asyncio.run(reg.ejecutar("pantalla_accion", {"accion": _CLICK}, ctx, confirmado=False))
    assert not r["ok"] and r["tipo"] == "requiere_confirmacion"
    assert ctrl.acciones == []
