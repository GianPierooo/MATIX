"""Fase 6.2 — tareas tipadas: solo tareas registradas, params tipados, compone
primitivas seguras (allowlist de apps + de carpetas), falla cerrado, sin shell.
"""
from __future__ import annotations

import asyncio

from agente_pc import tareas
from agente_pc.acciones import crear_registro
from agente_pc.registro import Contexto, NivelRiesgo

_CODE = r"C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe"
_CMD = r"C:\Windows\System32\cmd.exe"


class _LanzadorFake:
    def __init__(self) -> None:
        self.llamadas: list[tuple[str, list]] = []
        self._pid = 2000

    def __call__(self, exe: str, args: list) -> dict:
        self.llamadas.append((exe, list(args)))
        self._pid += 1
        return {"ok": True, "pid": self._pid}


def _ctx(apps_map, allowlist=None, lanzador=None) -> Contexto:
    return Contexto(
        allowlist=allowlist or [],
        apps=apps_map,
        lanzador=lanzador,
    )


# ── Registro de tareas ───────────────────────────────────────────────────────


def test_tareas_registradas_incluye_ejemplos():
    regs = tareas.tareas_registradas()
    assert "sesion_de_foco" in regs
    assert "abrir_proyecto" in regs


def test_ejecutar_tarea_desconocida_rechazada():
    r = tareas._ejecutar_tarea({"nombre": "formatear_disco"}, _ctx({"code": _CODE}))
    assert not r["ok"] and r["tipo"] == "no_registrada"
    assert "sesion_de_foco" in r["registradas"]


def test_ejecutar_tarea_sin_nombre():
    r = tareas._ejecutar_tarea({}, _ctx({"code": _CODE}))
    assert not r["ok"] and r["tipo"] == "validacion"


# ── sesion_de_foco ───────────────────────────────────────────────────────────


def test_sesion_de_foco_abre_apps_de_la_allowlist():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE, "chrome": r"C:\Program Files\Google\Chrome\Application\chrome.exe"},
               lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "sesion_de_foco", "params": {"apps": "code, chrome"}}, ctx
    )
    assert r["ok"] and r["tipo"] == "sesion_de_foco"
    assert set(r["abiertas"]) == {"code", "chrome"}
    assert r["fallidas"] == []
    assert len(lz.llamadas) == 2


def test_sesion_de_foco_app_no_permitida_falla_cerrado_por_app():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "sesion_de_foco", "params": {"apps": "code, inkscape"}}, ctx
    )
    # code abre; inkscape (no allowlisted) falla — reportado, sin reventar.
    assert r["ok"]  # al menos una abrió
    assert r["abiertas"] == ["code"]
    assert r["fallidas"] and r["fallidas"][0]["app"] == "inkscape"
    assert len(lz.llamadas) == 1  # solo code se lanzó


def test_sesion_de_foco_inyeccion_de_shell_imposible():
    # Intentar colar un comando como "app": no está en la allowlist → falla.
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "sesion_de_foco", "params": {"apps": "cmd, powershell, rm -rf /"}}, ctx
    )
    assert not r["ok"]  # ninguna abrió
    assert r["abiertas"] == []
    assert len(lz.llamadas) == 0  # nada se lanzó


def test_sesion_de_foco_params_faltantes():
    r = tareas._ejecutar_tarea({"nombre": "sesion_de_foco", "params": {}}, _ctx({"code": _CODE}))
    assert not r["ok"] and r["tipo"] == "validacion"


# ── abrir_proyecto ───────────────────────────────────────────────────────────


def test_abrir_proyecto_con_carpeta_permitida_y_editor_allowlisted(area):
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, allowlist=[area], lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "abrir_proyecto", "params": {"carpeta": str(area), "editor": "code"}}, ctx
    )
    assert r["ok"] and r["tipo"] == "abrir_proyecto"
    # El editor se lanzó con la carpeta REAL como argumento.
    assert len(lz.llamadas) == 1
    exe, args = lz.llamadas[0]
    assert exe == _CODE and len(args) == 1


def test_abrir_proyecto_carpeta_no_permitida(area, tmp_path):
    # area está permitida; pasamos OTRA carpeta no permitida.
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, allowlist=[area], lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "abrir_proyecto",
         "params": {"carpeta": str(area.parent), "editor": "code"}}, ctx
    )
    assert not r["ok"] and r["tipo"] == "rechazada"
    assert len(lz.llamadas) == 0


def test_abrir_proyecto_editor_no_allowlisted(area):
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, allowlist=[area], lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "abrir_proyecto", "params": {"carpeta": str(area), "editor": "sublime"}}, ctx
    )
    assert not r["ok"] and r["tipo"] == "app_no_permitida"
    assert len(lz.llamadas) == 0


def test_abrir_proyecto_editor_denylisted(area):
    # Editor que resuelve a un shell → denylist gana.
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE, "trampa": _CMD}, allowlist=[area], lanzador=lz)
    r = tareas._ejecutar_tarea(
        {"nombre": "abrir_proyecto", "params": {"carpeta": str(area), "editor": "trampa"}}, ctx
    )
    assert not r["ok"] and r["tipo"] == "denylist"
    assert len(lz.llamadas) == 0


# ── Gate consecuente vía el Registro real ────────────────────────────────────


def test_ejecutar_tarea_es_consecuente_y_exige_confirmado(area):
    reg = crear_registro()
    assert reg.get("ejecutar_tarea").nivel is NivelRiesgo.CONSECUENTE
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, allowlist=[area], lanzador=lz)
    r = asyncio.run(reg.ejecutar(
        "ejecutar_tarea",
        {"nombre": "sesion_de_foco", "params": {"apps": "code"}},
        ctx, confirmado=False,
    ))
    assert not r["ok"] and r["tipo"] == "requiere_confirmacion"
    assert lz.llamadas == []  # gate cortó antes de lanzar
    r2 = asyncio.run(reg.ejecutar(
        "ejecutar_tarea",
        {"nombre": "sesion_de_foco", "params": {"apps": "code"}},
        ctx, confirmado=True,
    ))
    assert r2["ok"] and len(lz.llamadas) == 1
