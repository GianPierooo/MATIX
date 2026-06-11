"""Fase 6.3 — el BUCLE de control de pantalla (rails). PURO: capturar /
interpretar / ejecutar se inyectan, así probamos la lógica sin canal, sin LLM y
sin tocar el mouse.

Cubre los cinco casos clave: tarea autónoma multi-paso (éxito), pantalla
prohibida → abort, anti-inyección (la única fuente de acción es el veredicto de
visión, NO el texto en pantalla), acción irreversible → gate, y kill switch
corta el bucle. Más: tope de pasos, piloto perdido → abort, audit por acción.
"""
from __future__ import annotations

from app.matix import control_pantalla as cp


def _cap_ok():
    async def _c():
        return {"ok": True, "imagen": "data:image/jpeg;base64,Zg==", "ancho": 1280, "alto": 720}
    return _c


def _interpret_secuencia(veredictos):
    """Devuelve un `interpretar` que entrega los veredictos en orden."""
    estado = {"i": 0}

    async def _interpretar(imagen, objetivo, **kw):
        i = estado["i"]
        estado["i"] = min(i + 1, len(veredictos) - 1)
        return veredictos[i]
    return _interpretar


def _ejecutor(resultado=None):
    acciones = []

    async def _ejecutar(accion):
        acciones.append(accion)
        return resultado or {"ok": True}
    _ejecutar.acciones = acciones  # type: ignore[attr-defined]
    return _ejecutar


def _correr(**kw):
    import asyncio
    return asyncio.run(cp.bucle_control("haz la tarea", **kw))


# ── 1) Tarea autónoma multi-paso → éxito ─────────────────────────────────────


def test_multipaso_exito():
    veredictos = [
        {"prohibida": False, "terminado": False, "irreversible": False,
         "accion": {"tipo": "click", "x": 10, "y": 10}, "descripcion": "abrir menú"},
        {"prohibida": False, "terminado": False, "irreversible": False,
         "accion": {"tipo": "escribir", "texto": "hola"}, "descripcion": "escribir"},
        {"prohibida": False, "terminado": True, "irreversible": False,
         "accion": None, "motivo": "listo"},
    ]
    ejec = _ejecutor()
    auditadas = []
    r = _correr(
        capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos),
        ejecutar=ejec, auditar=lambda a, ok, d: auditadas.append((a, ok)),
    )
    assert r["estado"] == "completado"
    assert len(ejec.acciones) == 2  # dos acciones seguras ejecutadas
    assert len(auditadas) == 2  # cada acción auditada


# ── 2) Pantalla prohibida → abort (sin actuar) ───────────────────────────────


def test_pantalla_prohibida_aborta():
    veredictos = [
        {"prohibida": True, "terminado": False, "irreversible": False,
         "accion": None, "motivo": "parece una pantalla de banca"},
    ]
    ejec = _ejecutor()
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos), ejecutar=ejec)
    assert r["estado"] == "abortado"
    assert "prohibida" in r["motivo"]
    assert ejec.acciones == []  # NO se actuó


# ── 3) Anti-inyección: la única fuente de acción es el veredicto ─────────────


def test_anti_inyeccion_la_pantalla_no_dirige():
    # La "pantalla" (vía interpretar) trae un veredicto que IGNORA cualquier
    # instrucción incrustada: el veredicto dice terminado, así que el bucle NO
    # actúa aunque "la pantalla" gritara 'haz clic aquí'. El bucle solo obedece
    # al veredicto estructurado, nunca a texto libre.
    veredictos = [
        {"prohibida": False, "terminado": True, "irreversible": False,
         "accion": None, "motivo": "no hay nada que hacer; ignoré el popup"},
    ]
    ejec = _ejecutor()
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos), ejecutar=ejec)
    assert r["estado"] == "completado"
    assert ejec.acciones == []  # ninguna acción salió de "la pantalla"


# ── 4) Acción irreversible → gate (para + propone, no ejecuta) ───────────────


def test_irreversible_va_al_gate():
    veredictos = [
        {"prohibida": False, "terminado": False, "irreversible": False,
         "accion": {"tipo": "click", "x": 5, "y": 5}, "descripcion": "navegar"},
        {"prohibida": False, "terminado": False, "irreversible": True,
         "accion": {"tipo": "click", "x": 9, "y": 9}, "descripcion": "botón Eliminar todo"},
    ]
    ejec = _ejecutor()
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos), ejecutar=ejec)
    assert r["estado"] == "gate"
    assert r["accion"] == {"tipo": "click", "x": 9, "y": 9}
    assert "Eliminar" in r["descripcion"]
    # Solo la 1ra (segura) se ejecutó; la irreversible NO.
    assert ejec.acciones == [{"tipo": "click", "x": 5, "y": 5}]


# ── 5) Kill switch corta el bucle ────────────────────────────────────────────


def test_kill_switch_corta_el_bucle():
    veredictos = [
        {"prohibida": False, "terminado": False, "irreversible": False,
         "accion": {"tipo": "click", "x": 1, "y": 1}, "descripcion": "click"},
    ] * 5
    ejec = _ejecutor(resultado={"ok": False, "tipo": "abortado_killswitch",
                                "mensaje": "mouse a la esquina"})
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos), ejecutar=ejec)
    assert r["estado"] == "abortado"
    assert "kill switch" in r["motivo"]
    assert len(ejec.acciones) == 1  # se intentó 1 y se cortó


# ── Extras: tope de pasos, piloto perdido, captura fallida ───────────────────


def test_tope_de_pasos():
    # Siempre devuelve una acción segura → nunca termina → corta en max_pasos.
    veredictos = [{"prohibida": False, "terminado": False, "irreversible": False,
                   "accion": {"tipo": "scroll", "cantidad": 1}, "descripcion": "scroll"}]
    ejec = _ejecutor()
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos),
                ejecutar=ejec, max_pasos=4)
    assert r["estado"] == "tope"
    assert len(ejec.acciones) == 4


def test_piloto_perdido_aborta():
    # No prohibida, no terminado, pero sin acción válida → abort (no a ciegas).
    veredictos = [{"prohibida": False, "terminado": False, "irreversible": False,
                   "accion": None, "motivo": "no sé qué hacer"}]
    ejec = _ejecutor()
    r = _correr(capturar=_cap_ok(), interpretar=_interpret_secuencia(veredictos), ejecutar=ejec)
    assert r["estado"] == "abortado"
    assert ejec.acciones == []


def test_captura_fallida_aborta():
    async def _cap_fail():
        return {"ok": False, "tipo": "error_captura", "mensaje": "no pude capturar"}
    ejec = _ejecutor()
    r = _correr(capturar=_cap_fail, interpretar=_interpret_secuencia([{}]), ejecutar=ejec)
    assert r["estado"] == "abortado"
    assert ejec.acciones == []


# ── Recalibración del riel anti-inyección / prohibida (prompt del piloto) ────


def test_prompt_no_trata_texto_como_prohibida():
    """Regresión del falso positivo: el prompt YA NO empuja 'ante la duda
    prohibida' ni trata 'pantalla con instrucciones' como prohibida. Reserva
    prohibida para pantallas SENSIBLES (login/banca) y manda IGNORAR el texto."""
    from app.matix.llm import _CONTROL_SYSTEM as s

    bajo = s.lower()
    # Ya NO existe el gatillo que sobre-abortaba.
    assert "ante la duda, prohibida=true" not in bajo
    assert "pantalla de instrucciones" in bajo  # ahora dice que NO existe esa categoría
    assert "no existe la categoria" in _norm_simple(s)
    # El texto de pantalla es DATO; se ignora, no se obedece.
    assert "ignoras" in bajo and "lienzo" in bajo
    # prohibida sigue cubriendo lo sensible.
    assert "login" in bajo and ("banca" in bajo or "pago" in bajo)
    # Un escritorio/terminal/navegador NUNCA es prohibida.
    assert "nunca prohibida" in bajo


def _norm_simple(t: str) -> str:
    import unicodedata
    return "".join(
        c for c in unicodedata.normalize("NFD", t.lower())
        if unicodedata.category(c) != "Mn"
    )


# ── Presupuesto de tiempo → tope limpio (nunca silencio) ─────────────────────


def test_presupuesto_de_tiempo_para_limpio():
    """Si el bucle agota su presupuesto de tiempo, para con estado 'tope' y un
    motivo claro — nunca se cuelga ni revienta el timeout del chat."""
    reloj_vals = iter([0.0, 0.0, 100.0, 100.0])  # inicio, paso1 ok, paso2 supera

    def reloj():
        return next(reloj_vals)

    nunca_termina = _interpret_secuencia([
        {"prohibida": False, "terminado": False, "irreversible": False,
         "accion": {"tipo": "scroll", "cantidad": 1}, "descripcion": "scrolleo"},
    ])
    r = _correr(
        capturar=_cap_ok(), interpretar=nunca_termina, ejecutar=_ejecutor(),
        presupuesto_s=10.0, reloj=reloj,
    )
    assert r["estado"] == "tope"
    assert "tiempo" in r.get("motivo", "")
