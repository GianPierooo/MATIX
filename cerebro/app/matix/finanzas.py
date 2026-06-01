"""Clasificación de movimientos por SEÑAL (gasto vs ingreso).

Al leer una captura de Yape/banco/recibo, cada línea trae pistas de si es un
gasto o un ingreso: el signo (−/+), el color (rojo = sale plata), y la palabra
clave («Pagaste», «Te yapearon», «Abono»…). El modelo de visión lee la imagen
y nos pasa, por cada movimiento, la `señal` que vio; esta función la traduce a
gasto/ingreso de forma DETERMINÍSTICA, para no depender solo del criterio del
modelo y evitar el error de anotar un ingreso como gasto.

`inferir_tipo` devuelve "gasto", "ingreso" o None (si la señal es ambigua, se
respeta el `tipo` que ya trae el movimiento).
"""
from __future__ import annotations

import re
import unicodedata

# Palabras que indican que SALE plata (gasto).
_GASTO = (
    "pagaste", "pago", "pagado", "enviaste", "envio", "enviado", "compra",
    "compraste", "retiro", "retiraste", "debito", "cargo", "cobro a", "gaste",
    "gasto", "transferencia enviada", "te cobraron", "consumo", "egreso",
)
# Palabras que indican que ENTRA plata (ingreso).
_INGRESO = (
    "recibiste", "recibido", "abono", "abonaste", "deposito", "depositaste",
    "te yapearon", "te plinearon", "ingreso", "transferencia recibida",
    "reembolso", "devolucion", "cobro de", "pago recibido", "sueldo", "salario",
)


def _norm(texto: str) -> str:
    s = (texto or "").lower().strip()
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def inferir_tipo(senal: str | None) -> str | None:
    """Traduce la señal observada a 'gasto' / 'ingreso', o None si es ambigua.

    Prioridad: el SIGNO manda (−/monto negativo = gasto; + = ingreso). Si no
    hay signo claro, se busca por palabra clave."""
    if not senal:
        return None
    s = _norm(senal)

    # 1) Signo explícito al inicio (lo más fiable en apps tipo Yape).
    señal_sin_espacios = s.lstrip()
    if señal_sin_espacios.startswith(("-", "−", "–", "(")):  # paréntesis = negativo contable
        return "gasto"
    if señal_sin_espacios.startswith("+"):
        return "ingreso"
    # Monto negativo en cualquier parte (ej. "s/ -30", "-30.00").
    if re.search(r"[-−–]\s*s?/?\s*\d", s):
        return "gasto"

    # 2) Color (a veces el modelo lo describe).
    if "rojo" in s:
        return "gasto"
    if "verde" in s:
        return "ingreso"

    # 3) Palabra clave.
    if any(p in s for p in _GASTO):
        return "gasto"
    if any(p in s for p in _INGRESO):
        return "ingreso"

    return None
