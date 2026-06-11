"""Fase 6.3 — bucle de CONTROL DE PANTALLA (la capacidad más peligrosa).

El bucle vive en el CEREBRO (es quien habla con el modelo de visión); el agente
de la PC solo ejecuta los primitivos (capturar / una acción). El bucle:

    capturar → interpretar (visión) → RAILS → actuar → repetir

RAILS (en orden, el primero que aplica gana):
  1. PANTALLA PROHIBIDA (login/banca/pago/contraseñas/datos sensibles) → ABORTA.
  2. OBJETIVO CUMPLIDO → termina OK.
  3. ACCIÓN IRREVERSIBLE (borrar/comprar/enviar dinero/mensaje a terceros/
     cambio de sistema) → PARA y devuelve la acción para el GATE (confirmación).
  4. Sin acción válida (el piloto se perdió) → ABORTA (no clickea a ciegas).
  5. Acción segura → la ejecuta y sigue.
Acotado por `max_pasos`; si el agente reporta kill switch o error, ABORTA.

Es una función PURA respecto a la infraestructura: recibe callables inyectados
(`capturar`, `interpretar`, `ejecutar`, `auditar`), así se testea sin canal, sin
LLM y sin tocar el mouse. `tools.py` cablea el canal + la visión reales.
"""
from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from typing import Any

# Tope de pasos del bucle: cota dura anti-runaway. Cada paso = 1 captura + 1
# visión + (a lo más) 1 acción. Generoso para una tarea simple, finito siempre.
MAX_PASOS = 12

# Presupuesto de TIEMPO total (s) del bucle. Cota blanda para que el control
# SIEMPRE devuelva un resultado dentro del timeout de la petición del chat —
# nunca silencio. Si se agota, paramos con "tope" y un mensaje claro ("avancé N,
# ¿sigo?"). `tools.py` lo cablea por debajo del timeout HTTP del chat.
PRESUPUESTO_S = 70.0

Capturar = Callable[[], Awaitable[dict[str, Any]]]
Interpretar = Callable[..., Awaitable[dict[str, Any]]]
Ejecutar = Callable[[dict[str, Any]], Awaitable[dict[str, Any]]]
Auditar = Callable[[str, bool, str], None]


def _resultado(estado: str, **extra: Any) -> dict[str, Any]:
    return {"estado": estado, **extra}


async def bucle_control(
    objetivo: str,
    *,
    capturar: Capturar,
    interpretar: Interpretar,
    ejecutar: Ejecutar,
    auditar: Auditar | None = None,
    max_pasos: int = MAX_PASOS,
    presupuesto_s: float | None = PRESUPUESTO_S,
    reloj: Callable[[], float] = time.monotonic,
    log: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    """Corre el bucle de control. Devuelve un dict con `estado`:
      - "completado": el objetivo se cumplió (incluye `pasos`).
      - "abortado": rail de seguridad o error (incluye `motivo`).
      - "gate": acción irreversible que requiere confirmación (incluye `accion`,
        `descripcion`); el bucle se DETIENE y la app pide confirmar esa acción.
      - "tope": se alcanzó `max_pasos` sin terminar (incluye `pasos`).
    Siempre acotado; nunca clickea a ciegas."""
    _log = log or (lambda _m: None)
    _audit = auditar or (lambda _a, _ok, _d: None)
    historial: list[str] = []
    inicio = reloj()

    for paso in range(1, max_pasos + 1):
        # Cota de TIEMPO: si se agotó el presupuesto, paramos limpio con un
        # mensaje (no silencio) en vez de seguir y reventar el timeout del chat.
        if presupuesto_s is not None and reloj() - inicio >= presupuesto_s:
            _log(f"control: presupuesto de {presupuesto_s:.0f}s agotado → paro")
            return _resultado(
                "tope", pasos=paso - 1, historial=list(historial),
                motivo="se acabó el tiempo del turno",
            )
        _log(f"control: paso {paso}/{max_pasos} — capturando pantalla")
        cap = await capturar()
        if not cap.get("ok"):
            _log(f"control: captura falló ({cap.get('tipo')}) → abort")
            return _resultado(
                "abortado",
                motivo=cap.get("mensaje") or "no pude capturar la pantalla",
                pasos=paso - 1,
            )

        veredicto = await interpretar(
            cap.get("imagen", ""),
            objetivo,
            ancho=cap.get("ancho"),
            alto=cap.get("alto"),
            historial=historial,
        )

        # RAIL 1 — pantalla prohibida (o falla cerrado de la visión).
        if veredicto.get("prohibida"):
            motivo = veredicto.get("motivo") or "pantalla sensible"
            _log(f"control: PANTALLA PROHIBIDA → abort ({motivo})")
            _audit(f"abort_prohibida:{_corto(motivo)}", False, "rail_prohibida")
            return _resultado("abortado", motivo=f"pantalla prohibida: {motivo}", pasos=paso - 1)

        # RAIL 2 — objetivo cumplido.
        if veredicto.get("terminado"):
            _log("control: objetivo cumplido → fin")
            return _resultado(
                "completado", pasos=paso - 1,
                descripcion=veredicto.get("motivo") or veredicto.get("descripcion") or "",
            )

        accion = veredicto.get("accion")

        # RAIL 4 — sin acción válida: el piloto se perdió. No clickeamos a ciegas.
        if not isinstance(accion, dict) or not accion.get("tipo"):
            _log("control: sin acción válida → abort (perdido)")
            return _resultado(
                "abortado",
                motivo=veredicto.get("motivo") or "el piloto no supo qué hacer",
                pasos=paso - 1,
            )

        descripcion = veredicto.get("descripcion") or accion.get("tipo")

        # RAIL 3 — acción irreversible: PARA y manda al gate (confirmación).
        if veredicto.get("irreversible"):
            _log(f"control: acción IRREVERSIBLE → gate ({descripcion})")
            _audit("gate_irreversible", True, _corto(descripcion))
            return _resultado(
                "gate", accion=accion, descripcion=descripcion, pasos=paso - 1,
                motivo=veredicto.get("motivo") or "acción irreversible: pido confirmación",
            )

        # RAIL 5 — acción segura: ejecutar.
        _log(f"control: ejecutando {accion.get('tipo')} — {_corto(descripcion)}")
        res = await ejecutar(accion)
        ok = bool(res.get("ok"))
        _audit(res.get("resumen") or accion.get("tipo", "accion"), ok, res.get("tipo", ""))
        if not ok:
            tipo = res.get("tipo")
            # Kill switch del usuario (mouse a la esquina) o cualquier error →
            # abortamos: no seguimos a ciegas.
            etiqueta = "kill switch" if tipo == "abortado_killswitch" else (res.get("mensaje") or tipo)
            _log(f"control: acción falló ({tipo}) → abort")
            return _resultado("abortado", motivo=str(etiqueta), pasos=paso)
        historial.append(_corto(descripcion))

    _log(f"control: alcancé el tope de {max_pasos} pasos → paro")
    return _resultado("tope", pasos=max_pasos, historial=list(historial))


def _corto(texto: Any, n: int = 80) -> str:
    s = str(texto or "").replace("\n", " ").strip()
    return s[:n]
