"""Fase 6.2 — abrir/cerrar apps: allowlist dura, denylist que gana, gate
consecuente, lanzador sin shell. Security-critical → cobertura amplia.

El lanzador/terminador se INYECTAN (fakes que registran), así NO se abren
procesos reales en los tests. Hay UN test del lanzador real (python -c pass)
para probar que el camino subprocess shell=False funciona de verdad.
"""
from __future__ import annotations

import asyncio
import sys

from agente_pc import apps
from agente_pc.acciones import crear_registro
from agente_pc.registro import Contexto, NivelRiesgo


class _LanzadorFake:
    """Registra (exe, args) en vez de spawnear. Devuelve un pid creciente."""

    def __init__(self, ok: bool = True) -> None:
        self.ok = ok
        self.llamadas: list[tuple[str, list]] = []
        self._pid = 1000

    def __call__(self, exe: str, args: list) -> dict:
        self.llamadas.append((exe, list(args)))
        if not self.ok:
            return {"ok": False, "error": "FakeError"}
        self._pid += 1
        return {"ok": True, "pid": self._pid}


class _TerminadorFake:
    def __init__(self) -> None:
        self.terminados: list[int] = []

    def __call__(self, pid: int) -> bool:
        self.terminados.append(pid)
        return True


def _ctx(apps_map: dict[str, str], lanzador=None, terminador=None) -> Contexto:
    return Contexto(
        allowlist=[],
        apps=apps_map,
        lanzador=lanzador,
        terminador=terminador,
    )


# Rutas sintéticas (no necesitan existir: el handler valida allowlist+denylist
# sobre el string, no abre el archivo — el lanzador es fake).
_CODE = r"C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe"
_CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
_CMD = r"C:\Windows\System32\cmd.exe"


# ── abrir_app ────────────────────────────────────────────────────────────────


def test_abrir_app_allowlisted_lanza_el_exe_correcto():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    r = apps._abrir_app({"nombre": "code"}, ctx)
    assert r["ok"] and r["tipo"] == "app_abierta" and r["app"] == "code"
    assert lz.llamadas == [(_CODE, [])]  # lanzó el exe, sin args, una vez
    # El pid quedó rastreado para cerrar_app.
    assert ctx.procesos["code"] == [r["pid"]]


def test_abrir_app_case_insensitive():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    assert apps._abrir_app({"nombre": "CODE"}, ctx)["ok"]
    assert len(lz.llamadas) == 1


def test_abrir_app_fuera_de_allowlist_rechazada_sin_lanzar():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    r = apps._abrir_app({"nombre": "inkscape"}, ctx)
    assert not r["ok"] and r["tipo"] == "no_permitida"
    assert lz.llamadas == []  # NO se lanzó nada


def test_abrir_app_denylist_gana_aunque_este_en_allowlist():
    # Una allowlist mal configurada que incluye cmd: la denylist del handler
    # (defensa en profundidad) la rechaza igual.
    lz = _LanzadorFake()
    ctx = _ctx({"shell": _CMD}, lanzador=lz)
    r = apps._abrir_app({"nombre": "shell"}, ctx)
    assert not r["ok"] and r["tipo"] == "denylist"
    assert lz.llamadas == []


def test_abrir_app_nombre_con_separador_o_metachar_rechazado():
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    for malo in [r"C:\evil.exe", "rm -rf /", "code;calc", "../python", "a&b"]:
        r = apps._abrir_app({"nombre": malo}, ctx)
        assert not r["ok"] and r["tipo"] == "nombre_invalido", f"no rechazó: {malo!r}"
    assert lz.llamadas == []


def test_abrir_app_sin_nombre():
    r = apps._abrir_app({}, _ctx({"code": _CODE}))
    assert not r["ok"] and r["tipo"] == "validacion"


def test_abrir_app_lanzador_falla():
    lz = _LanzadorFake(ok=False)
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    r = apps._abrir_app({"nombre": "code"}, ctx)
    assert not r["ok"] and r["tipo"] == "error_lanzar"
    assert ctx.procesos.get("code") in (None, [])  # no rastrea si falló


# ── cerrar_app ───────────────────────────────────────────────────────────────


def test_cerrar_app_termina_los_pids_de_la_sesion():
    lz = _LanzadorFake()
    tm = _TerminadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz, terminador=tm)
    apps._abrir_app({"nombre": "code"}, ctx)
    apps._abrir_app({"nombre": "code"}, ctx)  # dos instancias
    pids = list(ctx.procesos["code"])
    r = apps._cerrar_app({"nombre": "code"}, ctx)
    assert r["ok"] and r["tipo"] == "app_cerrada" and r["cerrados"] == 2
    assert sorted(tm.terminados) == sorted(pids)
    assert ctx.procesos["code"] == []  # limpiado


def test_cerrar_app_fuera_de_allowlist_rechazada():
    r = apps._cerrar_app({"nombre": "inkscape"}, _ctx({"code": _CODE}))
    assert not r["ok"] and r["tipo"] == "no_permitida"


def test_cerrar_app_sin_nada_abierto():
    r = apps._cerrar_app({"nombre": "code"}, _ctx({"code": _CODE}))
    assert r["ok"] and r["tipo"] == "nada_que_cerrar"


# ── Gate consecuente (vía el Registro real) ──────────────────────────────────


def test_abrir_app_es_consecuente_y_exige_confirmado():
    reg = crear_registro()
    # Confirmamos el nivel declarado.
    assert reg.get("abrir_app").nivel is NivelRiesgo.CONSECUENTE
    assert reg.get("cerrar_app").nivel is NivelRiesgo.CONSECUENTE
    lz = _LanzadorFake()
    ctx = _ctx({"code": _CODE}, lanzador=lz)
    # Sin confirmado: el registry corta ANTES de ejecutar (no lanza nada).
    r = asyncio.run(reg.ejecutar("abrir_app", {"nombre": "code"}, ctx, confirmado=False))
    assert not r["ok"] and r["tipo"] == "requiere_confirmacion"
    assert lz.llamadas == []
    # Con confirmado: ejecuta.
    r2 = asyncio.run(reg.ejecutar("abrir_app", {"nombre": "code"}, ctx, confirmado=True))
    assert r2["ok"] and len(lz.llamadas) == 1


def test_no_existe_accion_de_shell_arbitrario():
    """Garantía estructural: el registry NO expone ninguna acción que ejecute
    un comando crudo. Solo abrir_app (allowlist) y ejecutar_tarea (registro)."""
    reg = crear_registro()
    for prohibida in ("ejecutar_comando", "shell", "run", "exec", "system", "cmd"):
        assert reg.get(prohibida) is None


# ── Resolución de la allowlist (impuro: FS) ──────────────────────────────────


def test_resolver_apps_omite_inexistente_y_denylisted(tmp_path):
    buena = tmp_path / "miapp.exe"
    buena.write_bytes(b"MZ")  # un archivo cualquiera; resolver solo verifica isfile
    specs = {
        "buena": str(buena),
        "fantasma": str(tmp_path / "no_existe.exe"),
        "shell": _CMD,  # denylisted por basename
    }
    resueltas, avisos = apps.resolver_apps(specs)
    assert "buena" in resueltas
    assert "fantasma" not in resueltas  # no existe → omitida
    assert "shell" not in resueltas  # denylist gana → omitida
    # Hay un aviso por cada omisión.
    assert any("fantasma" in a for a in avisos)
    assert any("shell" in a for a in avisos)


def test_lanzador_real_sin_shell():
    """UN test del lanzador REAL: spawnea el python actual con `-c pass`
    (sale solo). Prueba que el camino subprocess shell=False funciona."""
    r = apps.lanzar_proceso(sys.executable, ["-c", "pass"])
    assert r["ok"] and isinstance(r["pid"], int)
    # Limpieza best-effort (probablemente ya terminó).
    apps.terminar_proceso(r["pid"])
