"""Reglas del enrutador del modo Automático (módulo puro, sin BD ni red).

Casos clave del paso: modo pesado, comando corto, razonamiento/escritura
largo, código/matemática, y el default. El par se pasa fijo para que el
test solo verifique la DECISIÓN, no la config.
"""
from __future__ import annotations

from app.matix import enrutador

BARATO = "gpt-4o-mini"
FUERTE = "claude-sonnet-4-6"


def _elegir(mensaje: str, modo=None):
    return enrutador.elegir(mensaje, modo_activo=modo, barato=BARATO, fuerte=FUERTE)


def test_modo_pesado_fuerza_el_fuerte():
    # Aunque el mensaje sea trivial, un modo pesado manda al fuerte.
    d = _elegir("ok", modo="tesis")
    assert d.modelo == FUERTE and d.motivo == "modo_pesado"
    assert _elegir("gracias", modo="estudio").modelo == FUERTE


def test_modo_liviano_no_fuerza():
    # "motivacion" no es pesado: un comando corto sigue siendo barato.
    d = _elegir("crea una tarea", modo="motivacion")
    assert d.modelo == BARATO


def test_comando_corto_va_al_barato():
    for m in [
        "crea tarea comprar pan",
        "márcala hecha",
        "qué tengo hoy",
        "recuérdame llamar al banco mañana",
        "borra ese evento",
    ]:
        d = _elegir(m)
        assert d.modelo == BARATO, m
        assert d.motivo == "comando_corto"


def test_razonamiento_o_escritura_va_al_fuerte():
    for m in [
        "redacta un ensayo sobre la guerra fría",
        "analiza a fondo este problema",
        "compara estas dos opciones",
        "explícame en profundidad cómo funciona la fotosíntesis",
        "escríbeme un correo formal para el profesor",
    ]:
        d = _elegir(m)
        assert d.modelo == FUERTE, m
        assert d.motivo == "razonamiento"


def test_codigo_y_matematica_van_al_fuerte():
    assert _elegir("escribe una función en python que ordene una lista").modelo == FUERTE
    assert _elegir("resuelve esta integral paso a paso").modelo == FUERTE
    assert _elegir("hay un bug en mi algoritmo, ayúdame a depurarlo").modelo == FUERTE


def test_mensaje_largo_sin_verbo_va_al_fuerte():
    # Un mensaje largo (sin verbo de comando) se asume razonamiento/escritura.
    largo = (
        "Estuve pensando bastante en mi futuro profesional y en como "
        "equilibrar mis cosas con el trabajo y la vida personal, y la verdad "
        "es que tengo sentimientos encontrados, porque por un lado quiero "
        "avanzar rapido hacia mis metas pero por otro lado tengo miedo de "
        "quemarme y de descuidar a las personas que mas me importan en este "
        "momento tan particular de mi vida y de mi carrera universitaria."
    )
    assert len(largo) >= 320
    d = _elegir(largo)
    assert d.modelo == FUERTE and d.motivo == "razonamiento"


def test_default_va_al_barato():
    # Saludo/charla trivial que no es ni pesado ni un comando reconocido.
    d = _elegir("buenas, todo bien por acá")
    assert d.modelo == BARATO


def test_pesado_gana_a_comando_corto():
    # Si hay señal pesada y de comando, el pesado tiene prioridad.
    d = _elegir("analiza esto y luego crea una tarea")
    assert d.modelo == FUERTE and d.motivo == "razonamiento"


def test_accion_de_dispositivo_va_al_fuerte():
    # Capa 6 · Fase 1: abrir/llamar/mandar/galería al modelo fuerte, que
    # llama estas tools de forma fiable (el barato a veces narra o rehúsa).
    casos = [
        "abre la calculadora",
        "ábreme spotify",
        "mándale un whatsapp a María diciéndole que llego tarde",
        "envíale un mensaje a Felipe",
        "llama a papá",
        "marca al 999888777",
        "abre el mapa a la universidad",
        "accede a mi última foto y anota los gastos",
    ]
    for m in casos:
        d = _elegir(m)
        assert d.modelo == FUERTE, m
        assert d.motivo == "accion_dispositivo", m


def test_accion_de_dispositivo_no_pisa_lo_pesado():
    # Un modo pesado activo sigue mandando aunque el mensaje pida abrir algo.
    d = _elegir("abre la calculadora", modo="tesis")
    assert d.modelo == FUERTE and d.motivo == "modo_pesado"


def test_revision_y_replan_van_al_fuerte():
    for m in [
        "revisa mi proyecto y dime qué sigue",
        "replanifica el proyecto",
        "reajusta el plan del proyecto",
    ]:
        d = _elegir(m)
        assert d.modelo == FUERTE and d.motivo == "intake_plan", m


def test_importar_plan_va_al_fuerte():
    assert _elegir("crea un proyecto desde este plan").modelo == FUERTE
    assert _elegir("importa este plan").modelo == FUERTE


def test_comentario_de_progreso_va_al_fuerte():
    # Comentarios de avance/cambio/blocker disparan la mejora continua → fuerte.
    for m in [
        "ya terminé las fotos del drop",
        "avancé con el marco teórico",
        "me trabé en la pasarela de pago",
        "se me ocurrió una idea para el proyecto",
        "cambié de idea con el enfoque",
        # Reportes de "entregué algo" (mejora continua conversacional):
        "ya subí el primer video",
        "terminé el nodo 3 del plan",
        "publiqué el short en tiktok",
        "grabé el episodio de hoy",
    ]:
        d = _elegir(m)
        assert d.modelo == FUERTE, m
        assert d.motivo == "intake_plan", m


def test_consulta_no_se_confunde_con_progreso():
    # Pedir ver material NO es un reporte de avance: no debe rutearse como
    # "comentario de progreso" (que llevaría a tocar el plan).
    d = _elegir("muéstrame el bloque 3 de guitarra")
    assert d.motivo != "intake_plan"


def test_intake_y_plan_van_al_fuerte():
    # El intake analítico y la generación del plan son tareas duras → fuerte.
    for m in [
        "crea un proyecto de mi marca",
        "estructúralo conmigo",
        "entrevístame para el proyecto",
        "armemos el plan del proyecto",
        "ayúdame a entender el proyecto a fondo",
    ]:
        d = _elegir(m)
        assert d.modelo == FUERTE, m
        assert d.motivo == "intake_plan", m


# ── Control de PC / pantalla → modelo fuerte (Capa 6 · C3) ───────────────────


def test_pc_control_va_al_fuerte():
    casos = [
        "en mi pc abre Spotify y pon una cancion de Michael Jackson",
        "controla mi pantalla y descarga el archivo",
        "en mi compu busca el pdf y abrelo",
        "hazlo tu en la laptop",
        "abre el chrome de mi pc",
    ]
    for m in casos:
        d = _elegir(m)
        assert d.modelo == FUERTE, f"PC debió ir al fuerte: {m!r} → {d.motivo}"
        assert d.motivo in ("pc_control", "accion_dispositivo"), d.motivo


def test_pc_no_secuestra_frases_sin_pc():
    # "completa la tarea" no menciona PC: sigue barato.
    assert _elegir("completa la tarea de hoy").modelo == BARATO
