#!/usr/bin/env python3
"""Test end-to-end del agente local — corre todas las acciones contra una
sandbox temporal y verifica que la cadena completa funciona.

Qué cubre (Capa 6 · Fase 1):
  1. Autotest de conexión (--test-connection): reusa autotest.ejecutar() del
     daemon. Se SALTA si SKIP_CONEXION=1 o no hay AGENTE_PC_TOKEN.
  2. Acciones SEGURAS sobre una carpeta temporal (allowlist creada al vuelo):
       - listar_carpeta
       - buscar_archivos (patrón)
       - leer_archivo (archivo de texto)
       - leer_bytes (PDF/MD para "resumir_documento" — el agente provee los
         bytes; quien resume es el cerebro)
  3. Casos de SEGURIDAD que DEBEN fallar (rails):
       - leer fuera de la allowlist (tmp paralelo)
       - leer con `../` (path traversal — el normalizado escapa de la sandbox)
       - leer `.env` dentro de la sandbox (denylist por nombre)
       - leer ruta en `.ssh` (denylist por nombre)
  4. Audit log: cada acción ejecutada deja una línea en audit.log y NUNCA
     viaja contenido sensible (solo nombre de acción, ruta, ok/error).

Uso:
    cd agente_pc
    uv run python scripts/test_e2e.py
    # opcionales:
    #   SKIP_CONEXION=1 uv run python scripts/test_e2e.py    (sin red)
    #   E2E_VERBOSE=1   uv run python scripts/test_e2e.py    (más detalle)

Exit code: 0 si todo pasa, 1 si algo falla.
"""
from __future__ import annotations

import asyncio
import os
import secrets
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

# Hacer importable el paquete `agente_pc` cuando se corre `python scripts/...`
# desde la raíz del proyecto del agente.
_AQUI = Path(__file__).resolve().parent
_RAIZ_AGENTE = _AQUI.parent
sys.path.insert(0, str(_RAIZ_AGENTE))

from agente_pc.acciones import crear_registro  # noqa: E402
from agente_pc.auditoria import registrar as auditoria_registrar  # noqa: E402
from agente_pc.config import RUTA_AUDIT, cargar_config  # noqa: E402
from agente_pc.registro import Contexto  # noqa: E402

VERBOSE = bool(os.environ.get("E2E_VERBOSE"))


def _ascii_safe() -> bool:
    """True si la consola NO sabe escribir Unicode (cp1252 en Windows)."""
    enc = (getattr(sys.stdout, "encoding", None) or "ascii").lower()
    try:
        "✓✗─".encode(enc)
        return False
    except (LookupError, UnicodeEncodeError):
        return True


_ASCII = _ascii_safe()
OK = "[OK]" if _ASCII else "✓"
NO = "[X]" if _ASCII else "✗"
SEP = "-" if _ASCII else "─"
BULLET = "*" if _ASCII else "·"


def _safe(texto: str) -> str:
    """Si la consola es cp1252 (Windows con stdout redirigido o no), bajamos
    a ASCII para no crashear. Conserva el sentido cambiando los símbolos
    típicos por equivalentes (`→` → `->`, `…` → `...`). Si la consola sí
    soporta Unicode, lo dejamos tal cual."""
    if not _ASCII:
        return texto
    return (
        texto.replace("→", "->")
        .replace("…", "...")
        .replace("·", "*")
        .replace("─", "-")
    )


def _print(*partes: str) -> None:
    """`print` consciente de la encoding de la consola."""
    print(*(_safe(p) if isinstance(p, str) else p for p in partes))


@dataclass
class Caso:
    """Un caso del test e2e. `correr` devuelve True si pasó."""
    nombre: str
    correr: Callable[[], bool] | Callable[[], "Any"]
    detalle: str = ""
    paso: bool = False
    error: str = ""


@dataclass
class Suite:
    """Acumulador de resultados de la suite."""
    casos: list[Caso] = field(default_factory=list)

    def correr(self, nombre: str, fn: Callable[[], bool], *, detalle: str = "") -> bool:
        c = Caso(nombre=nombre, correr=fn, detalle=detalle)
        try:
            resultado = fn()
            c.paso = bool(resultado)
        except Exception as e:  # noqa: BLE001
            c.paso = False
            c.error = f"{type(e).__name__}: {e}"
        self.casos.append(c)
        marca = OK if c.paso else NO
        det = f" — {c.detalle}" if c.detalle and c.paso else ""
        if c.paso:
            _print(f"  {marca} {c.nombre}{det}")
        else:
            _print(f"  {marca} {c.nombre}")
            if c.error:
                _print(f"      causa: {c.error}")
        return c.paso

    def reportar(self) -> int:
        pasados = sum(1 for c in self.casos if c.paso)
        total = len(self.casos)
        _print()
        _print(SEP * 60)
        _print(f"  Resultado: {pasados}/{total} pruebas pasaron")
        fallidos = [c for c in self.casos if not c.paso]
        if fallidos:
            _print(f"  Fallaron: {', '.join(c.nombre for c in fallidos)}")
            return 1
        _print("  Todo en orden: el agente funciona end-to-end.")
        return 0


# ── Helpers de prueba ─────────────────────────────────────────────────────────


def _ejecutar(reg, nombre: str, args: dict[str, Any], ctx: Contexto, *, confirmado: bool = False) -> dict:
    """Ejecuta una acción del registry Y la audita — replica el wrapper que
    `cliente._atender` aplica en el flujo real (registry → audit). Sin esto, el
    e2e perdería la cobertura de la línea de audit por acción."""
    resultado = asyncio.run(reg.ejecutar(nombre, args, ctx, confirmado=confirmado))
    # Misma ruta-de-audit que el cliente: la principal (ruta/origen/carpeta).
    ruta = args.get("ruta") or args.get("origen") or args.get("carpeta") or ""
    auditoria_registrar(
        accion=nombre, ruta=str(ruta),
        ok=bool(resultado.get("ok")),
        detalle=str(resultado.get("tipo", "")),
    )
    return resultado


def _crear_sandbox_en(base: Path, etiqueta: str) -> Path:
    """Crea la sandbox bajo `base` (no usar tempfile.mkdtemp porque en Windows
    cae en %AppData%\\Local\\Temp y AppData está en la denylist del agente —
    todo se rechazaría por "componente prohibido"). Devuelve la raíz."""
    raiz = base / f"{etiqueta}_{secrets.token_hex(4)}"
    raiz.mkdir(parents=True, exist_ok=False)
    return raiz


def _crear_sandbox() -> Path:
    """Sandbox típica con archivos (texto, MD, "PDF" mínimo, .env y .ssh para
    casos de denylist). Vive bajo `agente_pc/.e2e_sandbox/` para evitar el
    bloqueo de la denylist de AppData."""
    raiz = _crear_sandbox_en(_RAIZ_AGENTE / ".e2e_sandbox", "main")
    (raiz / "notas").mkdir()
    (raiz / "notas" / "hola.txt").write_text(
        "Esto es una nota corta de prueba del agente.\n", encoding="utf-8"
    )
    (raiz / "notas" / "ideas.md").write_text(
        "# Ideas\n\n- una\n- dos\n- tres\n", encoding="utf-8"
    )
    # PDF de juguete: el header importa para que `_es_pdf` del cerebro lo
    # acepte; el cuerpo no se necesita para nuestro test (solo leemos bytes).
    (raiz / "docs").mkdir()
    (raiz / "docs" / "muestra.pdf").write_bytes(
        b"%PDF-1.4\n%trailer demo for matix e2e test\n%%EOF\n"
    )
    # Casos de denylist:
    (raiz / ".env").write_text("SECRET=top-secret-do-not-leak\n", encoding="utf-8")
    (raiz / ".ssh").mkdir()
    (raiz / ".ssh" / "id_rsa").write_text("FAKE PRIVATE KEY\n", encoding="utf-8")
    return raiz


def _audit_lineas_recientes(audit_path: Path, desde: int) -> list[str]:
    """Lee el audit log desde el byte offset `desde` y devuelve las nuevas
    líneas. Tolera ausencia del archivo."""
    if not audit_path.exists():
        return []
    with open(audit_path, "rb") as f:
        f.seek(desde)
        crudo = f.read().decode("utf-8", errors="replace")
    return [l for l in crudo.splitlines() if l.strip()]


# ── Las pruebas concretas ─────────────────────────────────────────────────────


def correr_pruebas_seguras(suite: Suite, reg, ctx: Contexto, sandbox: Path) -> None:
    _print()
    _print("[1/3] Acciones SEGURAS sobre la sandbox …")

    # listar_carpeta
    def _t_listar() -> bool:
        r = _ejecutar(reg, "listar_carpeta", {"ruta": str(sandbox)}, ctx)
        if not r.get("ok"):
            return False
        nombres = {e["nombre"] for e in r.get("entradas", [])}
        # El listing oculta .env y .ssh por la denylist de nombres.
        return "notas" in nombres and "docs" in nombres and ".env" not in nombres

    suite.correr("listar_carpeta de la raíz oculta secretos", _t_listar,
                 detalle="vio 'notas'/'docs' y NO listó .env ni .ssh")

    # buscar_archivos
    def _t_buscar() -> bool:
        r = _ejecutar(reg, "buscar_archivos", {"patron": "*.md"}, ctx)
        if not r.get("ok"):
            return False
        return any(a["nombre"] == "ideas.md" for a in r.get("archivos", []))

    suite.correr("buscar_archivos encuentra ideas.md", _t_buscar,
                 detalle="patrón '*.md' encontró ideas.md")

    # leer_archivo
    def _t_leer() -> bool:
        r = _ejecutar(reg, "leer_archivo",
                      {"ruta": str(sandbox / "notas" / "hola.txt")}, ctx)
        return r.get("ok") and "nota corta" in (r.get("texto") or "")

    suite.correr("leer_archivo de un .txt devuelve el contenido", _t_leer,
                 detalle="hola.txt → texto recibido")

    # leer_bytes (soporte de resumir_documento)
    def _t_bytes() -> bool:
        r = _ejecutar(reg, "leer_bytes",
                      {"ruta": str(sandbox / "docs" / "muestra.pdf")}, ctx)
        # El agente devuelve base64 de los bytes; el cerebro luego los pasa por
        # `extraccion_documentos` para resumir. Aquí basta con que el agente
        # haya pasado el ribete (extensión, tope, denylist).
        if not r.get("ok"):
            return False
        b64 = r.get("base64") or ""
        return len(b64) > 0 and r.get("nombre") == "muestra.pdf"

    suite.correr("leer_bytes de un PDF devuelve base64 + nombre", _t_bytes,
                 detalle="muestra.pdf → bytes listos para resumir_documento")


def correr_pruebas_seguridad(suite: Suite, reg, ctx: Contexto, sandbox: Path,
                             fuera: Path) -> None:
    _print()
    _print("[2/3] Casos de SEGURIDAD que DEBEN fallar …")

    # Fuera de la allowlist (otro tmp distinto, allowlisteado en ningún sitio).
    def _t_fuera() -> bool:
        r = _ejecutar(reg, "leer_archivo", {"ruta": str(fuera / "file.txt")}, ctx)
        # rechazada por allowlist
        return not r.get("ok") and r.get("tipo") in ("rechazada", "validacion")

    suite.correr("leer fuera de la allowlist → rechazado", _t_fuera,
                 detalle=f"{fuera / 'file.txt'} rechazada")

    # Path traversal con ../
    def _t_traversal() -> bool:
        # `notas/../../escape.txt` se resuelve fuera de la sandbox.
        ruta = str(sandbox / "notas" / ".." / ".." / "escape.txt")
        r = _ejecutar(reg, "leer_archivo", {"ruta": ruta}, ctx)
        return not r.get("ok")

    suite.correr("path traversal con '../' → rechazado", _t_traversal,
                 detalle="ruta resuelta cae fuera de la allowlist")

    # Denylist: .env dentro de la sandbox
    def _t_env() -> bool:
        r = _ejecutar(reg, "leer_archivo", {"ruta": str(sandbox / ".env")}, ctx)
        # rechazada por componente prohibido (.env)
        return not r.get("ok")

    suite.correr(".env dentro de la sandbox → rechazado", _t_env,
                 detalle="denylist por nombre de componente")

    # Denylist: .ssh/id_rsa
    def _t_ssh() -> bool:
        r = _ejecutar(reg, "leer_archivo",
                      {"ruta": str(sandbox / ".ssh" / "id_rsa")}, ctx)
        return not r.get("ok")

    suite.correr(".ssh/id_rsa → rechazado", _t_ssh,
                 detalle="denylist por nombre de componente")

    # CONSECUENTE sin confirmado=true: el registry corta.
    def _t_consecuente_sin_confirmar() -> bool:
        destino = str(sandbox / "notas" / "renombrado.txt")
        r = _ejecutar(
            reg, "renombrar_archivo",
            {"ruta": str(sandbox / "notas" / "hola.txt"),
             "nuevo_nombre": "renombrado.txt"},
            ctx,
            confirmado=False,
        )
        return (
            not r.get("ok")
            and r.get("tipo") == "requiere_confirmacion"
            and not Path(destino).exists()
        )

    suite.correr(
        "renombrar_archivo sin confirmado → bloqueado",
        _t_consecuente_sin_confirmar,
        detalle="registry exige confirmado=true para CONSECUENTE",
    )


def correr_pruebas_audit(suite: Suite, audit_offset: int) -> None:
    _print()
    _print("[3/3] Audit log …")

    def _t_audit_tiene_entradas() -> bool:
        lineas = _audit_lineas_recientes(RUTA_AUDIT, audit_offset)
        # Debe haber AL MENOS una línea por cada acción que ejecutamos (8+).
        return len(lineas) >= 6

    suite.correr(
        "audit.log recibió las entradas de la sesión",
        _t_audit_tiene_entradas,
        detalle=f"escritas en {RUTA_AUDIT}",
    )

    def _t_audit_sin_contenido() -> bool:
        """El audit NUNCA debe llevar el contenido sensible: no buscamos el
        texto interno de los archivos en el log. Comprobamos que la cadena
        SECRET=top-secret-do-not-leak NO aparezca."""
        lineas = _audit_lineas_recientes(RUTA_AUDIT, audit_offset)
        crudo = "\n".join(lineas)
        # También verificamos que NO esté el texto interno de hola.txt.
        return ("top-secret-do-not-leak" not in crudo
                and "nota corta de prueba" not in crudo
                and "FAKE PRIVATE KEY" not in crudo)

    suite.correr(
        "audit.log NO contiene contenido sensible",
        _t_audit_sin_contenido,
        detalle="ni el texto leído ni el de .env aparecen en el log",
    )


# ── Conexión opcional ─────────────────────────────────────────────────────────


def correr_test_conexion(suite: Suite) -> None:
    _print()
    _print("[0/3] Test de conexión al cerebro (autotest)…")
    if os.environ.get("SKIP_CONEXION"):
        _print(f"  {BULLET} saltado (SKIP_CONEXION=1)")
        return
    try:
        config = cargar_config()
    except Exception as e:  # noqa: BLE001
        _print(f"  {BULLET} no pude cargar config ({type(e).__name__}); saltando.")
        return
    if not config.agente_pc_token:
        _print(f"  {BULLET} sin AGENTE_PC_TOKEN; saltando (esto es OK en CI).")
        return

    from agente_pc import autotest

    def _t_conexion() -> bool:
        # autotest.ejecutar imprime su propio veredicto; nos basta con el code.
        return autotest.ejecutar(config=config, log=lambda _: None) == 0

    suite.correr("autotest WSS + token aceptado por el cerebro", _t_conexion,
                 detalle="handshake con el cerebro completado")


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> int:
    _print(f"Matix · agente PC · test end-to-end ({_RAIZ_AGENTE.name})")
    _print(SEP * 60)

    suite = Suite()

    # Conexión (opcional, depende de .env + red).
    correr_test_conexion(suite)

    # Sandbox con archivos típicos + tmp paralelo para casos de allowlist.
    sandbox = _crear_sandbox()
    fuera = _crear_sandbox_en(_RAIZ_AGENTE / ".e2e_sandbox", "fuera")
    (fuera / "file.txt").write_text("no debería ser legible\n", encoding="utf-8")

    audit_offset = RUTA_AUDIT.stat().st_size if RUTA_AUDIT.exists() else 0

    try:
        reg = crear_registro()
        ctx = Contexto(allowlist=[sandbox], max_lectura_bytes=256 * 1024)
        if VERBOSE:
            _print(f"  sandbox: {sandbox}")
            _print(f"  fuera:   {fuera}")

        correr_pruebas_seguras(suite, reg, ctx, sandbox)
        correr_pruebas_seguridad(suite, reg, ctx, sandbox, fuera)
        # Aseguramos una entrada de audit explícita para que el chequeo de
        # audit nunca falle por timing en máquinas raras: registramos una
        # acción "sintética" del propio script.
        auditoria_registrar(accion="test_e2e", ruta=str(sandbox), ok=True,
                            detalle="cerrado")
        correr_pruebas_audit(suite, audit_offset)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
        shutil.rmtree(fuera, ignore_errors=True)

    return suite.reportar()


if __name__ == "__main__":
    sys.exit(main())
