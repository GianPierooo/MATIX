"""El clasificador rápido pre-LLM: ejecuta acciones LIMPIAS sin tocar el modelo.

Acá probamos los CAMINOS POSITIVOS (encaja → intención) y los VETOS críticos
(ambiguo o con fecha → None, lo maneja el LLM). El módulo es PURO: no hay BD ni
red — el test es trivial.
"""
from __future__ import annotations

from app.matix import clasificador_rapido as cl


# ── Saludos ──────────────────────────────────────────────────────────────────


def test_saludo_simple_devuelve_respuesta_lista():
    i = cl.detectar("hola")
    assert i is not None
    assert i.tipo == "saludo"
    assert i.etiqueta_motivo == "saludo"
    assert "Hola" in (i.mensaje or "")


def test_saludo_tolera_signos_y_capitales():
    assert cl.detectar("HOLA!").tipo == "saludo"
    assert cl.detectar("¡Hola!").tipo == "saludo"
    assert cl.detectar("buenos días").tipo == "saludo"


def test_agradecimiento():
    i = cl.detectar("gracias")
    assert i and i.tipo == "saludo" and i.etiqueta_motivo == "agradecimiento"


def test_afirmacion_vacia():
    i = cl.detectar("ok")
    assert i and i.tipo == "saludo" and i.etiqueta_motivo == "afirmacion"


def test_saludo_con_pregunta_va_al_llm():
    # "hola, qué tal" abre conversación: lo maneja el LLM (tiene personalidad).
    assert cl.detectar("hola, ¿qué tal?") is None
    assert cl.detectar("hola, cómo estás?") is None


def test_saludo_no_dispara_con_contenido_extra():
    # "hola, agrega tarea X" NO es saludo: cae al LLM (que entiende mejor).
    assert cl.detectar("hola agrega una tarea de comprar pan") is None


# ── "Anota X" → crear_apunte ─────────────────────────────────────────────────


def test_anota_simple_crea_apunte():
    i = cl.detectar("anota: la idea del bot de bolsa")
    assert i is not None
    assert i.tipo == "tool"
    assert i.nombre == "crear_apunte"
    assert i.etiqueta_motivo == "anota"
    assert (i.args or {}).get("titulo") == "la idea del bot de bolsa"


def test_anota_acepta_variantes_de_verbo():
    for verbo in ["anota", "apunta", "anotame", "apúntame", "toma nota de", "guarda esto:", "nota:"]:
        msj = f"{verbo} probar una hipótesis"
        i = cl.detectar(msj)
        assert i is not None and i.nombre == "crear_apunte", f"falló «{verbo}»"


def test_anota_con_verbo_de_accion_va_al_llm():
    # El usuario dijo "anota" pero el contenido es una acción → tarea, no apunte.
    # Mejor que el LLM decida (puede crear tarea con fecha si la hay).
    assert cl.detectar("anota llamar a juan") is None
    assert cl.detectar("anota comprar pan integral") is None


def test_anota_con_fecha_va_al_llm():
    # "mañana" / hora → al LLM, que sabe poner `vence_en` en una tarea.
    assert cl.detectar("anota la reunión mañana 10am") is None
    assert cl.detectar("anota el examen el viernes") is None
    assert cl.detectar("anota cita 14:00") is None


def test_anota_muy_largo_va_al_llm():
    # Textos muy largos suelen ser "anota: este resumen extenso de…" — el LLM
    # debería decidir si es un apunte normal o necesita estructurarlo.
    largo = "anota: " + ("contenido " * 50)
    assert cl.detectar(largo) is None


def test_anota_vacio_va_al_llm():
    # "anota" suelto sin contenido: el LLM tendrá que preguntar qué.
    assert cl.detectar("anota") is None
    assert cl.detectar("anota:") is None


# ── "Crea tarea X" simple (sin fecha) ────────────────────────────────────────


def test_crea_tarea_simple_sin_fecha():
    i = cl.detectar("crea una tarea de comprar pan")
    assert i is not None
    assert i.tipo == "tool"
    assert i.nombre == "crear_tarea"
    assert i.etiqueta_motivo == "crea_tarea_simple"
    assert (i.args or {}).get("titulo") == "comprar pan"


def test_crea_tarea_variantes():
    for msj in [
        "agrega una tarea: pasear al perro",
        "añade tarea revisar el correo",
        "pon una tarea de pasar al supermercado",
        "nueva tarea: ordenar el escritorio",
    ]:
        i = cl.detectar(msj)
        assert i is not None and i.nombre == "crear_tarea", f"falló «{msj}»"


def test_recuerdame_sin_fecha_es_tarea():
    i = cl.detectar("recuérdame pasar por la farmacia")
    assert i is not None and i.nombre == "crear_tarea"
    assert "farmacia" in (i.args or {}).get("titulo", "")


def test_crea_tarea_con_fecha_SIN_ahora_va_al_llm():
    # Compat: sin `ahora` inyectado, el clasificador NO resuelve fechas y delega.
    for msj in [
        "crea una tarea de comprar pan mañana",
        "recuérdame llamar al banco el viernes",
        "agrega tarea: entregar informe a las 10am",
        "nueva tarea: cita el 15 de marzo",
    ]:
        assert cl.detectar(msj) is None, f"NO debió disparar: «{msj}»"


def test_crea_tarea_con_fecha_resuelta_con_ahora():
    # T5: con `ahora`, la fecha común se resuelve determinista → `vence_en`.
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)  # jueves 10:00 Lima
    i = cl.detectar("recuérdame llamar al banco mañana a las 3pm", ahora=ahora)
    assert i is not None and i.nombre == "crear_tarea"
    assert i.etiqueta_motivo == "crea_tarea_fecha"
    assert (i.args or {}).get("vence_en", "").startswith("2026-07-03T15:00")
    assert "banco" in (i.args or {}).get("titulo", "").lower()
    assert "manana" not in cl._norm((i.args or {}).get("titulo", ""))


def test_crea_tarea_fecha_ambigua_con_ahora_delega():
    # "a las 3" sin am/pm ni franja → ambigua → al LLM (nunca adivina).
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    assert cl.detectar("recuérdame llamar al banco a las 3", ahora=ahora) is None


def test_crea_tarea_sin_fecha_con_ahora_sigue_simple():
    # Con `ahora` pero sin fecha en el texto: tarea simple, sin `vence_en`.
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    i = cl.detectar("crea una tarea de comprar pan", ahora=ahora)
    assert i is not None and i.etiqueta_motivo == "crea_tarea_simple"
    assert "vence_en" not in (i.args or {})


# ── Consulta de tareas (B1): "qué tareas tengo hoy" sin LLM ───────────────────


def test_consulta_tareas_hoy_resuelve():
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    i = cl.detectar("qué tareas tengo hoy", ahora=ahora)
    assert i is not None and i.nombre == "consultar_tareas"
    assert i.etiqueta_motivo == "consulta_tareas"
    assert i.args["estado"] == "pendiente"
    assert i.args["vence_desde"] == "2026-07-02"
    assert i.args["vence_hasta"] == "2026-07-02"
    assert i.mensaje == "para hoy"


def test_consulta_mis_pendientes_sin_fecha():
    from datetime import datetime

    i = cl.detectar("mis pendientes", ahora=datetime(2026, 7, 2, 10, 0))
    assert i is not None and i.nombre == "consultar_tareas"
    assert "vence_desde" not in i.args  # todas las pendientes


def test_consulta_tareas_esta_semana_rango():
    from datetime import datetime, timedelta

    ahora = datetime(2026, 7, 2, 10, 0)
    i = cl.detectar("qué tareas tengo esta semana", ahora=ahora)
    assert i is not None and i.args["vence_desde"] == "2026-07-02"
    fin = (ahora.date() + timedelta(days=(6 - ahora.weekday()))).isoformat()
    assert i.args["vence_hasta"] == fin


def test_consulta_ambigua_o_con_filtro_va_al_llm():
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    for msg in [
        "qué tengo hoy",                          # genérico: puede ser agenda → LLM
        "qué tareas tengo del curso de cálculo",  # calificador extra → LLM
        "qué tareas tengo hoy de prioridad alta",  # calificador extra → LLM
        "qué eventos tengo hoy",                   # eventos, no tareas → LLM
    ]:
        assert cl.detectar(msg, ahora=ahora) is None, msg


def test_consulta_sin_ahora_delega():
    assert cl.detectar("qué tareas tengo hoy") is None  # sin reloj → LLM


def test_b1_intercepta_consultas_puras():
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    for m in [
        "que tareas tengo", "tareas pendientes", "que pendientes tengo",
        "mis tareas de manana", "que tareas hay hoy", "que tengo que hacer manana",
    ]:
        i = cl.detectar(m, ahora=ahora)
        assert i is not None and i.nombre == "consultar_tareas", m


def test_b1_delega_frases_trampa():
    # Frases cercanas al límite que NO son una consulta de tareas pura: llevan
    # calificador, otra intención o piden completadas → deben ir al LLM.
    from datetime import datetime

    ahora = datetime(2026, 7, 2, 10, 0)
    for m in [
        "que tareas tengo pendientes con juan",   # calificador (persona)
        "que tareas importantes tengo hoy",        # adjetivo/prioridad
        "cuales son mis tareas de hoy",            # otra construcción
        "dame mis tareas de hoy",                  # verbo distinto
        "que tareas tengo hoy y manana",           # dos periodos
        "que tareas tengo del proyecto onexotic",  # filtro de proyecto
        "tengo tareas hoy",                        # afirmación, no consulta
        "que tareas complete hoy",                 # completadas, no pendientes
        "cuantas tareas tengo hoy",                # conteo, no listado
        "que tareas me faltan hoy",                # otra construcción
    ]:
        assert cl.detectar(m, ahora=ahora) is None, m


def test_frase_consulta_tareas_formato():
    from app.matix import chat

    assert chat._frase_consulta_tareas({"total": 0, "tareas": []}, "para hoy") == (
        "No tienes tareas pendientes para hoy."
    )
    d = {"total": 3, "tareas": [
        {"titulo": "comprar pan"}, {"titulo": "llamar al banco"}, {"titulo": "informe"}]}
    assert chat._frase_consulta_tareas(d, "para hoy") == (
        "Tienes 3 tareas para hoy: comprar pan, llamar al banco y informe."
    )


# ── Vetos transversales ─────────────────────────────────────────────────────


def test_imagen_adjunta_veta_la_ruta_rapida():
    # Con imagen, el modelo TIENE que ver: nada de ruta rápida.
    assert cl.detectar("anota: la idea", hay_imagen=True) is None
    assert cl.detectar("hola", hay_imagen=True) is None


def test_documento_adjunto_veta_la_ruta_rapida():
    assert cl.detectar("anota: la idea", hay_documento=True) is None


def test_modo_pesado_veta_la_ruta_rapida():
    # En modos tesis/estudio, respetar el contexto del modo > ahorrar latencia.
    assert cl.detectar("hola", modo_activo="tesis") is None
    assert cl.detectar("anota: la idea", modo_activo="estudio") is None
    # Modos livianos NO vetan.
    assert cl.detectar("hola", modo_activo="motivacion") is not None


def test_vacio_es_none():
    assert cl.detectar("") is None
    assert cl.detectar("   ") is None


def test_pregunta_va_al_llm():
    # Preguntas libres siempre al LLM — el clasificador no inventa respuestas.
    for msj in [
        "¿qué tengo hoy?",
        "cuántas tareas tengo?",
        "explícame las matrices",
        "cómo va el proyecto matix",
    ]:
        assert cl.detectar(msj) is None, f"NO debió disparar: «{msj}»"


def test_comando_complejo_va_al_llm():
    # Múltiples acciones en un mensaje → el LLM las orquesta.
    msj = "anota la idea y crea una tarea de revisarla mañana"
    assert cl.detectar(msj) is None
