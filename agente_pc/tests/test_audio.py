"""Verificación de sonido de Spotify (audio.py) — lógica pura con muestreador
inyectado. NO toca pycaw ni ventanas reales (en CI Linux ni existen)."""
from __future__ import annotations

from agente_pc import audio


def _reloj_falso(pasos: list[float]):
    estado = {"i": 0}

    def reloj() -> float:
        v = pasos[min(estado["i"], len(pasos) - 1)]
        return v

    def dormir(_s: float) -> None:
        estado["i"] += 1

    return reloj, dormir


def _verificar(muestras: list[dict], espera_s: float = 3.0):
    """Corre verificar_sonando con una secuencia fija de muestras."""
    idx = {"i": 0}

    def muestreador() -> dict:
        m = muestras[min(idx["i"], len(muestras) - 1)]
        idx["i"] += 1
        return m

    # El reloj avanza 1s por muestra: espera_s acota cuántas muestras se toman.
    tiempos = [float(i) for i in range(len(muestras) + 5)]
    reloj, dormir = _reloj_falso(tiempos)

    # dormir avanza el índice del reloj; el muestreador avanza solo.
    def dormir_(s: float) -> None:
        dormir(s)

    return audio.verificar_sonando(
        espera_s, muestreador=muestreador, dormir=dormir_, reloj=reloj
    )


def test_suena_por_peak():
    r = _verificar([
        {"peak": 0.0, "titulo": "Spotify Premium"},
        {"peak": 0.4, "titulo": "MJ - Billie Jean"},
    ])
    assert r["sonando"] is True
    assert r["titulo"] == "MJ - Billie Jean"


def test_no_suena_es_false_honesto():
    r = _verificar([{"peak": 0.0, "titulo": "Spotify Premium"}] * 6, espera_s=3.0)
    assert r["sonando"] is False  # midió y NO suena: jamás un falso éxito


def test_sin_medicion_es_none():
    # Sin pycaw y sin ventana (Linux/CI): no se afirma nada.
    r = _verificar([{"peak": None, "titulo": ""}] * 4, espera_s=2.0)
    assert r["sonando"] is None


def test_titulo_de_track_es_senal_si_no_hay_peak():
    # Sin peak medible, el título «Artista - Canción» (≠ reposo) cuenta.
    r = _verificar([{"peak": None, "titulo": "Artista - Cancion"}])
    assert r["sonando"] is True and r["titulo"] == "Artista - Cancion"


def test_titulo_en_reposo_no_cuenta_como_sonando():
    r = _verificar([{"peak": None, "titulo": "Spotify Free"}] * 4, espera_s=2.0)
    assert r["sonando"] is False  # hubo ventana (se pudo medir) pero en reposo


def test_funciones_reales_degradan_sin_reventar():
    # En cualquier entorno: nunca lanzan; tipos correctos.
    p = audio.peak_spotify()
    assert p is None or isinstance(p, float)
    t = audio.titulo_spotify()
    assert isinstance(t, str)
