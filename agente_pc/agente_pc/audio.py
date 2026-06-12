"""Verificación HONESTA de reproducción de Spotify en esta PC.

Dos señales locales, sin tocar la pantalla:
  1. Peak de audio del proceso Spotify (pycaw / Core Audio): >0 ⇒ suena.
  2. Título de la ventana de Spotify: «Artista - Canción» cuando reproduce,
     «Spotify Premium/Free» cuando está en pausa.

Diseñado para degradar limpio: en Linux/CI (sin pycaw ni win32) las funciones
devuelven None/"" y el veredicto queda en None («no pude medir»), nunca en un
falso «sí suena». Los tests inyectan `muestreador` — no tocan audio real.
"""
from __future__ import annotations

import logging
import time
from typing import Any, Callable

log = logging.getLogger("matix.agente")

_UMBRAL_PEAK = 0.01
# Títulos de Spotify cuando NO reproduce (la app en reposo).
_TITULOS_REPOSO = {"spotify", "spotify premium", "spotify free"}


def peak_spotify() -> float | None:
    """Peak de audio (0..1) de las sesiones del proceso Spotify, o None si no
    se puede medir (sin pycaw, sin Windows, sin sesión de audio)."""
    try:
        from pycaw.pycaw import AudioUtilities, IAudioMeterInformation
    except Exception:  # noqa: BLE001 — entorno sin pycaw (Linux/CI)
        return None
    try:
        mejor: float | None = None
        for sesion in AudioUtilities.GetAllSessions():
            proc = sesion.Process
            if proc and "spotify" in proc.name().lower():
                try:
                    medidor = sesion._ctl.QueryInterface(IAudioMeterInformation)  # noqa: SLF001
                    valor = float(medidor.GetPeakValue())
                    mejor = valor if mejor is None else max(mejor, valor)
                except Exception:  # noqa: BLE001
                    continue
        return mejor
    except Exception:  # noqa: BLE001
        log.exception("peak_spotify falló")
        return None


def titulo_spotify() -> str:
    """Título de la ventana principal de Spotify («Artista - Canción» si está
    reproduciendo). "" si no hay ventana o no se puede leer."""
    try:
        import ctypes

        import psutil
    except Exception:  # noqa: BLE001
        return ""
    try:
        user32 = ctypes.windll.user32  # type: ignore[attr-defined]
    except Exception:  # noqa: BLE001 — no Windows
        return ""
    try:
        pids = {
            p.pid for p in psutil.process_iter(["name"])
            if "spotify" in ((p.info.get("name") or "").lower())
        }
        titulos: list[str] = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
        def _cb(hwnd, _):
            pid = ctypes.c_ulong()
            user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if pid.value in pids and user32.IsWindowVisible(hwnd):
                n = user32.GetWindowTextLengthW(hwnd)
                if n:
                    buf = ctypes.create_unicode_buffer(n + 1)
                    user32.GetWindowTextW(hwnd, buf, n + 1)
                    titulos.append(buf.value)
            return True

        user32.EnumWindows(_cb, 0)
        # La ventana principal es la que tiene título con contenido.
        return max(titulos, key=len) if titulos else ""
    except Exception:  # noqa: BLE001
        log.exception("titulo_spotify falló")
        return ""


def _muestra() -> dict[str, Any]:
    return {"peak": peak_spotify(), "titulo": titulo_spotify()}


def verificar_sonando(
    espera_s: float = 8.0,
    *,
    muestreador: Callable[[], dict[str, Any]] | None = None,
    dormir: Callable[[float], None] = time.sleep,
    reloj: Callable[[], float] = time.monotonic,
) -> dict[str, Any]:
    """Espera hasta `espera_s` a que Spotify SUENE. Devuelve:
      {"sonando": True|False|None, "titulo": str|None}
    sonando=None ⇒ no se pudo medir nada (sin pycaw ni ventana). El título de
    reproducción («Artista - Canción») es la señal secundaria si no hay peak.
    """
    tomar = muestreador or _muestra
    inicio = reloj()
    pudo_medir = False
    titulo_track: str | None = None
    while True:
        m = tomar() or {}
        peak = m.get("peak")
        titulo = (m.get("titulo") or "").strip()
        reproduce_por_titulo = bool(titulo) and titulo.lower() not in _TITULOS_REPOSO
        if titulo and reproduce_por_titulo:
            titulo_track = titulo
        if peak is not None:
            pudo_medir = True
            if peak > _UMBRAL_PEAK:
                return {"sonando": True, "titulo": titulo_track}
        elif titulo:
            pudo_medir = True
            # Sin peak medible: el título de track es la mejor señal disponible.
            if reproduce_por_titulo:
                return {"sonando": True, "titulo": titulo_track}
        if reloj() - inicio >= espera_s:
            return {"sonando": False if pudo_medir else None, "titulo": titulo_track}
        dormir(0.5)
