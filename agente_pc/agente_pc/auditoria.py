"""Audit log local del agente (agente_pc/audit.log).

Una línea por acción ejecutada: acción, ruta, timestamp (America/Lima) y
resultado ok/error. NUNCA el contenido de los archivos. El audit jamás debe
tumbar el agente: si falla el disco, se ignora.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from .config import RUTA_AUDIT

# America/Lima es UTC-5 fijo (Perú no usa horario de verano). Usamos un offset
# fijo en vez de ZoneInfo para no depender del paquete `tzdata`, que el Python
# embebido de la PC del usuario podría no traer (igual que el cerebro en
# `matix/tools.py::_hoy_lima`).
_LIMA = timezone(timedelta(hours=-5))


def registrar(
    accion: str,
    ruta: str,
    ok: bool,
    detalle: str = "",
    ruta_log: Path = RUTA_AUDIT,
) -> None:
    ts = datetime.now(_LIMA).isoformat(timespec="seconds")
    estado = "ok" if ok else "error"
    ruta_s = (ruta or "").replace("\n", " ").replace("\r", " ")
    det = (detalle or "").replace("\n", " ").replace("\r", " ")
    linea = f"{ts} | accion={accion} | ruta={ruta_s} | resultado={estado} | {det}\n"
    try:
        with open(ruta_log, "a", encoding="utf-8") as f:
            f.write(linea)
    except OSError:
        pass
