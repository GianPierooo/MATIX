from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class MensajeChat(BaseModel):
    """Un mensaje del historial. `rol` es `user` o `assistant`."""

    rol: Literal["user", "assistant"]
    contenido: str


class DocumentoChat(BaseModel):
    """Documento adjunto al turno del chat (texto ya extraído por el cerebro).

    Lo manda la app tras subir el archivo a `/matix/extraer-documento`: el
    texto viaja como contexto de ESE turno para que Matix lo lea/analice/
    resuma. No se guarda en el historial (como la imagen)."""

    nombre: str
    texto: str


class ChatRequest(BaseModel):
    """Cuerpo del endpoint `/matix/chat`.

    `imagen`, si viene, es un data URL (`data:image/...;base64,...`) que
    se adjunta al mensaje para que el modelo de visión la vea. Va al
    servidor a propósito (distinto del OCR on-device): para entender la
    imagen hace falta el modelo. Solo viaja en ESE turno; no se guarda
    en el historial.

    `documento`, si viene, es el texto extraído de un PDF/DOCX/TXT/MD que el
    usuario adjuntó. También es contexto de ESE turno.
    """

    historial: list[MensajeChat] = Field(default_factory=list)
    mensaje: str = Field(min_length=1)
    # `imagen` (singular) se mantiene por compatibilidad; `imagenes` permite
    # adjuntar VARIAS en un mismo turno (ambos proveedores aceptan varios
    # bloques de imagen). Las dos van como data URL y solo en ESE turno.
    imagen: str | None = None
    imagenes: list[str] | None = None
    documento: DocumentoChat | None = None
    # Clave de idempotencia del turno (la genera la app y la REUSA si
    # reintenta tras una caída). Con la misma clave, el cerebro no re-ejecuta:
    # devuelve el resultado guardado (no duplica escrituras). Opcional.
    idempotency_key: str | None = None


class DocumentoExtraidoResponse(BaseModel):
    """Respuesta de `/matix/extraer-documento`: el texto que la app luego
    manda como `documento` en el chat (y puede ofrecer guardar en apuntes)."""

    nombre: str
    texto: str
    caracteres: int
    truncado: bool


class TranscripcionResponse(BaseModel):
    """Respuesta del endpoint `/matix/transcribir`.

    Solo devolvemos el texto. La app lo deja en el campo del composer
    para que el usuario lo valide y mande con el flujo normal.
    """

    texto: str


class VozRequest(BaseModel):
    """Cuerpo del endpoint `/matix/voz` (text-to-speech).

    `voz` es opcional; el default `onyx` se eligió en Capa 2 Paso 5.1
    como voz masculina grave estándar de Matix. Otras válidas en
    OpenAI: `alloy`, `echo`, `fable`, `nova`, `shimmer`.
    """

    texto: str = Field(min_length=1, max_length=4096)
    voz: str = "onyx"


class CapturaApunteRequest(BaseModel):
    """Cuerpo del endpoint `/matix/capturar-apunte`.

    `texto` es la idea ya transcrita (Whisper) que se dictó desde la
    barra "Anota algo…" de Inicio. NO es conversación: el cerebro la
    guarda como apunte clasificado en una sola pasada.
    """

    texto: str = Field(min_length=1)


class CapturaApunteResponse(BaseModel):
    """Respuesta del endpoint `/matix/capturar-apunte`.

    Devuelve el ítem recién creado (apunte o tarea) con su clasificación. La
    captura rápida puede crear:
      - APUNTE (idea / nota sin acción clara) — el caso histórico.
      - TAREA (verbo de acción: comprar, llamar, estudiar…) — bug fix de Tu día.

    NUNCA crea evento (los eventos solo vienen por la ruta explícita con hora
    fija del usuario). El campo `tipo` permite a la app pintar el snackbar
    correcto y refrescar la sección adecuada.

    `tablas_cambiadas` lleva `"apuntes"` o `"tareas"` según corresponda, para
    que la app invalide los providers correctos.
    """

    # "apunte" (default por compat) o "tarea".
    tipo: str = "apunte"
    id: str
    titulo: str
    # Campos de apunte (cuando tipo=="apunte"); vacíos para tarea.
    etiquetas: list[str] = Field(default_factory=list)
    proyecto_nombre: str | None = None
    curso_nombre: str | None = None
    general: bool = True
    tablas_cambiadas: list[str] = Field(default_factory=lambda: ["apuntes"])


class ExtraerTareasRequest(BaseModel):
    """Cuerpo del endpoint `/matix/extraer-tareas` (Capa 7-B).

    `texto` es el resultado del OCR de una foto (Capa 7-A) que el
    usuario ya revisó y corrigió en la app. SOLO viaja el texto: la
    imagen se quedó en el teléfono. El cerebro lo lee y propone tareas;
    no crea nada — la app las muestra para que el usuario confirme.
    """

    texto: str = Field(min_length=1)


class TareaPropuesta(BaseModel):
    """Una tarea candidata extraída del texto.

    `vence_en` es una fecha (sin hora) o `None`. El modelo resuelve
    fechas relativas ('el viernes') a una fecha real; si la tarea no
    menciona fecha, queda en `None`. La app deja editar título y fecha
    en la hoja de revisión antes de crear.
    """

    titulo: str
    vence_en: date | None = None


class ExtraerTareasResponse(BaseModel):
    """Respuesta del endpoint `/matix/extraer-tareas`.

    `tareas` puede venir vacía cuando el texto no tiene acciones
    claras — es un resultado válido, no un error. La app lo muestra
    como "No encontré tareas claras en el texto".
    """

    tareas: list[TareaPropuesta] = Field(default_factory=list)


class TareaParaEstimar(BaseModel):
    """Una tarea que el planificador necesita dimensionar."""

    id: str
    titulo: str = Field(min_length=1)


class EstimarDuracionesRequest(BaseModel):
    """Cuerpo de `/matix/estimar-duraciones` (Urgencia-3).

    La app manda las tareas pendientes (id + título) que quiere
    planificar hoy; el cerebro estima cuántos minutos toma cada una.
    El encaje en los huecos del día lo hace la app de forma
    determinística — esto solo aporta la duración.
    """

    tareas: list[TareaParaEstimar] = Field(default_factory=list)


class DuracionEstimada(BaseModel):
    tarea_id: str
    minutos: int


class EstimarDuracionesResponse(BaseModel):
    """Respuesta de `/matix/estimar-duraciones`. Una entrada por tarea
    estimada; las que el modelo no pudo dimensionar se omiten y la app
    les aplica un default."""

    duraciones: list[DuracionEstimada] = Field(default_factory=list)


class DesglosarTareaRequest(BaseModel):
    """Cuerpo de `/matix/desglosar-tarea` (Capa 7 · Desglose).

    `titulo` es la tarea a partir; `nota` es contexto opcional. El
    cerebro propone pasos accionables; NO crea nada — la app los muestra
    para que el usuario revise y confirme.
    """

    titulo: str = Field(min_length=1)
    nota: str | None = None


class PasoPropuesto(BaseModel):
    """Un paso del desglose. `horizonte` ordena el paso en el tiempo:
    `ahora` (arrancar ya), `pronto`, `mas_adelante`."""

    titulo: str
    horizonte: Literal["ahora", "pronto", "mas_adelante"] = "pronto"


class DesglosarTareaResponse(BaseModel):
    """Respuesta de `/matix/desglosar-tarea`.

    Si la tarea ya es atómica, `es_atomica=True` y `pasos` viene vacía —
    la app muestra "esto ya es accionable, no hay qué desglosar".
    """

    es_atomica: bool = False
    pasos: list[PasoPropuesto] = Field(default_factory=list)


class ExtraerEventosRequest(BaseModel):
    """Cuerpo de `/matix/extraer-eventos` (Cámara · sílabo).

    `texto` es el OCR de un sílabo u horario (ya corregido por el
    usuario). SOLO viaja el texto: la imagen se quedó en el teléfono.
    El cerebro propone eventos; no crea nada.
    """

    texto: str = Field(min_length=1)


class EventoPropuesto(BaseModel):
    """Un evento candidato. `tipo` distingue clases recurrentes de
    fechas únicas. Para 'recurrente', `dias_semana` (ISO 1=lun…7=dom) y
    horas. Para 'unico', `fecha`. Las horas son HH:MM o null."""

    tipo: Literal["recurrente", "unico"]
    titulo: str
    dias_semana: list[int] = Field(default_factory=list)
    hora_inicio: str | None = None
    hora_fin: str | None = None
    fecha: date | None = None


class ExtraerEventosResponse(BaseModel):
    """Respuesta de `/matix/extraer-eventos`. `eventos` vacía cuando el
    texto no tiene nada datable — resultado válido, no error."""

    eventos: list[EventoPropuesto] = Field(default_factory=list)


class TareaCap(BaseModel):
    titulo: str
    vence_en: date | None = None


class SesionCap(BaseModel):
    dia_semana: int = Field(ge=0, le=6)  # 0=lunes … 6=domingo
    hora_inicio: str
    hora_fin: str | None = None


class EvalCap(BaseModel):
    titulo: str
    tipo: Literal["examen", "entrega", "proyecto", "otro"] = "otro"
    fecha: date
    peso: float | None = None


class CursoCap(BaseModel):
    nombre: str
    profesor: str | None = None
    sesiones: list[SesionCap] = Field(default_factory=list)
    evaluaciones: list[EvalCap] = Field(default_factory=list)


class EventoCap(BaseModel):
    titulo: str
    fecha: date
    hora_inicio: str | None = None
    hora_fin: str | None = None


class ApunteCap(BaseModel):
    titulo: str
    contenido: str = ""


class PropuestaCaptura(BaseModel):
    """Lo que el digitalizador extrajo de una captura (Capa 7), para que la app
    lo muestre y el usuario CONFIRME/EDITE antes de crear. Nada se persiste hasta
    que se llama a `/matix/crear-desde-captura` con esta propuesta confirmada."""

    tipo: Literal["tareas", "silabo", "horario", "eventos", "apunte"] = "apunte"
    tareas: list[TareaCap] = Field(default_factory=list)
    cursos: list[CursoCap] = Field(default_factory=list)
    eventos: list[EventoCap] = Field(default_factory=list)
    apunte: ApunteCap | None = None


class DigitalizarRequest(BaseModel):
    """Cuerpo de `/matix/digitalizar-captura` (Cámara · digitalización general).

    Se pasa `texto` (OCR on-device — la imagen se queda en el teléfono) O
    `imagen` (data URL base64, para usar el modelo de VISIÓN barato). UNA llamada
    por captura. No persiste nada — devuelve la propuesta para confirmar."""

    texto: str | None = None
    imagen: str | None = None  # data:image/...;base64,...


class DigitalizarResponse(BaseModel):
    propuesta: PropuestaCaptura


class ItemCreado(BaseModel):
    tipo: str
    id: str | None = None
    titulo: str | None = None


class ItemError(BaseModel):
    tipo: str
    titulo: str | None = None
    mensaje: str


class CrearCapturaRequest(BaseModel):
    """Cuerpo de `/matix/crear-desde-captura`: la propuesta YA confirmada/editada
    por el usuario. Crea cada ítem por los comandos canónicos."""

    propuesta: PropuestaCaptura


class CrearCapturaResponse(BaseModel):
    creados: list[ItemCreado] = Field(default_factory=list)
    errores: list[ItemError] = Field(default_factory=list)
    total: int = 0


class ClasificarCapturaRequest(BaseModel):
    """Cuerpo de `/matix/clasificar-captura` (Cámara inteligente).

    `texto` es el OCR on-device de una foto. SOLO viaja el texto: la
    imagen se quedó en el teléfono. El cerebro decide a qué flujo
    pertenece (tareas, eventos o apunte); no crea nada — la app abre la
    revisión correspondiente y el usuario puede corregir el tipo.
    """

    texto: str = Field(min_length=1)


class ClasificarCapturaResponse(BaseModel):
    """Respuesta de `/matix/clasificar-captura`. `tipo` es el destino
    sugerido. Ante duda, el cerebro responde `apunte` — el catch-all que
    no pierde nada (siempre se puede guardar como nota)."""

    tipo: Literal["tareas", "eventos", "recibo", "apunte"] = "apunte"


class ExtraerReciboRequest(BaseModel):
    """Cuerpo de `/matix/extraer-recibo` (Finanzas-2 · Cámara).

    `texto` es el OCR de un recibo/boleta (ya corregido). SOLO viaja el
    texto: la imagen se quedó en el teléfono. El cerebro propone un gasto;
    no crea nada — la app lo revisa y lo guarda en Finanzas.
    """

    texto: str = Field(min_length=1)


class ReciboPropuesto(BaseModel):
    """El gasto candidato extraído de un recibo. Todo es opcional: si el
    OCR no dio un total claro, `monto` viene `null` y la app deja
    escribirlo a mano (no se inventan cifras). `categoria` es una
    sugerencia que el usuario puede cambiar."""

    monto: float | None = None
    fecha: date | None = None
    comercio: str | None = None
    categoria: str | None = None


class ExtraerReciboResponse(BaseModel):
    """Respuesta de `/matix/extraer-recibo`: un único gasto propuesto."""

    recibo: ReciboPropuesto = Field(default_factory=ReciboPropuesto)


class BloqueOpciones(BaseModel):
    """Bloque interactivo de opciones tocables (estilo Claude).

    Matix lo emite con `preguntar_con_opciones` cuando ofrecer una elección o
    pedir una preferencia ayuda. La app pinta las opciones debajo del mensaje;
    tocar una (o enviar el campo de texto) manda esa respuesta y la
    conversación sigue.

    `tipo`:
    - `seleccion_unica`  → chips; tocar uno responde.
    - `seleccion_multiple` → chips toggle + botón Enviar (responde la lista).
    - `texto` → un campo para escribir (las `opciones` van vacías).
    """

    pregunta: str
    opciones: list[str] = Field(default_factory=list)
    tipo: Literal["seleccion_unica", "seleccion_multiple", "texto"]
    # Regla de oro: el texto libre SIEMPRE está disponible salvo que se apague
    # a propósito. La app muestra un «escribir otra cosa» cuando es true.
    permite_texto: bool = True


class AccionDispositivo(BaseModel):
    """Acción que la APP ejecuta en el teléfono vía un Intent nativo (Capa 6 ·
    Fase 1). El cerebro NO la ejecuta: la PROPONE y la app la dispara tras la
    confirmación del usuario (las que envían/crean siempre se confirman).

    `tipo` discrimina y define qué campos vienen:
    - `mensaje`   → canal (whatsapp|sms|correo), destinatario?, texto, asunto?
    - `llamada`   → numero, nombre?
    - `evento`    → titulo, inicia_en, termina_en?, ubicacion?, descripcion?
    - `abrir`     → objetivo (url|mapa|app), valor
    - `galeria`   → modo (ultima|elegir) — la app toma la foto y la manda al
                    flujo de visión/finanzas que ya existe.
    - `pantalla`  → proposito — la app LEE (solo lectura) la pantalla activa y
                    manda el texto como dato en un turno nuevo (Tier C.0).
    - `whatsapp`  → contacto, mensaje — la app abre el chat, verifica el contacto,
                    escribe y, tras confirmar, envía (Tier C.1, acción blindada).
    - `pc_accion` → accion + args — acción CONSECUENTE en la PC del usuario
                    (Capa 6: mover/renombrar archivos, abrir/cerrar apps, tareas
                    tipadas, acción irreversible de pantalla). La app la confirma
                    con su sheet y la ejecuta vía POST /agente/ejecutar.
                    CUIDADO: si una tool emite un `tipo` que no está en este
                    Literal, la respuesta del chat NO valida y el endpoint
                    devuelve un 500 mudo (fue el bug del caso «abre Spotify»).
                    Hay un test de paridad que recorre los tipos emitidos.
    """

    tipo: Literal[
        "mensaje", "llamada", "evento", "abrir", "galeria", "pantalla",
        "whatsapp", "pc_accion",
    ]
    datos: dict = Field(default_factory=dict)
    # Texto corto para la hoja de confirmación de la app («Abrir WhatsApp para
    # María con este texto…»).
    resumen: str = ""
    # Si la app debe pedir confirmación explícita antes de ejecutar (enviar/crear).
    requiere_confirmacion: bool = True


class ChatResponse(BaseModel):
    """Respuesta del endpoint `/matix/chat`.

    `respuesta` es siempre texto natural para mostrar al usuario.

    `tools_usadas` y `tablas_cambiadas` son metadatos opcionales que
    aparecieron en Capa 2 Paso 2. La app los usa para decidir qué
    providers invalidar tras la respuesta — por ejemplo, si Matix
    creó una tarea, `tablas_cambiadas` incluirá `"tareas"` y el
    Notifier hará `ref.invalidate(tareasProvider)` para refrescar
    la lista al instante.
    """

    respuesta: str
    tools_usadas: list[str] = Field(default_factory=list)
    tablas_cambiadas: list[str] = Field(default_factory=list)
    # Sección a la que la app debe navegar si el usuario lo pidió
    # («llévame a Universidad»). `null` si no hubo navegación.
    navegacion: str | None = None
    # Modo de Matix activo DESPUÉS del turno (tono/conocimiento/prioridades).
    # `null` = modo normal. La app lo usa para el indicador del chat.
    modo_activo: str | None = None
    # Bloque interactivo de opciones tocables (elicitación), o `null`. La app
    # lo pinta debajo del mensaje; tocar una opción la manda como respuesta.
    opciones: BloqueOpciones | None = None
    # Transparencia del modelo: qué modelo (id del catálogo) respondió este
    # turno, y si lo eligió el modo Automático. La app muestra una etiqueta
    # pequeña — sobre todo cuando `auto` — para ver qué se usó.
    modelo_usado: str | None = None
    auto: bool = False
    # Acción a ejecutar en el teléfono (Intent nativo), o `null`. La app la
    # confirma con el usuario y la dispara. Gana la última del turno.
    accion_dispositivo: AccionDispositivo | None = None


class ConteoMuestrasResponse(BaseModel):
    """Cuántas muestras de voz hay guardadas para entrenar el wake word."""

    positivo: int = 0
    negativo: int = 0
    total: int = 0


class MuestraVozResponse(BaseModel):
    """Resultado de subir un clip de voz para el wake word."""

    ok: bool = True
    objeto: str
    conteo: ConteoMuestrasResponse


class NarrarFrameRequest(BaseModel):
    """Un frame muestreado de la cámara en vivo + la narración previa (para no
    repetir). La imagen viaja como data URL (`data:image/jpeg;base64,...`); el
    muestreo y los topes los hace la app (solo llegan frames que pasan el filtro)."""

    imagen: str
    narracion_previa: str | None = None


class NarrarFrameResponse(BaseModel):
    """Narración corta de lo que se ve. Vacía si no hay nada nuevo que narrar."""

    narracion: str = ""
