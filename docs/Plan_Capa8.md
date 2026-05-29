# Plan — Capa 8 reducida: Proactividad

Capa 8 completa = Matix avisa y actúa por iniciativa propia. Eso
incluye recordatorios contextuales, nudges sobre rutinas, detección
de "te olvidaste de X", acciones autónomas (mover una reunión, crear
una tarea derivada de un email).

**Para esta iteración trabajamos solo el briefing matutino.** El
resto del fan-out de proactividad queda para futuras vueltas — no
se construye nada de la maquinaria genérica de "decisiones
proactivas" todavía, porque sin un patrón de uso concreto se vuelve
abstracto rápido.

---

## Alcance reducido

**Sí entra en este paso**:

- Un briefing matutino programable: una vez al día, a la hora que
  el usuario elija, Matix le manda una notificación con el resumen
  del día.
- Al tocar la notificación, se abre una pantalla del briefing con
  el detalle y opción a escucharlo por voz.
- Ajuste de la hora en `Ajustes`.

**NO entra**:

- Briefings en otros momentos (mediodía, antes de dormir).
- Notificaciones contextuales fuera del briefing (recordatorios
  ya los maneja la Capa 1; nudges proactivos vienen después).
- Acciones autónomas (Matix tomando decisiones sin que el usuario
  pregunte).
- Sumarios redactados por LLM. El briefing es texto estructurado.
  Si más adelante queremos "vibra" o redacción más cálida, se suma
  encima con gpt-4o-mini.
- Personalización aprendida (Matix descubriendo qué priorizar
  primero por contexto previo).
- Multi-cuenta o multi-perfil.

---

## Decisiones clave

### 1. Programación: notificación local en la app, no scheduler en el cerebro

Dos caminos posibles:

- **Scheduler en el cerebro** (APScheduler / Railway cron):
  precomputa el briefing a una hora fija y lo guarda en una tabla,
  o lo manda como push (FCM) directamente al teléfono. Pros:
  el contenido está listo en la noti. Contras: nueva infra (cron
  + tabla `briefings_diarios` + manejo de zona horaria del usuario
  en el servidor + Railway free puede dormir y arruinar el job).

- **Notificación local en la app** (`flutter_local_notifications`
  · `programarDiaria`): el sistema Android dispara la noti aunque
  la app esté cerrada o el teléfono se haya reiniciado. Pros:
  cero infra nueva, zona horaria es la del teléfono (siempre
  correcta), funciona offline. Contras: el contenido se busca on
  demand al tocar la noti — si no hay red, la pantalla muestra
  "sin conexión".

**Decisión: local con compute-on-demand**. `NotificacionesService`
ya tiene `programarDiaria(id, titulo, cuerpo, hora, minuto)` desde
Capa 1; reusamos. El cuerpo de la noti es genérico ("Tu briefing
de hoy"); el contenido real se trae al tocar.

Trade-off documentado: si tocás la notificación a las 8:01 AM en
el subte sin señal, la pantalla muestra retry. La gran mayoría de
mañanas el usuario tiene WiFi de casa al despertarse, así que vale.

### 2. Contenido del briefing

Texto estructurado en secciones, sin LLM:

- **Encabezado**: día + fecha + saludo simple.
- **Eventos de hoy**: lista hora-título-ubicación, en orden cronológico.
  Sale del Calendar del hub (incluye los de Google sincronizados).
- **Tareas que vencen hoy**: lista título-prioridad-curso/proyecto.
- **Tareas vencidas**: resumen ("Tenés N tareas vencidas — la más
  antigua hace D días") sin desglosar las 20, para no abrumar.
- **Alertas / riesgos**:
  - Proyectos activos con ≥3 días sin avance.
  - Choques de horario en la agenda de hoy.
  - (Más adelante: tareas alta prioridad sin tocar, evaluaciones
    en <72h sin material asociado, etc.)

Si todo está limpio (sin tareas, sin eventos, sin alertas), el
briefing dice "Hoy tenés la agenda libre" y listo. Sin forzar
contenido.

### 3. Entrega

- **Notificación local**: título `🌅 Briefing de hoy`, cuerpo
  con el conteo (`3 eventos · 5 tareas · 2 alertas`). Sale a la
  hora configurada, todos los días (`DateTimeComponents.time`).
- **Al tocar**: abre `BriefingScreen` que GET `/api/v1/briefing/hoy`
  y pinta las tarjetas de cada sección. Es la pantalla que el
  usuario abre también desde un futuro botón "Briefing" en Inicio
  (no en este paso, pero el endpoint queda listo).
- **Botón "Escuchar"**: usa el endpoint TTS de Matix (Capa 2,
  voz onyx de OpenAI) sobre `texto_para_voz` que el endpoint del
  briefing devuelve ya armado en prosa natural.

### 4. Configuración (Ajustes)

Nueva sección "Briefing matutino" con:

- **Switch** "Activar briefing matutino" — default off (opt-in,
  para no sorprender al usuario tras una actualización).
- **Time picker** "Hora del briefing" — default 08:00.
- Texto pequeño: "Te mando una notificación a esta hora con tu
  resumen del día."

Persistencia en `SharedPreferences`:

- `briefing_activo: bool` (default false)
- `briefing_hora: int` (default 8)
- `briefing_minuto: int` (default 0)

Cuando el usuario cambia algo:

- Si pasó a activo y antes estaba off: pedir permiso de
  notificación (ya está el helper en `NotificacionesService`) y
  `programarDiaria` con un id fijo (`_idBriefing = 8000001`).
- Si pasó a off: `cancelar(_idBriefing)`.
- Si cambia la hora estando activo: `cancelar` + `programarDiaria`
  con el nuevo horario.

En el `main` de la app, al arrancar: si `briefing_activo`,
reprogramar (idempotente — sobrescribe la pendiente). Esto cubre
los casos "el sistema reseteó las notis" y "actualicé la app y la
pendiente perdió el horario".

### 5. Endpoint del cerebro

`GET /api/v1/briefing/hoy` devuelve:

```json
{
  "fecha": "2026-05-29",
  "dia_semana": "viernes",
  "saludo": "Buenos días",
  "eventos": [
    {"hora": "09:00", "titulo": "Clase de Sistemas", "ubicacion": null, "es_de_google": false}
  ],
  "tareas_hoy": [
    {"titulo": "Entrega del TP3", "prioridad": "alta", "contexto": "Sistemas"}
  ],
  "tareas_vencidas": {
    "total": 3,
    "mas_antigua_dias": 5
  },
  "alertas": [
    {"tipo": "proyecto_estancado", "mensaje": "Tesis sin avance hace 4 días"}
  ],
  "resumen_corto": "3 eventos · 5 tareas · 2 alertas",
  "texto_para_voz": "Buenos días. Hoy tenés tres eventos: a las 9..."
}
```

`resumen_corto` lo usa la app para armar el `body` de la
notificación. `texto_para_voz` se manda al endpoint TTS si el
usuario toca "Escuchar".

El endpoint reusa la lógica de `cerebro/app/matix/contexto.py`
extraída a un nuevo módulo `cerebro/app/briefing/armar.py` que
devuelve un dict estructurado en vez del markdown que va al
system prompt de Matix.

---

## Paso 2 — Cierre del día automático

Hermano nocturno del briefing. Mientras el briefing prepara la
mañana, el cierre cierra la noche: un repaso amable de lo que pasó.

### Alcance

- Notificación local a una hora configurable (sugerencia: **21:00**),
  con el mismo mecanismo que el briefing (`programarDiaria`, id de
  notificación distinto `8000002`, payload `'cierre'`).
- Al tocarla, abre `CierreScreen` con el repaso + botón "Escuchar"
  (mismo TTS onyx).
- Ajuste de la hora en Ajustes, en una sección propia justo debajo
  del briefing.

### Contenido y tono

**El tono es de cierre, no de exigencia.** No es una lista de deberes
que generan culpa. Lo que quedó sin hacer se enmarca como "mañana
seguís", nunca como "te falta". Secciones:

- **Lo que hiciste hoy** (`hechas`): tareas completadas hoy — lo
  logrado, para reconocerlo.
- **Quedó para después** (`pendientes_hoy`): tareas que vencían hoy
  y no se completaron, presentadas sin dramatismo.
- **Mañana** (`tareas_manana` + `eventos_manana`): qué viene, para
  soltar el día sabiendo que está anotado.
- **Frase para soltar** (`cierre_frase`): una línea final adaptada
  al volumen del día. Si cerraste todo → celebra y a descansar; si
  quedó mucho → "mañana con la cabeza fresca"; si no marcaste nada →
  "está perfecto, mañana es otra oportunidad".

Sin LLM, igual que el briefing — texto estructurado, predecible,
$0/noche. La frase de cierre se elige de un set de plantillas según
`(n_hechas, n_pendientes)`.

### Endpoint

`GET /api/v1/briefing/cierre` → `CierreHoyRead`. Vive en el mismo
router de proactividad que el briefing. Reusa los helpers de
zona horaria y formato de `cerebro/app/briefing/armar.py` desde
`cerebro/app/briefing/cierre.py`.

`completada_en` lo setea la app al togglear una tarea (no hay
trigger en BD); el cierre lo usa para saber qué se completó **hoy**.

---

## Paso 3 — Nudges de deadlines (event-driven) · mapeo

Los dos primeros pasos son **time-driven** (disparan a una hora
fija). El Paso 3 introduce nudges **event-driven**: avisos que
disparan por proximidad a un deadline, no por el reloj de pared.

### Idea

Cuando una entrega/examen/tarea de alta prioridad se acerca (ej.
48h, 24h, 3h antes), Matix avisa una vez — sin esperar al briefing
de la mañana siguiente, que podría llegar tarde.

### Decisión pendiente (a resolver al arrancar el paso)

El mecanismo de disparo es la pregunta central:

- **Opción A — notificaciones locales pre-programadas**: cuando se
  crea/edita una tarea o evento con `vence_en`/`inicia_en`, la app
  programa notificaciones en los offsets (T-48h, T-24h, T-3h). Cero
  backend, funciona offline, pero la lógica de "qué amerita nudge"
  vive en la app y hay que reconciliar al editar/borrar. Es una
  extensión del sistema de recordatorios de Capa 1.
- **Opción B — scheduler en el cerebro**: un job recurrente (cron de
  Railway o APScheduler) que barre deadlines próximos y manda push
  (requiere FCM, que sacamos en Capa 2 infra). Centraliza la lógica
  de riesgo pero reintroduce infra de push y depende de que el
  cerebro esté despierto.

Inclinación inicial: **Opción A**, coherente con la decisión del
Paso 1 (notificación local sobre scheduler) y con el sistema de
`recordar_en` que ya existe. Pero la decisión se confirma al
arrancar el paso, no antes.

### Qué amerita un nudge (borrador)

- Evaluaciones (examen/entrega) en <48h sin material/apunte asociado.
- Tareas de prioridad alta que vencen en <24h y no se tocaron.
- Eventos con `recordar_en` explícito (ya cubierto por Capa 1; el
  Paso 3 suma los implícitos por proximidad).

Anti-spam: máximo un nudge por entidad por offset; si el usuario ya
completó/pospuso, no insiste.

---

## Pasos futuros (fuera de alcance todavía)

- **Paso 4 — Acciones autónomas**: con confianza alta, Matix mueve
  cosas (reprograma, sube prioridad, agenda study session) y avisa
  después. Siempre con undo en un toque.
- **Paso 5 — Síntesis con LLM**: briefing y cierre pasan por
  gpt-4o-mini para redacción más natural y adaptada al volumen.

Cada uno se decide después de vivir con el anterior un tiempo.
