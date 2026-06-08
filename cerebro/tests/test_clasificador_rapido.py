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


def test_crea_tarea_con_fecha_va_al_llm():
    # Si hay fecha, el LLM la convierte a `vence_en` correctamente — el
    # clasificador no se mete con parsing de fechas-en-español.
    for msj in [
        "crea una tarea de comprar pan mañana",
        "recuérdame llamar al banco el viernes",
        "agrega tarea: entregar informe a las 10am",
        "nueva tarea: cita el 15 de marzo",
    ]:
        assert cl.detectar(msj) is None, f"NO debió disparar: «{msj}»"


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
