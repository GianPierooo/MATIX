"""Enrutador del modo "Automático": elige el modelo POR CADA MENSAJE.

Cuando el usuario tiene seleccionado "auto", el cerebro decide qué modelo
usar en cada turno por REGLAS — sin una llamada extra a ningún modelo, así
que no añade latencia. Este módulo concentra esas reglas en UN solo lugar
para afinarlas fácil.

Prioridad de las reglas (la primera que aplica, gana):

1. Hay un modo "pesado" activo (tesis, estudio/tutor) → modelo FUERTE.
2. El mensaje pide escritura, razonamiento o análisis a fondo (redacta,
   analiza, compara, explica en profundidad, código, matemática, varios
   pasos, o simplemente es largo) → modelo FUERTE.
3. Comando corto / CRUD / pregunta rápida ("crea tarea X", "márcala
   hecha", "qué tengo hoy") → modelo BARATO.
4. Por defecto → modelo BARATO.

La decisión es por mensaje del usuario; un turno completo (incluido su loop
de tools) se queda en el modelo elegido — `chat.py` resuelve esto UNA vez
por turno y no cambia de modelo a mitad del loop.

Es un módulo PURO (sin BD, sin red): recibe el mensaje, el modo activo y el
par barato/fuerte ya resueltos, y devuelve la decisión. Eso lo hace trivial
de testear.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

# Modos que justifican el modelo fuerte: trabajo pesado de escritura,
# análisis o enseñanza a fondo. "motivacion" es un empujón corto y liviano,
# así que NO entra. Editar este set para recalibrar.
MODOS_PESADOS: frozenset[str] = frozenset({"tesis", "estudio"})

# Por encima de este largo (caracteres del mensaje normalizado) asumimos que
# es escritura/razonamiento aunque no dispare ningún verbo: los mensajes
# largos casi nunca son comandos cortos.
_UMBRAL_LARGO = 320

# Acciones del teléfono (Capa 6 · Fase 1): abrir app/url/mapa, llamar, mandar
# WhatsApp/SMS/correo, leer la galería. El modelo BARATO es inconsistente
# llamando estas tools (a veces narra o rehúsa: "no puedo abrir apps"), así que
# estos pedidos van al modelo FUERTE, que sí dispara la tool de forma fiable.
# Se evalúa sobre el texto normalizado (minúsculas, sin acentos).
_ACCION_DISPOSITIVO = re.compile(
    r"\b("
    # abrir app / url / mapa
    r"abre|abreme|abrir|abrime|lanza|lanzame|"
    # mensajería
    r"whatsapp|wasap|wasapea|wasapeale|wsp|sms|"
    r"mandale|mandame|mensajea|mensajeale|escribele|"
    # llamada ("marca" se trata aparte para no chocar con «marca la tarea»)
    r"llama|llamale|llamar|llamame|telefonea|"
    # galería / foto del teléfono
    r"galeria"
    r")\b"
    r"|ultima foto|mi ultima foto"
    r"|manda(le|me)? un (whatsapp|mensaje|sms|correo)"
    r"|envia(le|me)? un (whatsapp|mensaje|sms|correo)"
    r"|marca (a|al|el numero)\b"
)

# Control de la PC (Capa 6): operar la compu del usuario —y sobre todo el
# control AUTÓNOMO de pantalla multi-paso (6.3)— es de las tareas MÁS duras
# (planear pasos, leer capturas, decidir clicks). Siempre al modelo FUERTE: el
# mini es inconsistente disparando `pc_*` y peor aún conduciendo el bucle.
_PC = re.compile(
    r"\b(pc|compu|computadora|laptop|pantalla)\b"
    r"|\bcontrol(a|ar|ame|alo)?\b"
    r"|haz(lo)? (tu|por mi)"
)

# Intake analítico + generación del plan: tareas DURAS (análisis a fondo,
# detección de huecos, plan en capas). Van al modelo FUERTE/razonador, no al
# mini. El chat casual sigue en rápido.
_INTAKE_PLAN = re.compile(
    r"\b("
    r"estructura|estructurame|estructuralo|estructurarlo|"
    r"entrevistame|entrevista|intake|"
    r"planifica|planificame|planifiquemos|replanifica|replanificame|"
    r"reajusta|reajustame|reescopea|"
    r"crea(me)? un proyecto|nuevo proyecto"
    r")\b"
    r"|arma(me)? el plan|armemos el plan|plan en capas|plan del proyecto"
    r"|entender el proyecto|a fondo el proyecto"
    r"|desde este plan|importa(r)? (este |el )?plan|crea(r)? .*desde (este|el) plan"
    r"|revisa(me)? (el|mi) proyecto|revision del proyecto|como va(mos)? (el|con el) proyecto"
    r"|que sigue en el proyecto|mejora(r)? el plan"
)

# Comentarios de PROGRESO/cambio/blocker/idea sobre un proyecto: disparan la
# mejora continua conversacional (actualizar árbol/perfil/% en el momento), que
# es tarea dura → modelo FUERTE. Son frases típicas de avance.
_COMENTARIO_PROYECTO = re.compile(
    r"\b("
    r"avance|avances|avanc|"
    r"termine|complete|acabe|"
    # verbos de "entregué/publiqué algo": reportes de avance frecuentes
    r"subi|publique|lance|grabe|entregue|estrene|"
    r"me trabe|trabad|atascad|estancad|"
    r"cambie de (idea|rumbo|plan|enfoque)|"
    r"se me ocurrio|tengo una idea|idea nueva|"
    r"ya hice|ya tengo|ya termine|ya complete|ya subi|logre"
    r")\b"
)

# Fraseo de recordatorio / agenda: «recuérdame llamar al banco» es un
# recordatorio, NO una llamada. Estos verbos VETAN la ruta de acción de
# dispositivo (el «llamar/mandar» embebido es el contenido del recordatorio,
# no la acción a ejecutar ahora).
_RECORDATORIO = re.compile(
    r"\b(recuerda|recuerdame|recordar|recordatorio|"
    r"agenda|agendame|programa|programame)\b"
)

# Señales de escritura / razonamiento / análisis a fondo → modelo fuerte.
# Se evalúa sobre el texto normalizado (minúsculas, sin acentos).
_PESADO = re.compile(
    r"\b("
    r"redacta|redactame|redaccion|escribeme|ensayo|articulo|informe|"
    r"monografia|parrafo|"
    r"analiza|analisis|analizar|analicemos|compara|comparacion|comparar|"
    r"contrasta|evalua|evaluar|critica|criticame|"
    r"profundiza|profundidad|"
    r"desarrolla|desarrollar|argumenta|argumentar|justifica|demuestra|"
    r"demostracion|razona|razonar|deduce|sintetiza|"
    r"ideacion|brainstorm|propon|proponme|propone|disena|disenar|"
    r"codigo|programa|programar|funcion|algoritmo|refactoriza|depura|"
    r"implementa|implementar|debuggear|debug|script|stacktrace|"
    r"ecuacion|integral|derivada|teorema|calcula|calcular|resuelve|resolver|"
    r"matematic|probabilidad|estadistic|optimiza|optimizar|demostrar|"
    r"traduce|traduccion|traducir"
    r")\b"
    r"|a fondo|en profundidad|paso a paso|lluvia de ideas|en detalle"
)

# Verbos "blandos": explica / revisa / mejora / corrige son AMBIGUOS. "revisa mi
# ensayo" o "explícame cómo funciona la fotosíntesis" son razonamiento/escritura
# (→ fuerte); pero "revisa mis tareas de hoy" o "explícame qué tengo hoy" son
# CONSULTAS triviales del hub (→ barato, no gastamos Sonnet en leer la agenda).
# Se resuelven abajo: fuerte por defecto, SALVO consulta corta del hub.
_PESADO_BLANDO = re.compile(
    r"\b(explica|explicame|explicacion|explicar|"
    r"revisa|revisame|revisar|mejora|mejorame|mejorar|"
    r"corrige|corrigeme|corregir)\b"
)

# Consulta trivial del hub: «qué tengo hoy», «mi día», «mis tareas/pendientes».
# Palabras del hub (sin acentos: el texto ya viene normalizado).
_CONSULTA_HUB = re.compile(
    r"\b(que tengo|que hay|que eventos|que tareas|mi dia|mi agenda|"
    r"mi semana|mis tareas|mis pendientes|mis eventos|mis clases|"
    r"pendientes|agenda|hoy|manana|esta semana)\b"
)
# Una consulta del hub es CORTA ("revisa mis tareas de hoy" ~24). Un pedido con
# razonamiento encima ("revisa mis tareas y dime cuál priorizar y por qué" ~49)
# ya no lo es → 40 lo manda al fuerte en vez de degradarlo por error.
_CONSULTA_CORTA = 40

# Señales de comando corto / CRUD / pregunta rápida → modelo barato. Solo
# se consulta cuando NO disparó `_PESADO` (las reglas pesadas tienen
# prioridad), para distinguir "comando_corto" de "default" en la traza.
_CORTO = re.compile(
    r"\b("
    r"crea|crear|creame|agrega|agregar|agregame|anade|anadir|pon|ponme|"
    r"marca|marcala|marcalo|completa|completala|termina|terminala|hecha|"
    r"hecho|lista|listame|listar|muestra|muestrame|borra|borrar|elimina|"
    r"eliminar|quita|quitar|mueve|mover|cambia|reprograma|renombra|"
    r"recuerdame|recordar|recordatorio|programa|agenda|agendame|"
    r"que tengo|que hay|que eventos|cuando es|cuanto|cuantos|cuantas|"
    r"hoy|manana|pendientes|gracias|hola|ok|dale|si|no"
    r")\b"
)


@dataclass(frozen=True)
class Decision:
    """El modelo elegido y por qué (para la traza/transparencia)."""

    modelo: str
    # "modo_pesado" | "intake_plan" | "accion_dispositivo" | "razonamiento" |
    # "consulta_hub" | "comando_corto" | "default"
    motivo: str


def _norm(texto: str) -> str:
    """Minúsculas + sin acentos, para que las reglas no dependan de tildes."""
    s = (texto or "").lower()
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def elegir(
    mensaje: str,
    *,
    modo_activo: str | None,
    barato: str,
    fuerte: str,
) -> Decision:
    """Decide el modelo para ESTE mensaje, según las reglas de arriba.

    `modo_activo` es el modo de Matix al arrancar el turno (o `None`).
    `barato`/`fuerte` son ids del catálogo, ya resueltos por el llamador.
    """
    if modo_activo in MODOS_PESADOS:
        return Decision(fuerte, "modo_pesado")

    texto = _norm(mensaje)

    # Operar la PC / control de pantalla: tarea dura → modelo FUERTE. (Antes de
    # accion_dispositivo: «en mi pc pon una canción» debe ir al fuerte aunque no
    # diga «abre».)
    if _PC.search(texto):
        return Decision(fuerte, "pc_control")

    # Intake / plan / revisión / comentario de progreso de un proyecto: al
    # modelo FUERTE (actualizar el plan/árbol coherente es tarea dura).
    if _INTAKE_PLAN.search(texto) or _COMENTARIO_PROYECTO.search(texto):
        return Decision(fuerte, "intake_plan")

    # Acción del teléfono (abrir/llamar/mandar/galería): al modelo FUERTE, que
    # llama estas tools de forma fiable. El barato a veces narra o rehúsa.
    # Excepción: si es un recordatorio/agenda, el «llamar/mandar» es el
    # CONTENIDO del recordatorio, no una acción a ejecutar ahora.
    if _ACCION_DISPOSITIVO.search(texto) and not _RECORDATORIO.search(texto):
        return Decision(fuerte, "accion_dispositivo")

    # Verbo/señal de razonamiento, o simplemente un mensaje largo: los
    # mensajes largos casi nunca son comandos cortos, así que se asumen
    # escritura/razonamiento. (No se gatea con `_CORTO` porque un texto
    # reflexivo largo contiene "no"/"si" de forma natural.)
    if _PESADO.search(texto) or len(texto) >= _UMBRAL_LARGO:
        return Decision(fuerte, "razonamiento")

    # Verbo blando (explica/revisa/mejora/corrige): fuerte por defecto (razonar/
    # escribir), SALVO que sea una consulta corta del hub ("revisa mis tareas de
    # hoy", "explícame qué tengo hoy") → ahí basta el barato.
    if _PESADO_BLANDO.search(texto):
        if len(texto) <= _CONSULTA_CORTA and _CONSULTA_HUB.search(texto):
            return Decision(barato, "consulta_hub")
        return Decision(fuerte, "razonamiento")

    if _CORTO.search(texto):
        return Decision(barato, "comando_corto")

    return Decision(barato, "default")
