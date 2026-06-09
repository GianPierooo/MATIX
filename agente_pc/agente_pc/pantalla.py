"""Fase 6.3 — control AUTÓNOMO de la pantalla (la capacidad MÁS PELIGROSA).

El agente expone las "manos": capturar la pantalla y ejecutar UNA acción de
mouse/teclado por petición. El BUCLE (capturar → interpretar con visión →
decidir → actuar) vive en el CEREBRO (`app/matix/control_pantalla.py`), que es
el único que habla con el modelo de visión. Aquí solo están los primitivos y
sus rails LOCALES.

Rails locales (defensa en profundidad sobre los del cerebro):
  - **Master switch OFF por defecto** (`AGENTE_PC_CONTROL_PANTALLA`): si no lo
    activas en `.env`, capturar/actuar se RECHAZAN. La capacidad más peligrosa
    no se enciende sola.
  - **Sesión acotada**: el control vive dentro de una sesión (iniciar/terminar).
    Fuera de sesión no se actúa. La sesión tiene un TOPE de acciones
    (`AGENTE_PC_MAX_ACCIONES_PANTALLA`): si lo supera, aborta (anti-runaway).
  - **Kill switch del SO**: pyautogui FAILSAFE (mover el mouse a una esquina →
    aborta la acción al instante). Más el Ctrl+C/SIGTERM del daemon.
  - **Indicador visible**: mientras la sesión está activa, un banner rojo
    siempre-encima avisa que Matix controla la pantalla (best-effort, tkinter).
  - **Sin shell**: estos primitivos NO ejecutan comandos; solo mueven mouse y
    teclean. La denylist de apps de 6.2 sigue aplicando al resto.

Todo es INYECTABLE (capturador / controlador / indicador en el Contexto) para
poder testear sin tocar el mouse real ni la pantalla. Las implementaciones
reales hacen lazy-import de `pyautogui` (extra `control`) y degradan con un
mensaje accionable si falta.
"""
from __future__ import annotations

import base64
import io
from typing import Any

from .registro import AccionDef, Contexto, NivelRiesgo, Param

# Teclas sueltas PERMITIDAS (sin combos con modificadores: nada de ctrl+alt+del
# ni atajos de sistema desde aquí). Edición de texto y navegación básica.
_TECLAS_OK: frozenset[str] = frozenset(
    {
        "enter", "return", "tab", "esc", "escape", "space", "backspace", "delete",
        "up", "down", "left", "right", "home", "end", "pageup", "pagedown",
    }
)

# Tipos de acción atómica que el agente sabe ejecutar.
_TIPOS_ACCION: frozenset[str] = frozenset(
    {"click", "doble_click", "click_derecho", "escribir", "tecla", "scroll", "mover", "esperar"}
)

# Topes duros (anti-abuso aunque el cerebro pida algo raro).
_MAX_TEXTO = 2000          # chars por acción "escribir"
_MAX_SCROLL = 20           # "clicks" de rueda por acción
_MAX_ESPERA_MS = 3000      # una acción "esperar" nunca cuelga el canal


def _err(tipo: str, mensaje: str, **extra: Any) -> dict[str, Any]:
    return {"ok": False, "tipo": tipo, "mensaje": mensaje, **extra}


# ── Implementaciones REALES (lazy pyautogui) — inyectables ────────────────────


class _PyAutoGuiNoDisponible(RuntimeError):
    pass


def _cargar_pyautogui():
    try:
        import pyautogui  # type: ignore
    except Exception as e:  # noqa: BLE001
        raise _PyAutoGuiNoDisponible(
            "Falta pyautogui para el control de pantalla. Instálalo con: "
            "cd agente_pc && uv sync --extra control"
        ) from e
    # FAILSAFE: mover el mouse a una esquina aborta cualquier acción (kill switch
    # del SO). PAUSE pequeño entre acciones para que el SO procese (y para no
    # disparar a ciegas a máxima velocidad).
    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.08
    return pyautogui


def capturar_pantalla() -> dict[str, Any]:
    """Captura la pantalla → JPEG comprimido y reescalado (barato para la
    visión). Devuelve {ok, imagen(data URL), ancho, alto}. Real (pyautogui+PIL)."""
    try:
        pg = _cargar_pyautogui()
    except _PyAutoGuiNoDisponible as e:
        return _err("sin_pyautogui", str(e))
    try:
        img = pg.screenshot()  # PIL.Image
        ancho, alto = img.size
        # Reescala a ancho máx 1280 (la visión low-detail no necesita más) y
        # JPEG calidad 55 → payload chico = barato y rápido.
        max_w = 1280
        if ancho > max_w:
            nuevo_alto = int(alto * max_w / ancho)
            img = img.resize((max_w, nuevo_alto))
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="JPEG", quality=55)
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        return {
            "ok": True,
            "imagen": f"data:image/jpeg;base64,{b64}",
            "ancho": ancho,
            "alto": alto,
        }
    except Exception as e:  # noqa: BLE001
        return _err("error_captura", f"no pude capturar la pantalla ({type(e).__name__})")


def ejecutar_accion_real(accion: dict[str, Any]) -> dict[str, Any]:
    """Ejecuta UNA acción de mouse/teclado con pyautogui. El kill switch del SO
    (mouse a la esquina) la aborta. Real."""
    try:
        pg = _cargar_pyautogui()
    except _PyAutoGuiNoDisponible as e:
        return _err("sin_pyautogui", str(e))
    tipo = accion.get("tipo")
    try:
        if tipo in ("click", "doble_click", "click_derecho"):
            x, y = int(accion["x"]), int(accion["y"])
            if tipo == "doble_click":
                pg.doubleClick(x, y)
            elif tipo == "click_derecho":
                pg.click(x, y, button="right")
            else:
                pg.click(x, y)
        elif tipo == "mover":
            pg.moveTo(int(accion["x"]), int(accion["y"]))
        elif tipo == "escribir":
            pg.write(str(accion.get("texto", ""))[:_MAX_TEXTO], interval=0.01)
        elif tipo == "tecla":
            pg.press(str(accion.get("tecla", "")).lower())
        elif tipo == "scroll":
            pg.scroll(int(accion.get("cantidad", 0)))
        elif tipo == "esperar":
            import time
            time.sleep(min(_MAX_ESPERA_MS, int(accion.get("ms", 0))) / 1000.0)
        else:
            return _err("accion_invalida", f"tipo de acción desconocido: {tipo}")
        return {"ok": True}
    except Exception as e:  # noqa: BLE001
        # FailSafeException de pyautogui (mouse a la esquina) cae aquí → abort.
        nombre = type(e).__name__
        if "FailSafe" in nombre:
            return _err("abortado_killswitch", "kill switch: moviste el mouse a la esquina")
        return _err("error_accion", f"no pude ejecutar la acción ({nombre})")


class IndicadorTk:
    """Banner rojo siempre-encima mientras Matix controla la pantalla
    (best-effort: tkinter en un hilo daemon). Si tkinter no está o falla, se
    degrada a no-op — el log y el FAILSAFE son las garantías duras."""

    def __init__(self) -> None:
        self._hilo = None
        self._root = None

    def mostrar(self) -> None:
        try:
            import threading
            import tkinter as tk

            def _correr() -> None:
                try:
                    root = tk.Tk()
                    self._root = root
                    root.overrideredirect(True)  # sin bordes
                    root.attributes("-topmost", True)
                    try:
                        root.attributes("-alpha", 0.92)
                    except Exception:  # noqa: BLE001
                        pass
                    ancho = root.winfo_screenwidth()
                    root.geometry(f"{ancho}x34+0+0")
                    root.configure(bg="#B00020")
                    tk.Label(
                        root,
                        text="●  MATIX está controlando tu pantalla  —  "
                        "mueve el mouse a una esquina para abortar",
                        bg="#B00020", fg="white",
                        font=("Segoe UI", 11, "bold"),
                    ).pack(fill="both", expand=True)
                    root.mainloop()
                except Exception:  # noqa: BLE001
                    self._root = None

            self._hilo = threading.Thread(target=_correr, daemon=True)
            self._hilo.start()
        except Exception:  # noqa: BLE001
            self._root = None  # degrada a no-op

    def ocultar(self) -> None:
        root = self._root
        if root is not None:
            try:
                root.after(0, root.destroy)
            except Exception:  # noqa: BLE001
                pass
        self._root = None


# ── Validación de la acción (PURA) ────────────────────────────────────────────


def validar_accion(accion: Any) -> tuple[bool, str]:
    """Valida la forma de una acción atómica. PURA. Falla cerrado."""
    if not isinstance(accion, dict):
        return False, "la acción debe ser un objeto"
    tipo = accion.get("tipo")
    if tipo not in _TIPOS_ACCION:
        return False, f"tipo de acción no permitido: {tipo!r}"
    if tipo in ("click", "doble_click", "click_derecho", "mover"):
        for c in ("x", "y"):
            v = accion.get(c)
            if not isinstance(v, int) or v < 0 or v > 20000:
                return False, f"coordenada «{c}» inválida"
    if tipo == "escribir":
        if not isinstance(accion.get("texto"), str):
            return False, "«texto» debe ser string"
    if tipo == "tecla":
        if str(accion.get("tecla", "")).lower() not in _TECLAS_OK:
            return False, f"tecla no permitida: {accion.get('tecla')!r}"
    if tipo == "scroll":
        v = accion.get("cantidad")
        if not isinstance(v, int) or abs(v) > _MAX_SCROLL:
            return False, "«cantidad» de scroll inválida"
    if tipo == "esperar":
        v = accion.get("ms")
        if not isinstance(v, int) or v < 0:
            return False, "«ms» inválido"
    return True, ""


def resumen_accion(accion: dict[str, Any]) -> str:
    """Descripción corta de la acción para el audit (sin contenido sensible: el
    texto tecleado NO se audita textual — solo su longitud)."""
    tipo = accion.get("tipo")
    if tipo in ("click", "doble_click", "click_derecho", "mover"):
        return f"{tipo}@{accion.get('x')},{accion.get('y')}"
    if tipo == "escribir":
        return f"escribir[{len(str(accion.get('texto', '')))} chars]"
    if tipo == "tecla":
        return f"tecla:{accion.get('tecla')}"
    if tipo == "scroll":
        return f"scroll:{accion.get('cantidad')}"
    return str(tipo)


# ── Handlers ──────────────────────────────────────────────────────────────────


def _control_activable(ctx: Contexto) -> str | None:
    """Motivo si el control de pantalla NO se puede usar, o None. El master
    switch OFF por defecto es el rail más fuerte."""
    if not getattr(ctx, "control_pantalla", False):
        return (
            "el control de pantalla está DESACTIVADO. Es la capacidad más "
            "peligrosa: actívala a conciencia con AGENTE_PC_CONTROL_PANTALLA=1 "
            "en agente_pc/.env."
        )
    return None


def _pantalla_control_iniciar(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    motivo = _control_activable(ctx)
    if motivo:
        return _err("control_desactivado", motivo)
    sesion = ctx.pantalla_sesion
    sesion["activa"] = True
    sesion["acciones"] = 0
    ind = ctx.indicador
    if ind is None:
        ind = ctx.indicador = IndicadorTk()
    try:
        ind.mostrar()
    except Exception:  # noqa: BLE001
        pass  # indicador best-effort
    return {"ok": True, "tipo": "control_iniciado"}


def _pantalla_control_terminar(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    sesion = ctx.pantalla_sesion
    sesion["activa"] = False
    ind = ctx.indicador
    if ind is not None:
        try:
            ind.ocultar()
        except Exception:  # noqa: BLE001
            pass
    return {"ok": True, "tipo": "control_terminado", "acciones": sesion.get("acciones", 0)}


def _pantalla_capturar(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    motivo = _control_activable(ctx)
    if motivo:
        return _err("control_desactivado", motivo)
    if not ctx.pantalla_sesion.get("activa"):
        return _err("sin_sesion", "no hay una sesión de control activa")
    cap = ctx.capturador or capturar_pantalla
    return cap()


def _pantalla_accion(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    motivo = _control_activable(ctx)
    if motivo:
        return _err("control_desactivado", motivo)
    sesion = ctx.pantalla_sesion
    if not sesion.get("activa"):
        return _err("sin_sesion", "no hay una sesión de control activa; no actúo")
    # Tope de acciones por sesión (anti-runaway: aunque el cerebro pida de más).
    if sesion.get("acciones", 0) >= ctx.max_acciones_pantalla:
        sesion["activa"] = False
        return _err(
            "tope_acciones",
            f"alcancé el tope de {ctx.max_acciones_pantalla} acciones de la "
            "sesión; aborto por seguridad.",
        )
    accion = args.get("accion") or {}
    ok, val = validar_accion(accion)
    if not ok:
        return _err("accion_invalida", val)
    ctrl = ctx.controlador or ejecutar_accion_real
    res = ctrl(accion)
    # Cuenta TODA acción intentada (aunque falle) contra el tope.
    sesion["acciones"] = sesion.get("acciones", 0) + 1
    if not res.get("ok"):
        # Kill switch o error → cerramos la sesión (no seguimos a ciegas).
        if res.get("tipo") == "abortado_killswitch":
            sesion["activa"] = False
        return res
    return {"ok": True, "tipo": "accion_hecha", "resumen": resumen_accion(accion)}


def _pantalla_accion_confirmada(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    """Ejecuta UNA acción IRREVERSIBLE que el usuario YA confirmó en el gate
    (el bucle del cerebro se detuvo en ella). One-shot: no requiere sesión
    activa, pero SÍ el master switch (no se ejecuta si el control está OFF).
    Muestra el indicador brevemente y audita. Solo llega aquí vía el canal de
    ejecución confirmada (confirmado=true)."""
    motivo = _control_activable(ctx)
    if motivo:
        return _err("control_desactivado", motivo)
    accion = args.get("accion") or {}
    ok, val = validar_accion(accion)
    if not ok:
        return _err("accion_invalida", val)
    ind = ctx.indicador
    if ind is not None:
        try:
            ind.mostrar()
        except Exception:  # noqa: BLE001
            pass
    ctrl = ctx.controlador or ejecutar_accion_real
    res = ctrl(accion)
    if ind is not None:
        try:
            ind.ocultar()
        except Exception:  # noqa: BLE001
            pass
    if not res.get("ok"):
        return res
    return {"ok": True, "tipo": "accion_confirmada_hecha", "resumen": resumen_accion(accion)}


DEFS_PANTALLA: list[AccionDef] = [
    AccionDef(
        "pantalla_control_iniciar",
        "Inicia una sesión de control de pantalla (muestra el indicador). "
        "Requiere el master switch AGENTE_PC_CONTROL_PANTALLA=1.",
        (),
        NivelRiesgo.CONSECUENTE,
        _pantalla_control_iniciar,
    ),
    AccionDef(
        "pantalla_control_terminar",
        "Termina la sesión de control de pantalla (oculta el indicador).",
        (),
        NivelRiesgo.SEGURA,  # terminar/limpiar nunca es peligroso
        _pantalla_control_terminar,
    ),
    AccionDef(
        "pantalla_capturar",
        "Captura la pantalla (JPEG comprimido) para que la visión del cerebro "
        "la interprete. Solo dentro de una sesión de control activa.",
        (),
        NivelRiesgo.CONSECUENTE,
        _pantalla_capturar,
    ),
    AccionDef(
        "pantalla_accion",
        "Ejecuta UNA acción de mouse/teclado (click/escribir/tecla/scroll/"
        "mover). Solo en sesión activa, con tope de acciones y kill switch.",
        (Param("accion", dict, requerido=True),),
        NivelRiesgo.CONSECUENTE,
        _pantalla_accion,
    ),
    AccionDef(
        "pantalla_accion_confirmada",
        "Ejecuta UNA acción IRREVERSIBLE que el usuario confirmó en el gate. "
        "One-shot (sin sesión), requiere el master switch.",
        (Param("accion", dict, requerido=True),),
        NivelRiesgo.CONSECUENTE,
        _pantalla_accion_confirmada,
    ),
]
