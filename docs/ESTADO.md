# Estado de Matix

> **ESTADO: Matix 1.0 — TERMINADA (8 de junio de 2026).**
> Tag de versión: `v1.0.0`. La rama `main` queda en modo mantenimiento de la
> 1.0 hasta arrancar formalmente la 2.0.

## Estado real por capa (gana el código)

| Capa | Estado | Evidencia |
|---|---|---|
| 1 — Armazón del hub | HECHA | migr. 0001+, `home_shell`, CRUD completo, notis locales |
| 2 — Chat/voz | HECHA | `matix/chat.py`, 128 tools, Whisper, manos libres, wake word |
| 3 — Memoria/RAG | HECHA | migr. 0048 `recuerdos` (RAG unificado auto-recuperado), tutor |
| 4 — Google | PARCIAL | OAuth (0007), `routers/google.py`, Calendar con sync manual |
| 5 — Casa (Home Assistant) | Fuera del repo | stack Docker local (homeassistant/whisper/piper) |
| 6 — PC/archivos | HECHA hasta 6.3 | `agente_pc/` funcional + tools `pc_*` + control de pantalla |
| 7 — Visión | HECHA | cámara en vivo + `/matix/digitalizar-captura` |
| 8 — Proactividad | Base HECHA | `matix/proactividad.py` con detectores de riesgo |

Última migración aplicada en prod: `0048_recuerdos.sql` (próxima: `0049_*`).
Migraciones 0038-0048 confirmadas aplicadas en prod.

Bitácora viva del proyecto. Si la sesión se reinicia, lee primero
`CLAUDE.md`, después `docs/Mapa_del_Hub.md`, después
`docs/Plan_Capa1.md` y por último este archivo para saber dónde
estamos.

Convención: el paso "en curso" tiene `→`, los terminados `✓`, los
pendientes `·`.

---

## Criterio de "Matix 1.0 terminada"

1. ✓ Capas 1-3 (hub, chat y voz, memoria/tutor) funcionan sólidas a diario.
2. ✓ El horario automático arma el día, replanifica, y se confía en él.
3. ✓ El acceso agéntico al teléfono (C.2) hace los flujos seguros habituales.
4. ✓ Resiliencia de proveedores: si uno cae, Matix sigue funcionando.
5. ✓ Usado como sistema principal 7 días seguidos sin romperse nada crítico.

Fuera de 1.0 (post-1.0 / 2.0): agente PC completo, casa inteligente,
Google sync completo, cámara avanzada, proactividad plena, capa de
comandos unificada, voz con ElevenLabs.

---

## Qué entregó 1.0

Superficie que quedó viva y se usa a diario:

- **Hub completo**: Inicio (presencia Matix, robot, "Tu día", widgets),
  Tareas (con prioridad, fechas, subtareas, papelera), Calendario (mensual +
  lista del día, eventos fijos y recurrentes, asistencia con confirmación),
  Universidad (cursos, entregas, exámenes, calificaciones, sesiones de clase,
  evaluaciones), Apuntes (etiquetas, búsqueda, conversión a tareas), Proyectos
  (con árbol, fase actual, capacidad estimada y modalidad), Finanzas básicas
  (movimientos, categorías, consultas), y la búsqueda global desde Inicio.
- **Chat + voz con Matix**: chat persistente con historial, modo voz manos
  libres, wake word entrenado por el usuario, transcripción Whisper, captura
  rápida desde Inicio (tarea o apunte en un toque). **Voz UNIFICADA**: una
  sola voz del dispositivo (flutter_tts) en TODOS los puntos (chat, manos
  libres, cámara, briefing, cierre), config centralizada en `VozConfig`/
  `VozPrefs` (voz/tono/velocidad) que todos aplican; ajuste "Voz de Matix" en
  Ajustes (elige voz es, sliders, probar, ayuda voces Google). El cloud
  (OpenAI tts-1) es solo ÚLTIMO recurso; ElevenLabs fuera por defecto.
- **Memoria + RAG + modo tutor**: memoria personal de Matix (lo que sabe del
  usuario), RAG sobre apuntes y biblioteca de material por skill/bloque
  (calistenia, inglés con bloques 1-6 ingeridos, etc.), recall semántico del
  historial, modo tutor que explica y genera práctica.
- **Horario automático**: plan del día determinístico que coloca tareas en
  ventanas libres reales, respeta anclas, buffer de transición tras
  compromisos fuera de casa, replanificación desde "me acabo de levantar",
  rollover de lo aceptado-no-hecho, apartado de huecos libres con sugerencia
  dosificada.
- **Acceso agéntico al teléfono (C.2)**: enviar mensaje (WhatsApp/SMS/correo),
  iniciar llamada, crear evento del teléfono, abrir app/URL/mapa, leer la
  galería, leer la pantalla — todos con confirmación previa cuando es
  irreversible.
- **Resiliencia de proveedores**: failover OpenAI ↔ Anthropic para chat,
  visión y JSON; cadena de respaldo de TTS (ElevenLabs/OpenAI cloud → voz
  nativa); embeddings degrada a sin-RAG si falla; cámara con reintentos y
  timeout agresivo.
- **Cámara en vivo con narración**: muestreo de frames, narración corta del
  modelo, voz device-first del Honor con fallback a cloud.
- **Notificaciones de accountability + proactivas**: rendición de cuentas y
  nudges de plazos con dial de intensidad (suave/medio/intenso/máximo),
  asistencia a eventos fuera de casa, recordatorios pre-actividad (lead
  ~15 min), resumen matutino, nudges del próximo bloque, programadas con el
  AlarmManager nativo (sobreviven a MagicOS sin depender del receiver del
  plugin), respetando quiet hours y dedup.
- **Widgets de pantalla de inicio (Android)**: lista del día y "lo siguiente",
  semántica de colores, push on-change y al cambiar día.
- **Robot companion**: presencia de Matix en Inicio + burbuja flotante;
  acción siguiente tocable; despedida nocturna.
- **Base del agente PC (Capa 6 — Fase 1)**: agente local en la PC,
  autotest de conexión, listar/leer/mover/renombrar archivos, organizar
  carpeta, resumir documento — con confirmación para acciones destructivas.

Bajo la línea: cerebro y app con tests verdes, CI bloqueante (analyze + tests
+ APK release), instrumentación de latencia por turno (clasificador rápido
pre-LLM + tools en paralelo + prompt caching en ambos proveedores), backups
deterministas, y migraciones siempre aplicadas vía helper.

---

## Siguiente capítulo: 2.0

El norte de la 2.0 vive en [`docs/Matix_2.0_Norte_Capa_de_Comandos.md`](Matix_2.0_Norte_Capa_de_Comandos.md).

Capa 7 (digitalización por cámara) — sobre la capa de comandos: HECHO. Generaliza
el OCR de sílabo a cualquier documento/pizarra y crea por los comandos canónicos.
`llm.extraer_documento_json` clasifica (tareas/sílabo/horario/eventos/apunte) y
estructura en UNA sola llamada al modelo barato (gpt-4o-mini, modo JSON), por
texto (OCR on-device — la imagen se queda en el teléfono) o por imagen (pipeline
de visión barato con failover); solo digitaliza lo escrito, no inventa.
`POST /matix/digitalizar-captura` propone (no persiste). La creación de lo
CONFIRMADO va por `digitalizacion.crear_desde_captura` → cada ítem por su comando
canónico (crear_tarea / crear_curso + crear_sesion_clase + crear_evaluacion con
el curso_id enlazado / crear_evento; apunte por insert+índice, gap de comando de
apuntes), expuesta en `POST /matix/crear-desde-captura` (solo tras confirmar).
Extracción y creación son endpoints separados = gate de confirmación. Lo nativo
(captura + OCR on-device + pantallas de revisión de la app) no corre en tests.

Capa 8 (proactividad) — detección anticipada de riesgo + intervención dosificada:
HECHO. El motor `cerebro/app/matix/proactividad.py` (ya existente, con toda la
dosificación: niveles con tope diario, baja-el-tono-si-se-ignora, dedup por tema
en `proactividad_enviados`, silencio/ventana vía `permitido_ahora`, un aviso a la
vez) se EXTENDIÓ con los detectores de riesgo, deterministas y sin LLM en el
trigger: día sobrecargado (el planificador recortó trabajo), proyecto estancado
en la banda temprana [3,5) días (el aviso sostenido a 5+ lo sigue dando el motor
de evolución, no se pisan), evaluación próxima (1..7 días) sin estudio agendado,
y skill activa sin práctica ≥7 días (toque ligero). Cada uno surfacea por el push
existente con acción de un toque (deep-link rollover / proyecto / hoy). Corre en
el tick del scheduler que ya existía. Lo nativo (FCM + scheduling local de la
app) no corre en tests; la lógica determinista (detectores, dosificación,
selección) sí está cubierta con FakeDB.

Avance — Fase 1 (cimiento de la capa de comandos): HECHO. Existe un registro
tipado de comandos (`cerebro/app/comandos/`): cada comando declara nombre,
params, riesgo (segura/consecuente/prohibida) y UN handler único, con logging
por invocación. El comando es la única fuente de lógica; el endpoint de la app
(UI) y la tool de la IA son envoltorios delgados sobre el MISMO handler — una
sola ruta canónica. Tareas migrado como piloto (crear/lote/editar/completar/
reabrir/eliminar/restaurar). Consolidó dos bugs reales: D1 (la captura rápida
crea siempre Tarea, nunca Evento) y D5 (completar por checkbox, por comando o
por el bloque de Tu día deja el mismo estado, con repetición y sync de árbol).

Avance — Fase 2 (Universidad): HECHO. La sección Universidad entera pasó al
registro con el mismo patrón. Comandos en `comandos/universidad.py`: cursos
(crear/editar/eliminar/consultar), sesiones de clase (crear, crear_sesiones_
clase recurrente, editar/eliminar/consultar) y evaluaciones (crear/editar/
eliminar/consultar con filtro por curso y rango de fechas). Los routers
`cursos`/`evaluaciones`/`sesiones_clase` quedaron como envoltorios (POST/PATCH/
DELETE → comando; GET de lectura directos). Hito de capacidad: la IA ahora VE
Universidad — 13 tools nuevas (antes la sección era invisible para Matix), así
responde «¿qué cursos llevo?» o «¿qué evaluaciones tengo esta semana?». La
recurrencia de clases NO usó G5: una clase «lunes y miércoles» es N filas de
sesiones (una por día), el modelo existente; la recurrencia general de
`crear_evento` queda para Fase 3 (Calendario). Helper comando→HTTP extraído a
`comandos/http.py`, compartido por los 4 routers. Borrados de Universidad son
duros → la IA pide confirmación.

Avance — Fase 3 (Calendario / Eventos): HECHO. Eventos migrado al registro:
crear/editar/eliminar/restaurar/consultar como comandos (`comandos/eventos.py`),
con el endpoint de la app y la tool de la IA envolviendo el MISMO handler. Se
creó el motor de recurrencia ÚNICO (`comandos/recurrencia.py`): una sola fuente
de verdad para "esto se repite". `horario` lo importa y re-exporta (compat);
las sesiones de clase (Universidad) y los eventos semanales miden el día con la
misma vara, así la recurrencia de clases que la Fase 2 dejó pendiente de G5
quedó reconciliada. Recurrencia general (G5): diaria/semanal(días)/mensual +
fin nunca/hasta/conteo, con editar/borrar recurrente en los tres alcances
estilo Google Calendar (toda_serie / solo_esta / esta_y_futuras); "solo_esta"
usa la columna nueva `recurrencia_excepciones` (migración 0046, aditiva).
Consolidó D4: formulario manual, OCR de sílabo e IA crean por `crear_evento` —
una sola ruta con acceso a recurrencia; el router conserva la orquestación de
Google Calendar sobre el comando.

Avance — Fase 4 (Proyectos): HECHO. Proyectos migrado al registro
(`comandos/proyectos.py`): crear/editar/aparcar/terminar/reactivar/eliminar/
consultar como comandos con handler único; el endpoint de la app y la tool de
la IA envuelven el MISMO handler. Consolidó la lógica que estaba duplicada
entre el router y las tools (tope de 3 activos, prioridad única, coherencia de
la acción siguiente, `inactivo_desde`, tope blando de skills) en una sola
fuente. Acción siguiente (G9): nuevo `definir_accion_siguiente` para DEFINIR o
CAMBIAR la acción siguiente desde la IA (antes solo se marcaba hecha o se
cambiaba por el PATCH del router); `marcar_accion_siguiente_hecha` migrado.
Resto de D5: nuevo `completar_avance_proyecto` cierra un nodo del árbol por
cualquier camino (UI, IA, o el bloque agendado de Tu día) — el camino del
bloque pasaba por un update directo y ahora enruta al comando, que refresca la
actividad del proyecto, así el % y el motor de evolución quedan consistentes.
El motor de evolución sigue intacto: el % se deriva de los estados de los nodos
y la suite de árbol/intake sigue delegando a sus módulos (no se reescribió).

Avance — Fase 5 (Planificador / Tu día): HECHO. El subsistema más
interconectado (set del día, plan en ventanas, rollover, despertar, bloques)
migrado al registro (`comandos/planificador.py`): 12 comandos, todos
ENVOLTORIOS DELGADOS sobre las funciones deterministas que ya existían en
`matix.horario`/`planificador_diario`/`rollover`. UI/robot e IA invocan el mismo
handler. Determinismo preservado (no negociable): los handlers no importan ni
llaman al LLM (módulos `matix` importados perezosamente); la IA solo elige qué
comando llamar, el trabajo (huecos, colocación, rundown del despertar, rollover)
lo hace el motor determinista — hay un test-bomba que revienta si algún camino
del bucle tocara el modelo. D3 consolidado: «agregar al día» tiene una sola ruta
canónica vía `agendar_bloque` (UI POST /horario/agendar e IA entran por el mismo
comando; sigue creando Tarea con bloque, nunca Evento pelado). D5/Fase 4
reconciliado: `completar_bloque` enruta a `completar_tarea` y
`completar_avance_proyecto`. La IA ahora maneja el bucle completo (6 tools
nuevas: despertar, agendar, saltar/completar bloque, proponer/aplicar rollover).
El contrato de /rollover/decidir se preservó (sin_hueco/no_existe siguen siendo
200, no error).

Auditoría de la capa de comandos (post-Fase 5): HECHA. Revisión exhaustiva
multi-agente (9 dimensiones + verificación adversarial por hallazgo): 22
hallazgos, 9 confirmados reales, 6 arreglados + limpieza (los 13 restantes,
falsos positivos). Correcciones: mapeo HTTP de tipos de error que faltaban
(no_soportado/sin_accion_siguiente/inconsistencia → 422); /horario/replanificar
volvió a respetar el `ahora` del body; la tool de rollover traduce sus flags a
error tipado para el LLM (el endpoint REST mantiene el dict crudo 200); marcar
acción siguiente propaga el error si completar_tarea falla; guard de ancla
inválida en los splits recurrentes de eventos; imports muertos limpiados.

Siguiente: Apuntes, Finanzas y Ajustes (marginales) si se quisieran; gate de
confirmación de acciones consecuentes (anotado desde Fase 1) — el cimiento de
riesgo por comando ya está puesto en las 5 fases.

Parqueado para 2.0 (no entra en 1.0):

- Agente PC completo y Capa 6 restante (ejecutar comandos, control real más
  allá de archivos, integración con apps de escritorio).
- Voz premium con ElevenLabs (la cadena ya soporta el respaldo; falta la
  voz pinneada del usuario).
- Google sync completo (Calendar, Tasks, Mail vía MCP).
- Casa inteligente (Home Assistant).
- Cámara avanzada (más allá de la narración en vivo: visión continua, modo
  estudiar-conmigo, reconocimiento de pizarras).
- Proactividad plena (Matix actuando por iniciativa propia, no solo
  reaccionando).
- Tier B de acceso al teléfono (acciones más sensibles y compuestas).
- Logimatix / Peyo (las dos extensiones de Matix para los flujos de la empresa
  y la familia).

---

## INVENTARIO — qué tiene Matix HOY (leído del repo · 2026-06-04)

Foto honesta del estado real, sacada del código (no de memoria). Marcas:
COMPLETO (backend + UI usable) · PARCIAL (a medias o solo por chat) ·
SOLO-BACKEND (existe en el cerebro, sin pantalla propia en la app).

### Confirmaciones rápidas (para zanjar dudas)

- Búsqueda web / internet: SÍ existe. Tool `buscar_web` vía Tavily
  (`cerebro/app/matix/busqueda_web.py`, key en `TAVILY_API_KEY`). El modelo
  sintetiza con su voz y cita fuentes.
- Wake word "oye Matix": SÍ existe. Modelo `oye_matix.onnx` (~214 KB) en la
  raíz, endpoints `/matix/wakeword/muestras*`, pantalla `entrenar_voz_screen`.
- Cámara en vivo: SÍ (desde 2026-06-04). Sesión en vivo con narración continua
  por muestreo inteligente (frame cada ~3 s + cambio de escena; topes de
  frames/min, duración y auto-stop). Frame → gpt-4o-mini (detail=low) → frase
  corta → TTS onyx. Endpoint `/matix/narrar-frame`; muestreo y topes en la app
  (`features/live_camara`). Además sigue la visión por FOTO/galería (recibos,
  pizarras, documentos) → OCR/extracción. No promete tiempo real frame-perfect.
  Ritmo en vivo (2026-06-07): loop de captura y visión DESACOPLADOS — la captura
  deja el frame más fresco que pasó el muestreo (ÚLTIMO GANA, sin cola) y la
  visión procesa una sola petición a la vez tomando siempre el más reciente; el
  TTS es interrumpible (época: una descarga superada no suena → sin audio viejo
  acumulado); timeout agresivo por proveedor (~3.5 s) con failover rápido, y se
  respeta el proveedor pinneado (si está en Claude, no intenta OpenAI).
  Indicador honesto "mirando…" mientras la visión piensa. Topes de costo y
  auto-stop intactos.
- Teléfono Tier B: NO. Solo hay Fase 1 (intents), Tier C.0 (leer pantalla, solo
  lectura) y Tier C.1 (enviar WhatsApp tras confirmación). No hay automatización
  libre de tocar/escribir en apps arbitrarias.

### Cerebro — proveedores (RESILIENCIA multi-proveedor)

- Chat/razonamiento/JSON: OpenAI o Anthropic con **failover real**. Si el
  proveedor preferido cae por error transitorio (timeout/5xx/429) **o por
  auth/crédito agotado (401/403/insufficient_quota)**, reintenta UNA vez con el
  modelo comparable del OTRO proveedor. Aislado en `matix/llm.py`.
- **Proveedor preferido** (`config_matix.proveedor_preferido`: openai /
  anthropic / auto, default auto): a cuál apuntar primero; el failover cae al
  otro. Editable desde Ajustes → Modelo. GET/POST `/api/v1/modelos[/proveedor]`.
- Visión (cámara/imágenes): por la MISMA abstracción → gpt-4o-mini o Claude
  (ambos ven imágenes), con failover. La cámara revive aunque OpenAI no esté.
- TTS (texto→voz): voz UNIFICADA del DISPOSITIVO (flutter_tts) como la voz de
  Matix en toda la app; **cadena device-first**: voz del dispositivo → (último
  recurso) OpenAI tts-1 vía `/matix/voz` → texto. ElevenLabs FUERA por defecto
  (gate `tts_elevenlabs_activo`, código conservado). Config centralizada en la
  app (`VozConfig`/`VozPrefs`): misma voz/tono/velocidad en chat, manos libres,
  cámara, briefing y cierre; ajuste "Voz de Matix" en Ajustes.
- STT (voz→texto): Whisper (`whisper-1`, "es") + filtro de alucinaciones;
  **respaldo NATIVO** de Android (`speech_to_text`) cuando Whisper no responde.
- Embeddings (RAG): OpenAI `text-embedding-3-small`. Degradan elegante: sin
  crédito, la búsqueda RAG/recall vuelve vacía (el chat NO se cae) y la ingesta
  responde honesto ("ingesta en pausa: sin crédito de embeddings").

### Memoria UNIFICADA de la vida del usuario — RAG auto-recuperado (Capa 3)

**Causa raíz que cierra:** hasta hoy TODO el recall era por herramienta (el
modelo decidía si llamar `buscar_apuntes`/`buscar_memoria`/`buscar_en_historial`)
→ a menudo NO lo hacía y "Matix no recordaba la vida"; y tareas/proyectos/
universidad no tenían NINGÚN embedding. Ahora hay una tienda semántica ÚNICA,
`recuerdos` (migración `0048`), que el chat recupera **SOLO, automático, cada
turno** e inyecta como contexto — sin depender de que el modelo decida buscar.

- **Tabla `recuerdos`** (`fuente_tipo` ∈ tarea/nota/proyecto/universidad/chat,
  `fuente_id`, `contenido`, `contenido_hash`, `embedding vector(1536)`, `fecha`,
  `metadata`, UNIQUE(tipo,id)). HNSW coseno; RLS sin políticas (solo service
  role). RPC `buscar_recuerdos(query_embedding, match_count, tipos[])`.
- **Ingesta incremental** (`cerebro/app/matix/recuerdos.py`): `indexar` salta el
  re-embeber si el `contenido_hash` no cambió (sin re-embeber cada edición);
  best-effort (si OpenAI cae, guarda sin vector y reintenta luego). Hooks en UN
  punto: `comandos/registro.ejecutar` llama `recuerdos.hook_comando` tras cada
  comando OK (UI + IA convergen) → indexa/olvida tareas, proyectos, universidad
  (cursos/evaluaciones/eventos, enriquecidos con el nombre del curso); las notas
  se enganchan en el router de apuntes (índice doble: `apunte_chunks` para la
  tool + `recuerdos` para el recall). `sesiones_clase` se omite a propósito
  (franjas recurrentes, ruido). Borrar → olvida; restaurar nota → re-indexa.
- **Recuperación AUTOMÁTICA** (`chat.py::_recall_automatico`): embebe el mensaje
  UNA vez por turno y trae, en paralelo, los recuerdos del hub (`recuerdos`) +
  el recall de conversaciones pasadas (`memoria_conversacional`, reusando el
  embedding) — inyecta un bloque MEMORIA con dos secciones. Acotado (top-K 6+3)
  y con UMBRAL de distancia (0.75: descarta matches flojos → no mete ruido). Si
  no hay nada relevante o no hay crédito, no inyecta y el chat sigue igual. Solo
  en la ruta normal (la ruta rápida sin-LLM no lo necesita).
- **Backfill**: `cerebro/scripts/backfill_recuerdos.py` (idempotente por hash;
  omite lo borrado). Corrido en prod: 70 entidades reales indexadas
  (26 tareas, 9 proyectos, 7 cursos, 3 evaluaciones, 25 eventos).
- **Validado**: "¿qué tenía pendiente de OneXotic?" recupera el proyecto +
  tareas reales; A/B confirma que la respuesta pasa de "no tengo acceso a tus
  datos" (sin memoria) a la lista real de pendientes (con memoria).

### Endurecimiento por auditoría adversarial (app/cerebro/agente)

Auditoría multi-agente (10 dimensiones × verificación adversarial, 54 hallazgos
confirmados, 0 críticos). Arreglado lo seguro y claro: (1) **errores tragados**
— `.json()` de Spotify/secretos ahora captura `ValueError` (un 200 con cuerpo
malformado degradaba lanzando JSONDecodeError sin avisar); persistencia del
turno de chat loguea su fallo; el latido del WS del agente y el guard de
instancia del daemon dejan rastro; las tareas del agente loguean el traceback
real. (2) **WS del agente robusto**: si falla el transporte al responder,
re-lanza para reconectar; si falla serializar, manda un error estructurado al
cerebro (nunca lo deja colgado esperando). (3) **Riel de pantalla FAIL-CLOSED**:
si conocía la ventana objetivo pero no puede leer el foco actual, ABORTA en vez
de teclear a ciegas (`ventana_indeterminada`). (4) **Higiene**: el callback de
Spotify ya no renderiza el detalle de la excepción al navegador (solo loguea) ni
usa emojis. Confirmado por la auditoría que SIGUEN sólidos: denylist (gana sobre
allowlist), sin ejecución de shell, credenciales nunca logueadas, `.env`
gitignored y no versionado, anti-inyección en documentos/visión/recuerdos.
Pendientes de DECISIÓN del dueño (no tocados): ver cierre del prompt.
- Observabilidad: el medidor de costos etiqueta proveedor (`por_proveedor`); el
  chat surfacea `failover`/`modelo_usado` (la app muestra "respondiendo con …").
- Búsqueda web: Tavily. Push: Firebase Cloud Messaging (FCM).

### Optimización de tokens / determinismo (palancas estructurales)

- **Flujos deterministas (cero LLM, cero tokens):** rollover (propuesta +
  aceptar/otro-día/lo-suelto), ventanas libres, briefing matutino, cierre del
  día, hitos, contenido de TODAS las notificaciones (incl. rendición de
  cuentas), set/sugerencias del día. El juicio del modelo se mantiene SOLO en:
  chat, intake de proyecto, visión, resumen de documentos, extracción de OCR,
  repaso semanal, y la desambiguación de proactividad (tie-break raro). Un test
  estático (`test_audit_determinista`) enforza que los deterministas no llamen
  al modelo (gate rojo si alguien mete un LLM ahí).
- **Filtrado de tools por turno** (`seleccion_tools.py`): el chat manda solo un
  CORE (~37) + grupos disparados por keyword en vez de las 93 — ~50% menos
  tokens de tools en turnos comunes, sin perder potencia (mensaje largo/ambiguo
  o modo pesado → todas; salvaguarda nunca cae bajo el CORE).
- **Prompt caching:** system ya se cachea en Anthropic; ahora las TOOLS también
  (`cache_control` en la última). OpenAI auto-cachea por prefijo estable.
- **Routing a barato por defecto** (enrutador, modo auto) + recorte de historial
  por turno (`_MAX_HISTORIAL_MENSAJES`) + RAG top-k=5 (verificado razonable).
- **Notis proactivas programadas** (`notis_programadas.py` + endpoint
  `/horario/notis-programadas` + `NotisProactivasService` en app): el cerebro
  arma la lista determinista (resumen matutino + pre-actividad por cada bloque
  con lead default 15 min + nudges del próximo bloque dosificados por dial
  suave/medio/intenso/maximo). La app las mete al scheduler local con
  `flutter_local_notifications.zonedSchedule` → las dispara el AlarmManager
  nativo aunque la app esté dormida (robusto contra MagicOS sin depender del
  receiver del plugin). Respeta quiet hours, dedup por dedup_key estable
  (re-pedir cancela las anteriores y reprograma; cero duplicados). Triggers:
  tras "me acabo de levantar", tras agendar bloques, on-resume throttled 10 min.
  Cero LLM, cero FCM, cero tokens.
- **Clasificador rápido pre-LLM** (`clasificador_rapido.py`): para casos
  LIMPIOS — saludos ("hola", "gracias"), "anota: X" sin verbo-de-acción ni
  fecha, "crea tarea X" / "recuérdame X" sin fecha — el chat se SALTA el LLM
  entero y ejecuta la tool directo (o responde plantilla). De ~2s a ~50ms en
  los inputs más comunes. Defensivo: ante la mínima ambigüedad (fecha,
  imagen/documento adjunto, modo pesado, contenido extra), cae al camino LLM.
- **Tool calls en paralelo** dentro de una vuelta del loop (`asyncio.gather`):
  si el modelo pide `consultar_tareas` + `consultar_eventos` en una respuesta,
  ahora arrancan juntos en vez de en serie — el tiempo de esa vuelta cae a la
  tool más lenta, no a la suma. Antes sumaba round-trips a la BD.
- **Latencia instrumentada por etapa** (`chat.py:_Cronometro`): cada turno emite
  un log estructurado `contexto=Xms llm=Yms tools=Zms persistir=Wms total=…
  modelo=… vueltas=…`. Permite diagnosticar dónde se va el tiempo sin adivinar.
- **Robot instantáneo:** la burbuja de rollover y posponer/reprogramar son
  update OPTIMISTA (instant al tocar) + operación de BD en background; nada pasa
  por el modelo. **Bolita persistente** del robot abajo-izquierda (tocar = chat).
- **"Me acabo de levantar"** (`POST /horario/despertar`, migración 0042): setea
  el ancla de despertar SOLO-HOY (no toca la rutina estándar) y materializa el
  set del día desde esa hora — determinista, instantáneo.
- **Inteligencia del planificador (determinista, sin LLM):**
  - **Transición tras compromisos fuera de casa** (migración 0043): tras una
    clase o un evento con `ubicacion`, reserva un buffer de transición
    (`config_horario.transicion_min`, default 60 min; override por evento en
    `eventos.transicion_min`) donde NO coloca trabajo de casa. Editable por chat
    con `configurar_horario`.
  - **Ningún proyecto activo sin acción siguiente:** si un proyecto de trabajo no
    quedó en el set ni con tarea de hoy, el planificador deriva su siguiente paso
    del árbol (primer nodo fino abierto) o sintetiza "Definir el siguiente paso
    de X". Mata el bug "0%, sin acción".
  - **Apartado de huecos libres:** el plan del día expone `huecos` (ventana libre
    real + duración legible) con UNA sugerencia dosificada que de verdad cabe por
    hueco (pool = lo que no entró, en orden de prioridad). Instantáneo, sin
    tokens. Se surface por el chat/`plan_de_hoy` y la vista nativa "Tu día" en
    Flutter YA lo dibuja (`plan_dia_section.dart`: filtra huecos ≥20min, apartado
    de huecos con botones "Hacer"/"Ahora no"); el REST lleva `huecos`/`sugerencias`.

### Cerebro — tools del chat (128)

Hub básico: crear_tarea, crear_tareas (lote), editar_tarea, completar_tarea,
reabrir_tarea, eliminar_tarea(conf), marcar_accion_siguiente_hecha, crear_evento,
editar_evento, eliminar_evento(conf), crear_apunte, editar_apunte,
eliminar_apunte(conf), registrar_cierre. · Consultas (solo lectura):
consultar_tareas, consultar_eventos, consultar_proyectos, consultar_apuntes,
consultar_movimientos, consultar_uso. · Proyectos: crear_proyecto, editar_proyecto,
aparcar/terminar/reactivar_proyecto, eliminar_proyecto(conf). · Finanzas:
crear_movimiento, editar_movimiento, eliminar_movimiento(conf),
registrar_movimientos (lote por foto), revertir_ultimo_lote. · RAG/biblioteca:
buscar_apuntes, leer_apunte, buscar_material. · Memoria personal: recordar,
actualizar_memoria, olvidar(conf), buscar_memoria. · Memoria conversacional:
buscar_en_historial. · Web: buscar_web. · UX: navegar, preguntar_con_opciones. ·
Modos: activar_modo, desactivar_modo. · Perfil profundo de proyecto:
ver_perfil_proyecto, actualizar_perfil_proyecto, anotar/corregir/borrar_detalle,
iniciar/continuar_entrevista_proyecto. · Árbol (plan): generar_arbol_proyecto,
ver_arbol_proyecto, agregar/actualizar/eliminar_nodo, refinar_fase,
avance_proyecto. · Intake analítico: intake_proyecto, guardar_parametro_proyecto,
puede_planear_proyecto, material_para_proyecto, capacidad_proyectos,
importar_plan_proyecto. · Evolución: revisar_proyecto. · Set del día:
proponer_set_dia, ver_set_dia, aceptar_set_dia, saltar_item_set,
configurar_planificacion. · Horario: plan_de_hoy, replanificar_dia,
configurar_horario. · Automatizaciones: crear/listar/eliminar_automatizacion. ·
Teléfono: redactar_mensaje (SMS/correo), iniciar_llamada, crear_evento_telefono,
abrir_en_telefono, leer_galeria (Fase 1) · leer_pantalla (C.0) · escribir_whatsapp
(C.1). · PC (agente local · Capa 6): lectura (6.0b) pc_listar_carpeta,
pc_buscar_archivos, pc_leer_archivo, pc_resumir_documento · organización (6.1,
proponen y la app confirma) pc_mover_archivo, pc_renombrar_archivo,
pc_crear_carpeta, pc_organizar_carpeta · apps y tareas (6.2, proponen y la app
confirma) pc_abrir_app, pc_ejecutar_tarea, pc_cerrar_app · control de pantalla
(6.3, autónomo con rails, OFF por defecto) pc_controlar_pantalla. (conf) = pide
confirmación por ser destructiva.

### Rendición de cuentas — push con botones de acción

Notificaciones push del SISTEMA con 3 botones ("Sí, lo hice" / "Más tarde hoy"
/ "Mañana") que funcionan con la app cerrada. Contenido determinista
(plantilla, cero LLM/tokens). El botón "Más tarde hoy" aparece SOLO si hay
ventana útil real antes del ancla de dormir (reusa `horario.ventanas_libres`
con `buffer_pre_sueno_min`). Escalada con tope (3 niveles, dedup por tarea,
cooldown 20h; una tarea resuelta no vuelve a aparecer). Silencio nocturno
respetado vía `permitido_ahora` (config_nudges + anclas). Disparo: enganchado
al ritual del cierre (primera ronda) + tick periódico del scheduler cada
minuto. Lado app: el push viene con `data.tipo=rendicion_cuentas`, el handler
de background de FCM repinta con `flutter_local_notifications` (que sí soporta
actions); los taps disparan `manejarTapNotificacionEnBackground` (top-level
`@pragma('vm:entry-point')`) → POST `/push/rendicion-cuentas/accion` (el
cerebro hace completar / rollover.otro_dia / mover al próximo hueco real).
MagicOS/Honor: tile en Ajustes para conceder exención de optimización de
batería (`permission_handler` + `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`); si
el OEM bloquea el diálogo, abre Ajustes de la app. Migración 0041
(`pings_rendicion_cuentas`). Detalle en `docs/Rendicion_Cuentas.md`.

Extensión (2026-06-07, migración 0044):
- **Asistencia a eventos fuera de casa** (`asistencia_eventos.py`): tras un
  evento con `ubicacion` (clase/gym/cita) que termina, push "¿Fuiste a X?" con
  "Sí fui" / "No fui" / "Reprogramar". La respuesta vive en `eventos.asistencia`
  y alimenta el motor de evolución. Endpoint `/push/asistencia/accion`; tipo de
  push `asistencia_evento`, payload `as:<id>`, handler
  `manejarTapAsistencia`. Dedup por `asistencia_preguntada_en`.
- **Tareas re-etiquetadas** "¿Hiciste X?": Sí / No, mañana / No, más tarde
  (mismo motor `hecho`/`manana`/`mas_tarde`; "más tarde" solo con ventana útil).
- **Intensidad graduable** (`config_nudges.intensidad`, dial en Ajustes:
  suave/medio/intenso/máximo, default intenso). El cerebro la manda en el push;
  la app la mapea (puro, `intensidad_notif.dart`) a mecanismos Android:
  suave=estándar, medio=heads-up, intenso=heads-up+persistente, máximo=+full-
  screen para lo crítico vencido. Canales: `matix_suave` (default),
  `matix_recordatorios` (alta), `matix_critico` (máx). La cadencia de re-alerta
  escala con la intensidad (20/12/6/3 h).
- **Evolución alimentada por dos señales reales**: tasa de cierre de tareas +
  tasa de asistencia (`combinar_tasas`, conservador: la peor manda → faltar a
  eventos también achica el set).
- **Silencio nocturno** gatea ambos ticks (ni el máximo dispara full-screen
  mientras duermes). MagicOS: la guía del modo máximo (batería + full-screen
  intent + autoarranque) reusa `entrega_background_service` y el canal nativo de
  `wakeword_bg_service`. Lo nativo (heads-up/full-screen/ongoing real) es de
  DISPOSITIVO: no corre en CI; cubierto por tests puros del mapeo + contratos.

Refuerzo MagicOS (2026-06-07):
- **Pantalla "Diagnóstico de notificaciones"** (Ajustes → Notificaciones):
  estado de POST_NOTIFICATIONS, alarmas exactas, batería sin restricciones y
  full-screen intent (canal nativo), con CTA que abre el ajuste del sistema
  correspondiente. Botón "Enviar prueba con botones AHORA" que dispara una noti
  real (con la `tareaId='diag-ping'` que el cerebro responderá 404 sin tocar
  datos del usuario). Historial reciente del [ConfirmacionService] muestra
  el último intento + status para cada acción — convierte "no sé por qué falla"
  en "veo qué eslabón falla".
- **ConfirmacionService** centraliza los POST de las acciones de tareas y de
  asistencia (mismos endpoints que la noti). Lo usan: los handlers de background
  (instrumentados), la UI in-app y la pantalla de diagnóstico. Persiste un log
  rotatorio (~30) con `cuando/tipo/ref/accion/ok/statusCode/error`.
- **Confirmación IN-APP** (`ConfirmarPendientesCard`) en Tu día y en Cierre del
  día: muestra tareas pasadas sin completar + eventos fuera-de-casa terminados
  sin asistencia (endpoint nuevo `GET /push/pendientes-confirmacion`), con
  botones que aplican exactamente las mismas acciones del cerebro. El motor de
  evolución sigue alimentándose aunque la noti nunca llegue.
- **Logging en cerebro**: `/push/rendicion-cuentas/accion` y `/push/asistencia/
  accion` ahora hacen `logger.info("…/accion recibida: …")`. El user puede
  verificar contra los logs de Railway si la acción llegó al servidor.

### Widgets de pantalla de inicio (Android · 2026-06-07)

Dos widgets nativos: **"Próximo"** (compacto, una sola cosa: lo que toca ahora o
lo siguiente) y **"Hoy"** (lista del día desde ahora, capada a 4 con "+X más",
diferenciando fijo de tentativo). Puente `home_widget`: la app EMPUJA el plan del
día YA determinista al almacenamiento del widget y dispara el refresco; el nativo
(**RemoteViews**, no Glance — Compose no está en el classpath) SOLO lee y pinta,
sin lógica ni llamadas al cerebro. Selección pura en Dart
(`features/widgets_inicio`, reusa `bloqueActual`/`bloqueSiguiente`). Tokens de
Matix espejados en `res/values/colors.xml`. Refresco: push on-change (un
`ref.listen(planDiaProvider)` cubre completar/saltar/replanificar/despertar/
rollover) + WorkManager periódico (90 min, solo con red) + `updatePeriodMillis`
nativo de respaldo. Tap en ítem → deep link (`matixwidget://abrir?payload=…`,
reusa `_enrutarPayload`); tap en encabezado → Inicio. Estado vacío limpio ("Abre
Matix para ver tu día"). Marcar hecho desde el widget queda para Fase 2 (solo
lectura + deep link). MagicOS: el refresco en background puede morir por la
gestión agresiva — reusa la exención de batería (`entrega_background_service`).
Render nativo: validación en DISPOSITIVO (el unit local no lo prueba); la lógica
de empuje sí está testeada.

Pulido (2026-06-07): se corrigió la CAUSA real del deep link roto en "Hoy" — el
helper `HomeWidgetLaunchIntent` hardcodea requestCode=0 y la igualdad de
PendingIntent ignora el `data`, así que todas las filas colapsaban en un solo
intent (abrían el mismo destino). Ahora un `deepLink(payload, requestCode único)`
por ítem/widget hace que cada fila aterrice en su pantalla. Frescura: además del
push on-change + WorkManager, se re-empuja al volver al frente (recalcula el
"próximo" contra el reloj) y se invalida el plan si cambió la fecha (cubre "día
nuevo"). Diseño: jerarquía fuerte (hora grande monospace + relativo "en X min"),
barra de color por semántica (proyecto azul, evento fijo verde, vencido rojo,
práctica tentativa ámbar), encabezado "HOY · fecha" con distintivo, primer ítem
destacado y resto sobrio, estado celebratorio "¡Todo hecho!", y responsive de
verdad (`onAppWidgetOptionsChanged`: chico = solo el próximo, grande = la lista).
Fuente: monospace del sistema para la hora (Inter/JetBrains Mono no se pueden
bundlear nativo sin GMS en el Honor; documentado).

### Capa 6 — Agente de PC (6.0a cimiento · 6.0b lectura · 6.1 organización · 6.2 apps y tareas · 6.3 control de pantalla)

Daemon local `agente_pc/` (Python) que corre en la PC del usuario y abre una
conexión SALIENTE persistente al cerebro (WebSocket sobre TLS, reconexión por
backoff). La PC siempre inicia; el cerebro nunca inicia hacia la PC; no se abren
puertos. Autenticación por secreto compartido `AGENTE_PC_TOKEN` (header
`X-Agente-PC-Token`, distinto de la API key de la app) + verificación de host
por TLS (CA estándar, sin pinning). Framework de acciones TIPADO (registry con
nivel de riesgo segura/consecuente/prohibida, extensible).

Acciones: **6.0a** listar_carpeta. **6.0b (lectura, SEGURA)** buscar_archivos
(nombre/glob → ruta, tamaño, fecha), leer_archivo (texto, con tope; binarios
no), resumir_documento (PDF/DOCX/TXT/MD → bytes por el canal → extractor del
cerebro reutilizado → resumen con el modelo mini). **6.1 (organización,
CONSECUENTE con gate)** mover_archivo, renombrar_archivo, crear_carpeta,
organizar_aplicar (por tipo/fecha/proyecto: primero PLAN, luego ejecución paso a
paso revalidando cada movimiento). **6.2 (apps y tareas, CONSECUENTE con gate)**
abrir_app (allowlist DURA de apps configurable + denylist hardcoded que gana:
shells/terminales, intérpretes, sistema, instaladores, credenciales, y todo lo
que viva en C:\Windows; lanzado con subprocess SIN shell), ejecutar_tarea
(tareas PREDEFINIDAS y tipadas del registro `tareas.py` — sesion_de_foco,
abrir_proyecto — que componen primitivas seguras; cero comandos arbitrarios),
cerrar_app (graceful, solo los PIDs que el agente abrió esta sesión). **6.3
(CONTROL DE PANTALLA, la más peligrosa — OFF por defecto)** pc_controlar_pantalla:
bucle en el cerebro capturar→visión(gpt-4o-mini, falla cerrado)→rails→actuar,
acotado a 12 pasos; el agente pone las manos (pantalla_capturar/pantalla_accion
con pyautogui FAILSAFE, sin shell). Rails: pantalla prohibida (login/banca/pago/
contraseñas)→abort; anti-inyección (lo visible es DATO); acción irreversible→
gate (pantalla_accion_confirmada); kill switch (mouse a la esquina o Ctrl+C) +
indicador rojo; tope de acciones/sesión; master switch AGENTE_PC_CONTROL_PANTALLA.
Sin borrado todavía (irreversible → fase propia con confirmación reforzada).
Recalibración del riel anti-inyección (`_CONTROL_SYSTEM`): `prohibida` se RESERVA
para pantallas SENSIBLES (login/banca/claves) — un escritorio/navegador/terminal/
Spotify, o una pantalla "con instrucciones", NUNCA es prohibida; el texto de la
pantalla es DATO que se IGNORA, la única intención es el objetivo del usuario. Si
la app aún no está abierta, NAVEGA (no aborta). Antes el modelo sobrecargaba
`prohibida` con "no es relevante / no sé qué hacer" (reproducido: 4/8 falsos
positivos en un escritorio con texto → 0/8 tras la recalibración; un login
sintético sigue dando prohibida). `interpretar_pantalla` ahora loguea el veredicto
del piloto (prohibida/motivo/acción) para diagnosticar futuros aborts.

**Robustez del canal + nunca silencio (D).** Diagnóstico: el agente NO crasheaba
(PID estable en los logs); el WS se caía A MITAD del bucle de control (corte del
proxy de Railway) y el cerebro veía `_ws=None` durante el ~1s de reconexión y
abortaba al instante; además el bucle podía exceder el timeout del chat (45s) →
silencio. Fixes: (1) `canal.enviar_accion` ahora da una **gracia de reconexión**
(12s) si el WS cayó hace poco — un blip a mitad del control ya no aborta la tarea;
si la PC nunca conectó o lleva rato caída, responde "desconectada" al instante.
(2) `bucle_control` tiene **presupuesto de tiempo** (70s): si se agota, para con
"tope" y mensaje claro, nunca silencio. (3) El timeout del chat de la app subió a
**90s** para que el control entre. (4) `registro.ejecutar` del agente loguea el
**traceback real** de cualquier handler que falle (ninguna acción tumba el
proceso). **Acceso amplio (D3):** `AGENTE_PC_ALLOWLIST=~` (todo el perfil del
usuario) — la denylist dura (.env/.ssh/credenciales/AppData/sistema) sigue
ganando, verificado.

Rails: allowlist (default Documentos/Escritorio/Descargas, editable); denylist
dura que GANA (.ssh, .env, llaves, .git, AppData/perfiles de navegador, sistema);
path traversal y symlinks bloqueados por canonicalización (realpath antes de
validar); revalidación por paso (anti-TOCTOU) y sin sobreescritura; sin shell;
audit log local; kill switch (Ctrl+C/SIGTERM); anti-inyección (lo leído es DATO,
nunca instrucciones — el mini que resume recibe orden explícita de no obedecer al
documento); rechazo a correr elevado.

Gate de las consecuentes (triple capa): el modelo solo PROPONE (las tools
devuelven un bloque `accion_dispositivo` tipo `pc_accion`); la app reusa el sheet
de confirmación del agéntico del teléfono; al confirmar, `POST /api/v1/agente/
ejecutar` (whitelist server-side) cruza el canal con `confirmado=true`; el agente
exige esa marca y revalida cada ruta en su borde. Nota (fix del caso «abre
Spotify»): el Literal de `AccionDispositivo.tipo` ya incluye `pc_accion` (antes
la propuesta de PC no validaba contra `ChatResponse` y el chat moría en 500
mudo); hay handler dedicado de `ResponseValidationError` (motivo claro, nunca
silencio) y test de paridad emisor↔schema. El system prompt lleva una sección
«CAPACIDADES EN LA PC» GENERADA del catálogo de tools (`capacidades_pc.py`,
fuente única con test de cobertura): ruteo multi-paso → `pc_controlar_pantalla`
(6.3) y límites reales — el doc de autoconocimiento ya no declara la PC como
«capa futura». Lado cerebro: canal singleton
(`app/agente/canal.py`) + WS `/agente/ws` + GET `/agente/estado` + POST
`/agente/ejecutar`. Si la PC no está conectada, todo responde limpio (no se
cuelga). App: indicador "PC: conectada/desconectada" en Ajustes → Conexión +
chips de las tools en el chat. Guía completa en `docs/Capa6_Agente_PC.md`.

**Arranque automático (autostart).** El agente solo conecta mientras corre; si
no está vivo, Matix ve "PC desconectada" (síntoma de "lo de pc no funciona").
Se deja permanente con un acceso directo en la **carpeta de Inicio** del usuario
(`scripts/instalar_autostart.ps1`; se quita con `desinstalar_autostart.ps1`):
arranca al iniciar sesión, con `pythonw.exe` (sin ventana), sin admin, sin
elevación. Se eligió la carpeta de Inicio y NO una Tarea Programada porque bajo
Task Scheduler el `pythonw` del venv de uv (trampolín que re-ejecuta el
intérprete base) se cuelga en el arranque por handles de stdio inválidos en esa
sesión; la carpeta de Inicio lanza en la sesión interactiva real, donde conecta
sin problemas. Operabilidad: lanzador `scripts/arrancar.py` (resuelve la raíz por
`__file__`, independiente del CWD, y redirige stdout/stderr a
`agente_autostart.log` porque `pythonw` los deja en None) + log de runtime
rotativo `agente_runtime.log` + guard de **instancia única** (mutex de sesión
`Local\MatixAgentePC`: un segundo agente lanzado a mano sale con código 6 en vez
de pelear por el canal).

**Apps en modo PERMISIVO (C2).** `abrir_app` ya NO exige una allowlist: cualquier
app instalada que el usuario nombre se resuelve sola (PATH → App Paths del
registro → búsqueda acotada en `LOCALAPPDATA`/`APPDATA`/`Program Files`). El
único rail que queda es la **denylist DURA** (shells/terminales, instaladores,
herramientas de sistema, todo `C:\Windows`) — innegociable. `AGENTE_PC_APPS_ALLOWLIST`
sobrevive solo como overrides opcionales de ruta. `cerrar_app` cierra solo lo que
el agente abrió en la sesión (por PID). Honestidad: el resultado real de cada
acción de PC (abrió / no encontró / bloqueó por denylist) se inyecta en el CHAT
(`agregarNotaMatix`), no solo en un toast.

**Librería de capacidades TIPADAS (E) — el control de pantalla es el ÚLTIMO
recurso.** Lección (arquitectura tipo OpenClaw): la fiabilidad viene de una
herramienta DETERMINISTA por tarea, no de clicar a ciegas. Nuevo módulo
`agente_pc/capacidades.py` (registrado en `crear_registro`): `abrir_carpeta`
(abre carpeta en Explorador o archivo en su app, sin shell, ruta validada),
`tomar_captura` (PNG full-res a ~/Pictures/Matix, SEGURA), `crear_documento_word`
(`.docx` REAL con python-docx: título/párrafos/tablas, sin tocar la GUI de Word)
y `reproducir_spotify` (URI `spotify:`, determinista, sin clics). Cerebro:
tools `pc_abrir_carpeta`/`pc_captura`/`pc_crear_word`/`pc_reproducir_spotify` +
ruteo en `capacidades_pc.py` que PREFIERE la capacidad tipada y deja
`pc_controlar_pantalla` como fallback.

**Spotify que SUENA de verdad + fin del interrogatorio (F).** Dos cambios:
(1) **Sin fricción en órdenes reversibles**: `abrir_app`, `abrir_carpeta`,
`crear_documento_word` (archivo nuevo, nunca sobreescribe) y
`reproducir_spotify` pasaron de CONSECUENTE a **SEGURA** — se ejecutan DIRECTO,
sin sheet de confirmación ni preguntas («cualquier canción de X» es orden
completa). La confirmación queda para lo que puede perder datos: `cerrar_app`,
mover/renombrar/organizar, tareas tipadas y la acción irreversible de pantalla.
(2) **Reproducción REAL y verificada**: pipeline en `_pc_reproducir_spotify` →
con `SPOTIFY_CLIENT_ID/SECRET` resuelve el track más popular vía Web API; el
agente abre el URI y **MIDE si suena** (`agente_pc/audio.py`: peak de audio del
proceso Spotify vía pycaw + título de ventana «Artista - Canción»); si no
arrancó y hay `SPOTIFY_REFRESH_TOKEN` (Premium, se obtiene una vez con
`tools/spotify_autorizar.py`), ordena play por `PUT /me/player/play` al device
Computer y RE-VERIFICA (`verificar_spotify`). El mensaje dice «suena» SOLO si
se midió; si no, narra el muro exacto (qué variable falta) sin loops. Hallazgo
empírico (en la PC real): abrir `spotify:track:…` a veces auto-reproduce y a
veces solo navega — por eso se mide siempre en vez de asumir. Módulo
`cerebro/app/matix/spotify_web.py` (client-credentials + refresh token, caché
de tokens, mockeado en `test_spotify_web.py`).

**Spotify — vía garantizada PRIMERO (cierre).** El pipeline de
`_pc_reproducir_spotify` se invirtió: con OAuth (Premium) la Web API es el
camino PRINCIPAL, no el rescate. Orden: (1) resolver track; (2) asegurar el
dispositivo — si el cliente de escritorio está cerrado, el agente lo ABRE
(`abrir_app spotify`) y se espera ACOTADO (~12s máx) a que figure en
`/me/player/devices` (`dispositivo_objetivo`, prefiere `SPOTIFY_DEVICE_NAME` =
hostname de la PC, nunca la laptop); (3) `PUT /me/player/play` a ese device;
(4) re-verificar el audio con el agente. Estados honestos: `sonando` (API
confirmó Y se mide audio), `reproduccion_ordenada` (API confirmó pero no se
mide audio local — volumen/mezclador), `abierto_sin_sonar` (con la CAUSA
exacta: sin dispositivo / token vencido o revocado → reautorizar con
`tools/spotify_autorizar_auto.py` / sin Premium 403 / faltan credenciales).
Renovación del access token automática (refresh + caché con expiración).
Credenciales: env vars o `secretos_runtime` (Supabase, solo service role);
`spotify_autorizar_auto.py` guarda todo sin imprimir valores. PENDIENTE del
dueño (una sola vez): crear la app en developer.spotify.com y autorizar
(pasos exactos en el cierre del prompt).

**Spotify — OAuth DESDE LA APP (I).** Se reemplazó el OAuth local por 127.0.0.1
por un flujo authorization-code con el cerebro como redirect público — el dueño
conecta su Premium desde Ajustes, sin Chrome en la PC. Cerebro: router
`spotify.py` (espejo de `google.py`) — `GET /spotify/status`,
`GET /spotify/oauth/url` (URL de consentimiento con scopes
`user-modify-playback-state` + `user-read-playback-state`, state CSRF en memoria
con TTL), `GET /spotify/callback` (PÚBLICO, sin `X-Matix-Key`: Spotify redirige
desde el navegador; valida el state e intercambia el code) y
`DELETE /spotify/disconnect`. `spotify_web` ganó `url_de_autorizacion`,
`intercambiar_code` (guarda el refresh en `secretos_runtime` vía nuevo
`secretos.guardar`, NUNCA lo loggea), `conectado` y `olvidar_refresh`. Redirect
URI: `https://matix-production.up.railway.app/api/v1/spotify/callback` (a
registrar en el dashboard de la app de Spotify). App: tile «Conectar Spotify» en
Ajustes › Conexiones (`features/spotify/`), abre la URL en el navegador del
teléfono y al volver «Ya autoricé» re-chequea. Client ID/Secret YA cargados y
validados (la búsqueda resuelve tracks); falta solo que el dueño toque conectar
una vez. VERIFICADO local: la authorize URL trae scopes y el redirect correcto.

**Spotify — cambio de canción limpio + controles del player (J).** Dos pulidos:
(1) **Reemplazo limpio**: al cambiar de canción ya no se encima una segunda.
`_elegir_dispositivo` ahora prefiere la entrada ACTIVA de ESTA PC (Spotify a
veces registra una entrada duplicada al reconectar → apuntar a la otra dejaba
DOS sonando); el `PUT /me/player/play` reemplaza en la misma sesión. Y la
confirmación pasó a leer el ESTADO REAL del player (`estado_reproduccion` →
`GET /me/player`: qué track suena de verdad) en vez del título de ventana —
se dice «puse X» solo si el player confirma que suena justo esa. (2) **Controles
sin cambiar de track**: nueva `pc_control_spotify` (pausa/reanuda/siguiente/
anterior vía `spotify_web.control_player` → endpoints del player apuntando al
device de la PC), con sinónimos tolerantes a tildes/frases («pásala», «para la
música»). MÚSICA NUNCA CONFIRMA: `pc_reproducir_spotify` y `pc_control_spotify`
son directas; el prompt (`capacidades_pc.py`) prohíbe explícitamente el
«¿quieres que…?» para órdenes de música. Resultado siempre leído del estado
real. Solo cerebro (la app no cambió): redeploy, sin build nuevo.

**Fiabilidad del agente PC — autoarranque con VIGILANTE (G).** Causa raíz del
agente muerto tras un reinicio (boot 2026-06-12): el venv del disco real
apuntaba a un build de Python que no existía ahí (las instalaciones de uv desde
la sesión de Claude caen en un overlay que el sistema real no ve) → el `.lnk`
del Startup lanzaba un trampolín que moría en silencio. Fix en dos capas:
(1) `uv sync` (+ `--extra control`) ejecutado EN CONTEXTO REAL vía tarea
programada → venv real sano (Python 3.14 + todas las deps); (2) tarea
`MatixAgenteVigilante` (cada 5 min, `scripts/vigilar_agente.ps1`, instalador
`scripts/instalar_vigilante.ps1`): si el proceso del agente no está, lo relanza
oculto vía `cmd /c` con stdio explícito a `agente_vigilante.log` (pythonw
directo bajo el scheduler se cuelga; y redirigir a `agente_autostart.log`
chocaba con arrancar.py → PermissionError). El `.lnk` del Startup queda como
arranque inmediato al logon; el vigilante cubre boots donde el Startup no
dispara y cualquier muerte a mitad de sesión. VERIFICADO en vivo: kill →
resurrección + reconexión al cerebro. Reconexión WS con backoff + latido de
datos (25s) + motivo de cada caída logueado ya estaban (sobrevivió 2 redeploys
de Railway reconectando en ~1s); ninguna acción tumba el proceso
(`registro.ejecutar` captura todo y reporta error estructurado). Lote 1
re-verificado EN EL SISTEMA REAL: abrir_carpeta (Explorador), tomar_captura
(PNG 1920x1080 en ~/Pictures/Matix) y crear_documento_word (.docx con tabla,
releído y validado). **Confinamiento del control de pantalla
(la seguridad que falló):** cada captura reporta la VENTANA enfocada; antes de
cada acción el agente verifica que la ventana siga siendo esa (`ventana_esperada`)
y NUNCA actúa si el foco es una superficie de comandos (terminal/Claude/cmd/
PowerShell) — si el foco saltó, aborta. Así no vuelve a teclear en otra app.
Rieles previos intactos (banner, kill switch, tope, denylist, confirmación).

**Librería de capacidades — lote 2 (H): gestión de archivos directa, abrir web,
resumen con modelo fuerte.** Tres incorporaciones, todas deterministas y con la
denylist intacta (`.ssh`, `.env`, credenciales, repo, AppData, sistema →
INVISIBLES aunque estén en el perfil; verificado en vivo: copiar/mover a `.ssh`
o AppData devuelven `rechazada` con el original intacto). (1) **Archivos**: nueva
`copiar_archivo` (`shutil.copy2`, origen intacto, nunca sobreescribe) +
`pc_copiar_archivo`; y migración de criterio: como NINGUNA op de un solo archivo
sobreescribe (todas rechazan si el destino existe), `mover_archivo`,
`renombrar_archivo`, `crear_carpeta` y `copiar_archivo` pasan de CONSECUENTE a
**SEGURA** → se ejecutan DIRECTO, sin sheet de confirmación («solo confirmar lo
irreversible»). `organizar_aplicar` (lote, mueve muchos) SIGUE confirmando con
plan previo. (2) **abrir_web**: capacidad nueva (`capacidades.py`) que abre una
URL en el navegador por defecto sin shell, con riel de esquema (solo http/https;
`file://`, `javascript:`, `data:` → rechazados; un host pelado tipo «youtube.com»
se prefija https tras parsear) + `pc_abrir_web` directo. (3) **resumir_documento**
arreglado de raíz: usaba el modelo BARATO y cortaba a 16k chars; ahora usa el
**modelo FUERTE** y si el doc excede ~12k chars **trocea con sensatez**
(map-reduce: resume cada trozo en paralelo y combina, tope 12 trozos con aviso de
parcial). `extraccion_documentos` ganó `extraer_completo` (sin cap) y `trocear`.
Ruteo en `capacidades_pc.py`; selección en `seleccion_tools.py`. Probado EN LA PC
REAL: copiar (preserva original), mover, buscar, crear carpeta y abrir_web.

**Captura de pantalla (C1).** El control 6.3 captura con `pyautogui`→`pyscreeze`→
`Pillow`. Pillow NO era dependencia dura de pyscreeze, así que faltaba y
`screenshot()` reventaba con un críptico «(PyAutoGUIException)». Se fija `Pillow`
explícito en el extra `control` del pyproject y `capturar_pantalla` ahora loguea
el traceback REAL en `agente_runtime.log` + da una pista accionable.

**Ruteo de modelos por dificultad + failover de crédito (C3).** El modo
Automático ya escala mini↔fuerte por mensaje (enrutador); ahora **operar la PC /
controlar pantalla rutea al FUERTE** (tarea dura). Y el failover entre
proveedores detecta el crédito agotado de **Anthropic (400 «credit balance too
low»)**, no solo el de OpenAI (429): antes ese 400 mataba el turno; ahora cruza a
un GPT fuerte (`claude-sonnet-4-6`→`gpt-5.5`). El par barato/fuerte es
configurable (`/modelos/par`); sirve como camino OpenAI-only cuando Anthropic no
está disponible.

### Cerebro — endpoints REST (~126 rutas, prefijo /api/v1)
(Nota 2026-06-04: se retiró el router /tracks, legacy; ver «Consolidación» abajo.)

CRUD del hub: profile, categorias, cursos, sesiones-clase, tareas, subtareas,
evaluaciones, eventos (con papelera/restaurar/permanente), cuadernos, apuntes
(archivar/restaurar/retomar/permanente), movimientos, proyectos, memoria,
cierres_dia. · Matix/IA: chat, transcribir, voz, capturar-apunte,
clasificar-captura, desglosar-tarea, estimar-duraciones, extraer-documento,
extraer-eventos, extraer-recibo, extraer-tareas, uso, wakeword/muestras. ·
Notificaciones: push (registrar-token, probar, revisar), nudges, rituales. ·
Briefing: hoy, cierre, repaso-semanal. · Horario: GET plan, replanificar,
bloque/completar, bloque/saltar, calendario. · Aprendizaje:
material/ingestar. · Modelos/modos: modelos (par, seleccionar), modos
(activar/desactivar). · Google (Capa 4): oauth/url, oauth/callback, status, sync,
disconnect. · Infra: health, version, docs.

### Cerebro — jobs del scheduler (APScheduler, cada minuto; solo si hay FCM)

recordatorios de tareas/eventos/evaluaciones · rituales (briefing mañanero,
cierre, repaso semanal) · nudges de tareas pendientes · automatizaciones del
usuario · planificador diario (propuesta del set, escalación sobre lo aceptado,
nudge de dormir, sugerencia ligera de skill) · evolución (check-in semanal por
proyecto, celebración de hito de fase, hito de % 25/50/75/100, aviso de
estancamiento). Todo respeta el silencio 22:00–08:00 (America/Lima).

### Cerebro — sistemas de proyectos/skills/intake/evolución/horario

- Perfil profundo de proyecto (0029): objetivo, estado, fase, horizonte +
  detalles con fecha (componentes/próximos pasos/blockers/notas) + entrevista.
  SOLO-BACKEND (se opera por chat; la app solo muestra % y acción siguiente).
- Árbol de descomposición (0030): fases→pasos, elaboración progresiva (fase
  actual fina, lejanas gruesas), % ponderado. SOLO-BACKEND (por chat).
- Intake analítico (0032): tipo (negocio, contenido, construir, skill, físico,
  genérico) con esquema de requeridos+opcionales, gate de meta medible + porqué,
  y análisis de realismo (incoherencias/metas irreales) antes de planear.
  COMPLETO en cerebro; se usa por chat e importación de plan.
- Skills/hábitos (0034): flag `es_skill`; no consumen el tope de 3 (tope blando
  de 2), dosis ligera (nudge suave opcional, sin la insistencia de una tarea).
  Creadas: Inglés (B2) y Guitarra activas con ruta por bloques desde la
  biblioteca; Trading y Portugués parqueadas. SOLO-BACKEND (aparecen como
  proyectos en la app; sin pantalla dedicada).
- Evolución/seguimiento (0033): review holístico (modelo fuerte), generación
  progresiva sin duplicar, check-in semanal honesto, hitos, estancamiento +
  re-scope, adaptación al ritmo (no apila si vas atrasado). SOLO-BACKEND + push.
- Set del día (0031): set chico priorizado desde los árboles, insistencia sana,
  anti-fatiga. Se ve dentro de la vista «Hoy» y por chat (el viejo
  `planificar_dia` se retiró el 2026-06-04).
- Horario (0035): config_horario (anclas/despertar/dormir/pico/buffers),
  ventanas libres, colocación del set (pico para lo importante, skills en
  ventanas ligeras), replan, empuje al calendario. COMPLETO backend + UI nueva
  (vista «Hoy» en Inicio); falta validación en device.

### Cerebro — integraciones

- FCM (push): notificaciones locales/push; el scheduler solo corre con
  `FIREBASE_SERVICE_ACCOUNT_JSON`.
- RAG/biblioteca_material (0015): `material_chunks` (skill+bloque+embedding);
  tool `buscar_material` + `POST /material/ingestar`. Skills con material:
  ingles, guitarra, calistenia, trading, portugues. Skills activas como
  proyectos: Inglés, Guitarra, Calistenia; parqueadas: Trading, Portugués.
  SOLO-BACKEND (sin UI para
  navegar la biblioteca).
- Teléfono: Fase 1 intents (abrir app/url/mapa, llamar, SMS/correo prellenado,
  leer galería) COMPLETO · Tier C.0 leer_pantalla (accesibilidad, solo lectura)
  · Tier C.1 escribir_whatsapp (envía tras confirmación). Tier B NO existe.
- Google (Capa 4): OAuth + sync de calendario. PARCIAL/temprano (tile en
  Ajustes + endpoints; no es el foco actual).

### App (Flutter) — pantallas y secciones

- Navegación: `home_shell` — 5 pestañas (Inicio · Tareas · Matix(FAB) ·
  Calendario · Proyectos) + Universidad/Finanzas/Apuntes/Ajustes fuera de barra.
- Inicio (`inicio_screen`): panel del día — rituales, captura rápida, vista
  «Hoy» (línea de tiempo del plan, NUEVA), finanzas del mes, apuntes recientes,
  reflote de ideas, 3 proyectos activos, universidad. COMPLETO.
- Tareas: lista con vistas/filtros + crear/editar. COMPLETO.
- Calendario/Eventos: grid mensual + lista del día + crear evento + clases
  recurrentes + detección de choques. COMPLETO.
- Universidad: cursos + detalle (promedio) + evaluaciones + horario de clases.
  COMPLETO.
- Apuntes: lista + editor con etiquetas. COMPLETO.
- Proyectos: lista + detalle (acción siguiente + barra de %) + nuevo (con tope).
  COMPLETO el CRUD; el árbol/perfil/intake se ven por chat (PARCIAL en UI).
- Matix: chat (`matix_chat_screen`), manos libres con voz (`manos_libres`),
  accesibilidad (C.0), confirmación de acciones de dispositivo. COMPLETO.
- Finanzas: dashboard + lista + editor + captura por foto. COMPLETO.
- Cierre del día + Briefing + Repaso semanal: rituales. COMPLETO.
- Captura cámara (visión): captura + revisión de tareas/eventos/recibos + OCR.
  COMPLETO (foto, no cámara en vivo).
- Memoria («Sobre mí»), Búsqueda global, Papelera, Wake word (entrenar voz),
  Selección de modelo, Conexión Google (tile), Auto-update: presentes.
- La vista «Hoy» (timeline) es la ÚNICA vista del plan; el viejo
  `planificar_dia` se retiró (2026-06-04). En Inicio queda «Pendientes» (tareas
  de hoy/vencidas) bajo la timeline. La «Disponibilidad por día» (Ajustes) se
  conserva (alimenta los nudges).
- SIN pantalla propia (se operan por chat / scheduler): automatizaciones,
  intake/árbol/evolución de proyectos, skills (se ven como proyectos),
  biblioteca de material. (tracks legacy: código retirado; la tabla con 1 fila
  Calistenia queda sin uso — Calistenia ahora es una skill en Proyectos.)

### Base de datos — migraciones (0001 → 0035, todas aplicadas)

0001 esquema base (profile, categorias, cursos, sesiones_clase, tareas,
subtareas, evaluaciones, eventos, cuadernos, apuntes) · 0002 proyectos · 0003
cierres_dia · 0004 papelera (eliminado_en) · 0005 apuntes RAG (embeddings) · 0006
app_versions · 0007 google_oauth · 0008-0010 eventos (sync bidireccional,
offset de recordatorio, recurrencia) · 0011 apuntes reflote · 0012 tareas bloque
(Urgency-3) · 0013 tracks de aprendizaje · 0014 movimientos · 0015
biblioteca_material (material_chunks) · 0016 device_tokens · 0017
recordatorios_enviados · 0018 rituales · 0019 nudges (config_nudges) · 0020
repaso_semanal · 0021 modos (config_matix) · 0022 memoria · 0023 modelo_chat ·
0024 par_auto_modelo · 0025 movimientos_lote · 0026 chat_operaciones · 0027
automatizaciones · 0028 memoria_conversacional · 0029 perfil_proyecto
(+proyecto_detalles, entrevistas_perfil) · 0030 arbol_proyecto (arbol_nodos) ·
0031 planificador_diario (set_diario_items, config_planificacion,
planificacion_enviados) · 0032 intake_analitico (proyectos.tipo, parametros) ·
0033 evolucion_proyecto (arbol_nodos.celebrado_en) · 0034 es_skill_proyectos ·
0035 config_horario.

Últimas tres: 0033 evolución de proyectos, 0034 skills (es_skill), 0035 config
de horario (anclas del día).

---

## Capa actual

**Capa 2 — Matix conversacional + voz + capacidad total** ·
iniciada el 2026-05-26, en validación al cierre del Paso 5.1
(2026-05-27).

La Capa 1 quedó cerrada en sus features (hub funcional con CRUD
manual + notificaciones) — su validación visual la fue haciendo
el usuario en paralelo con la Capa 2.

Pasos completados de Capa 2:

- ✓ Paso 1 — Chat solo texto (cerrado 2026-05-26).
- ✓ Paso 2 — Tool calling, primera tanda aditiva (cerrado 2026-05-26).
- ✓ Paso 3 — Voz de entrada con Whisper (cerrado 2026-05-26).
- ✓ Paso 4 — Modo manos libres con TTS (cerrado 2026-05-26).
- ✓ Paso 5 — Hub indulgente + capacidad total + medidor (cerrado 2026-05-27).
- ✓ Paso 5.1 — Correcciones: VAD, en pausa, OpenAI TTS onyx,
       `consultar_uso`, filtro de alucinaciones, aislamiento de
       tests, bugs banner/papelera (cerrado 2026-05-27).

---

## Avance por pasos

- ✓ **Paso 1 — Cimientos** (cerrado 2026-05-24)
  - ✓ Verificación de entorno (Python 3.14.5, uv 0.11.16, Flutter 3.41.9, Android SDK).
  - ✓ Acceso a Supabase confirmado; proyecto existente vacío.
  - ✓ `docs/Plan_Capa1.md` y `docs/ESTADO.md` creados.
  - ✓ `supabase/migrations/0001_initial_schema.sql` con las 10 tablas, triggers y RLS.
  - ✓ Esqueleto del cerebro (`cerebro/` con `pyproject.toml`, `app/main.py` `/health`, `app/config.py`, `.env.example`).
  - ✓ Esqueleto de la app Flutter (`app/`).
  - ✓ `.gitignore` raíz y `README.md` raíz.
  - ✓ Migración aplicada al proyecto Supabase `matix` vía Management API.
- ✓ **Paso 2 — Conexión BD ↔ Cerebro** (cerrado 2026-05-24)
  - ✓ Cliente PostgREST `app/db.py` (httpx, lazy, `service_role`). En vez de `supabase-py` que en Windows arrastra `pyiceberg` con compilación nativa.
  - ✓ Dependencia `require_api_key` (`app/security.py`) que valida `X-Matix-Key` → 401 si falla.
  - ✓ Schemas Pydantic v2 (`Create` / `Update` / `Read`) para las 10 entidades: `profile`, `categorias`, `cursos`, `sesiones_clase`, `tareas`, `subtareas`, `evaluaciones`, `eventos`, `cuadernos`, `apuntes`.
  - ✓ 10 routers CRUD bajo `/api/v1/...` con el mismo patrón (`GET` lista, `GET` por id, `POST` 201, `PATCH`, `DELETE` 204; 404 en inexistentes).
  - ✓ Tests pytest de integración: 24/24 verde. Cubren el ciclo CRUD de las 10 entidades, auth (401), validación (422) en `tareas`, `profile`, `categorias`, `evaluaciones`, `sesiones_clase`, `apuntes`, y el `ON DELETE CASCADE` de `subtareas`.
  - ✓ Smoke test con `curl` confirmado contra Supabase real (POST/PATCH/DELETE + UTF-8).
- ✓ **Paso 3 — App: navegación y tema** (cerrado 2026-05-24, pendiente verificación visual del usuario)
  - ✓ Design tokens extraídos y aprobados: colores (`bg #0B0F1A`, `card #161B2E`, `cardHi #1B2138`, `accent #2D7FF9`, semánticos), tipografía Inter + JetBrains Mono vía `google_fonts`, escala de radios (8/10/12/14/18/pill), 6 sombras nombradas, escala de espaciado de 2px.
  - ✓ `app/lib/theme/`: `matix_colors.dart`, `matix_typography.dart`, `matix_radii.dart`, `matix_shadows.dart`, `matix_spacing.dart`, `matix_semantic_colors.dart` (ThemeExtension), `matix_theme.dart` (ThemeData M3 dark).
  - ✓ Bottom nav (NavigationBar M3) con las 5 secciones + `IndexedStack` que preserva estado al cambiar de pestaña.
  - ✓ Stubs por sección: `InicioScreen`, `TareasScreen`, `CalendarioScreen`, `UniversidadScreen`, `ApuntesScreen` con badge "Próximamente".
  - ✓ Cliente HTTP `app/lib/api/matix_client.dart` (paquete `http`). Métodos `health/getList/getOne/post/patch/delete`. Inyecta header `X-Matix-Key`.
  - ✓ Configuración por `--dart-define` (`app/lib/config.dart`): `MATIX_API_URL`, `MATIX_API_KEY`, `MATIX_ENV`. Default URL = `http://10.0.2.2:8000` (emulador Android).
  - ✓ Ping al cerebro al arrancar (HomeShell `initState`): si falla, SnackBar con botón "Reintentar".
  - ✓ Widget genérico `AsyncView<T>` para el patrón estándar cargando / error / vacío / con datos.
  - ✓ `flutter analyze`: sin issues. `flutter test`: 2/2 verde (smoke + cambio de pestaña). `flutter build apk --debug`: OK.
- ✓ **Paso 4 — Sección Tareas** *(plantilla)*
  - ✓ **4.A — Backend de Proyectos** en el cerebro
    (`/api/v1/proyectos`, tope de 3 activos como 409, coherencia
    acción siguiente ↔ proyecto con auto-vinculación si la tarea está
    libre, `inactivo_desde` automático, `ultima_actividad_en`
    refrescado en cada PATCH). Tests: 18/18 verde, suite completa
    42/42. Schemas de `tareas/apuntes/eventos` expuestos con
    `proyecto_id`.
  - ✓ **4.B — Sección Tareas en la app** con Riverpod.
    Pubspec con `flutter_riverpod`, `riverpod_annotation`,
    `riverpod_generator`, `build_runner`, `intl`. `ProviderScope`
    envuelve el `MatixApp`. Estructura `app/lib/features/tareas/`
    con `data/`, `domain/`, `providers/`, `presentation/`. Pantalla
    `TareasListScreen` con 5 vistas (Hoy, Esta semana, Todas,
    Completadas, Por curso). Bottom sheet de filtros con curso,
    categoría, proyecto, prioridad, vencimiento. Pantalla
    `NuevaTareaScreen` para crear y editar (modo edición incluye
    subtareas inline). Vencidas resaltadas. `flutter analyze` sin
    issues; APK instalado y corriendo en el Huawei del usuario.
- ✓ Paso 5 — Sección Calendario (grid mensual + lista del día +
  crear eventos con recordatorio).
- ✓ Paso 6 — Sección Universidad MVP (lista cursos + detalle con
  promedio + crear curso/evaluación).
- ✓ Paso 7 — Sección Apuntes MVP (lista + editor con etiquetas).
- ✓ Paso 8 — Sección Inicio (panel del día real).
- ✓ Paso 9 — Sección Proyectos UI (lista + detalle + nuevo con
  bloqueo del tope + cambio de estado).
- ⏳ Paso 10 — Transversales (Ajustes hecho; FAB captura rápida
  cubierto vía botón "Nueva tarea" en Tareas; búsqueda global
  pendiente).
- ✓ Paso 11 — Recordatorios y notificaciones locales (tareas,
  eventos y evaluaciones). Pendientes finos: pedir permiso runtime
  proactivo, probar e2e en teléfono real.
- → Paso 12 — Cierre de Capa 1: APK debug + APK release listos en
  `app/build/app/outputs/flutter-apk/`. Doc completa
  `docs/Como_correr_Matix_desde_cero.md` con requisitos, setup,
  arranque y troubleshooting. **Pendiente**: validación visual del
  usuario en su Huawei + firma con keystore propio si quiere
  publicar fuera de Play Console.

---

## Decisiones tomadas

- 2026-06-05 — **El CI ahora corre un GATE de calidad real**, no solo arma el
  APK. `.github/workflows/release.yml` (renombrado a "CI · gate + Release APK")
  corre en cada push y PR: `gate-flutter` (`flutter analyze` + `flutter test`
  en `app/`) y `gate-cerebro` (tests PUROS del cerebro con `uv` + `pytest`). El
  job `build-and-publish` DEPENDE de ambos gates (`needs`): si analyze o tests
  fallan, el APK NO se construye ni publica. El build solo corre en push y solo
  si cambió `app/**` (paths-filter), para no republicar un APK idéntico en
  cambios solo-cerebro. Los tests de integración del cerebro (pytest contra
  Supabase) NO corren en CI: el conftest entró en "modo solo-puros" cuando falta
  `cerebro/.env.test` (antes hacía `pytest.exit`; ahora omite integración con
  `skip` y no toca Supabase). El gate no usa secretos nuevos (solo un
  `SUPABASE_URL` dummy para que la app importe); los del build siguen en GitHub
  Secrets. Con esto la calidad se enforza sin importar desde qué máquina se
  codee.
- 2026-05-26 — **Proveedor LLM para Capa 2: OpenAI**, no Claude. El
  usuario ya tiene su `OPENAI_API_KEY` y prefiere un solo proveedor.
  Decisión asociada: **la llamada al modelo vive en un único módulo
  `cerebro/app/matix/llm.py`** que es el ÚNICO punto del cerebro que
  importa `openai`. Esto permite que un futuro cambio de proveedor
  (Claude, Gemini, modelo local) sea reescribir ese archivo y nada
  más. El resto del cerebro recibe `dict`/`str` simples, no tipos del
  SDK. Plan_Capa2.md actualizado con esa arquitectura.
- 2026-05-23 — Proyecto Supabase nuevo creado: nombre `matix`,
  `ref=jtxlkwhgqeubvgfwmwcd`, región `us-east-1`, organización
  `MATIX`. El proyecto antiguo (`xapqlnyzblhnhnnvttyy`) se deja como
  está; el usuario decide después si lo borra.
- 2026-05-23 — RLS activada en las 10 tablas sin políticas; el
  cerebro accede con `service_role`. La app nunca habla con
  Supabase directamente.
- 2026-05-23 — Recordatorios viven como columna inline
  `recordar_en` en `tareas`, `evaluaciones` y `eventos` — no
  hay tabla separada. Etiquetas de apuntes son `TEXT[]`.
- 2026-05-24 — En `evaluaciones`, la columna de texto libre se llama
  `descripcion` (no `nota`), para evitar confusión con
  `nota_obtenida` / `nota_maxima`.
- 2026-05-24 — Migración 0001 aplicada vía Management API
  (`POST /v1/projects/{ref}/database/query`) con el access token —
  `supabase db push` falló por la DB password y se cambió de canal.
- 2026-05-24 — Capa 1 NO usa `supabase-py`: arrastra `pyiceberg`
  con extensión Cython que necesita MSVC en Windows. El cerebro habla
  directo con PostgREST vía `httpx` con el `service_role` key. Si más
  adelante se necesita Storage o Realtime, se reintroduce el SDK
  detrás de un wrapper limpio.
- 2026-05-24 — Los tests del cerebro son de **integración real**
  contra el proyecto Supabase `matix`, no contra mocks. Cada test
  limpia las filas que crea (try/finally). Justificación: validar
  el esquema, los triggers y el comportamiento de PostgREST sin
  ilusiones de mock.
- 2026-05-24 — Mockup `Curso Detalle.html` + `curso-detalle.jsx`
  (23-may) descartado y movido a `mockups/_old/`. La versión
  canónica del detalle de curso es `Detalle Curso.html` +
  `detalle-curso.jsx` (24-may), que además alinea el nombre con el
  patrón `Detalle X` / `Nueva X` del resto.
- 2026-05-24 — Agregado al `Mapa_del_Hub.md` el bottom sheet de
  filtros sobre Tareas (curso, categoría, prioridad, vencimiento).
  No es funcionalidad nueva: viene en `mockups/Filtros.html` y se
  documenta para que no quede como "asumido" al construir Tareas.
- 2026-05-24 — En Capa 1 cada `profile` se trata como entidad CRUD
  normal (la BD admite múltiples filas). La regla "una sola fila"
  vive en la app móvil: la crea una vez al primer arranque. Si más
  adelante hace falta, se agrega un endpoint `GET /profile/me` o
  un constraint en la BD.
- 2026-05-24 — Tokens visuales aprobados; sólo dark theme en Capa 1.
  El outlier `cardHi #1F2542` de `modal-borrar.jsx` se normalizó al
  estándar `#1B2138` para tener una sola fuente de verdad. Si hace
  falta una variante explícita para modales sobre scrim, se agrega
  como token aparte.
- 2026-05-24 — Fuentes Inter y JetBrains Mono se cargan vía paquete
  `google_fonts` (descarga + caché en disco), no como TTFs
  embebidos. Pro: cero archivos en el repo; contra: la primera
  carga necesita red. Si más adelante molesta el flash inicial, se
  cambia a TTFs en `assets/fonts/`.
- 2026-05-24 — Capa 1 no usa librería de estado todavía
  (`provider` / `riverpod` / `bloc`). Las pantallas son
  `StatefulWidget` + `FutureBuilder` vía `AsyncView<T>`. Si al
  llegar al Paso 4 (Tareas con filtros/edición) se vuelve
  incómodo, se introduce el state mgmt antes de los siguientes
  pasos.
- 2026-05-25 — **State management**: Riverpod entra desde el inicio
  del Paso 4.B (no se empieza con `StatefulWidget+FutureBuilder` para
  migrar después — sería propagar churn). Se usa el patrón **clásico**
  (`Provider`, `FutureProvider`, `NotifierProvider`) en lugar de
  codegen con `@riverpod` — mismo Riverpod, sin tener que correr
  `build_runner` antes de cada `flutter build`. Las deps
  `riverpod_annotation` y `riverpod_generator` quedan en el `pubspec`
  por si se decide migrar a anotaciones más adelante.
- 2026-05-25 — `ultima_actividad_en` de `proyectos` se asigna desde
  el cerebro (Python `datetime.now()`) tanto en POST como en PATCH,
  no se delega al `default now()` de Postgres. Razón: el reloj del
  cerebro y el de Supabase pueden discrepar por segundos y la
  comparación de strings ISO 8601 puede salir "al revés"; con el
  cerebro asignándolo en ambos lados, las comparaciones son
  monotónicas. `creado_en` y `actualizado_en` siguen viniendo del
  reloj de Postgres como antes — no se comparan con timestamps del
  cerebro.
- 2026-05-26 — **Dos fixes críticos para APK release** (descubiertos
  al instalar la release en el Huawei real):
  1. **INTERNET permission faltante en release**. Flutter SOLO
     añade `android.permission.INTERNET` automáticamente en builds
     debug y profile (vía `android/app/src/debug/AndroidManifest.xml`
     y `src/profile/AndroidManifest.xml`). El manifest **main** lo
     necesita explícito o la APK release no puede abrir sockets →
     `SocketException: Operation not permitted (errno=1)` en cada
     request. Añadido al manifest principal.
  2. **Cleartext HTTP a localhost bloqueado**. Android 9+ bloquea
     cleartext por política de seguridad. Creado
     `res/xml/network_security_config.xml` que permite cleartext
     SOLO para `localhost`, `127.0.0.1`, `10.0.2.2` (dominios de
     desarrollo). El resto sigue exigiendo HTTPS — sin debilitar la
     app cuando Capa 2 hable con Anthropic/Supabase.
  Tras los dos fixes la APK release carga datos del seed en
  Inicio, Proyectos, Tareas, Universidad y Calendario sin errores.
- 2026-05-26 — **Cierre final de Capa 1**. Tres mejoras grandes
  cierran la mecánica del Documento Maestro:
  - **Acción siguiente del proyecto en UI**: `DetalleProyectoScreen`
    muestra la tarea siguiente como bloque destacado con dos botones
    (Marcar hecha → abre selector próxima · Cambiar). El selector
    es un bottom sheet con las tareas pendientes del proyecto.
  - **Detección de choques de horario**: módulo `domain/choque.dart`
    con `seSolapan(...)` puro (6 tests). Integrado en
    `CalendarioScreen` — eventos que pisan otras filas (eventos o
    clases recurrentes) salen con badge rojo CHOQUE + fondo rojo
    suave. El caso del Documento Maestro (clase L/Mi 20:15–21:45 vs
    box 21:00–22:00) se detecta solo.
  - **Cierres pasados colapsables**: sección al final de
    `CierreDiaScreen` con histórico (hasta 30) — fecha, items con
    check verde, nota extra en cursiva. Colapsada por defecto.
  Doc nueva `docs/Como_correr_Matix_desde_cero.md` con guía
  completa para levantar Matix desde una PC nueva.
  Tests: cerebro 46/46, flutter 19/19.
- 2026-05-26 — **Notificación diaria del cierre del día**. Nuevo
  método `programarDiaria` en `NotificacionesService` usa
  `matchDateTimeComponents: DateTimeComponents.time` para que el
  plugin la repita cada día a las 21:30 sin tener que reprogramarla.
  Toggle en `AjustesScreen` → sección "Rituales" → Switch
  "Recordarme el cierre del día". Id estable `1001` para poder
  cancelarla sin persistir nada (se detecta si está activa
  preguntando a `pendientes()`). Limpieza colateral:
  `mockups/_old/` borrado.
- 2026-05-26 — Mockup `inicio.jsx` repulido con datos reales:
  header con 5 iconos (lupa, calendario, apuntes, **luna del
  cierre**, ajustes), MatixCard con alerta de Shadows Games en
  riesgo, "Para hoy" / "Próximas entregas" / "Tu día" con cursos
  reales del DM y horario del martes. `Mapa_del_Hub.md` añade
  sección 8 (Cierre del día) y detalle del acceso a Búsqueda.
  `CLAUDE.md` §4 sincronizado.
- 2026-05-25 — **Datos demo cargados + bug crítico cazado**.
  Script `cerebro/scripts/seed_demo.py` (idempotente por nombre)
  pre-pobló la BD del proyecto matix con los datos del Documento
  Maestro: 7 cursos universitarios, 13 sesiones del horario semanal
  exacto, 3 categorías generales y los 3 proyectos activos +
  3 aparcados (Matix #1, OnExotic #2, Shadows Games #3 / Peyo,
  Idiomas, Automatizaciones). De paso destapó que el endpoint del
  cerebro era `/sesiones-clase` (con guión), no `/sesiones_clase`,
  y mi `CursosRepository` en Flutter usaba el path equivocado. Sin
  este fix, las sesiones recurrentes en el Calendario nunca habrían
  cargado. Arreglado en ambos lados.
- 2026-05-25 — **Cierre del día (ritual nocturno)** del Documento
  Maestro sección 7. Migración 0003 con tabla `cierres_dia` (fecha
  unique, items text[], nota_extra opcional). Endpoint
  `/api/v1/cierres_dia` con UPSERT: POST a una fecha ya cerrada
  actualiza el cierre existente, no duplica. Pantalla
  `CierreDiaScreen` accesible desde el icono de luna en Inicio:
  campos numerados (mínimo 1, sugerencia 3), botón "Añadir otra",
  espacio para "Algo que te haya rondado". Tono empático: "No
  tiene que ser épico. Cualquier paso real cuenta." Test cerebro
  cubre CRUD + UPSERT (46/46 verde).
- 2026-05-25 — **Segunda mega-tirada**:
  - **Búsqueda global** (`features/busqueda/`): pantalla con
    TextField + resultados agrupados (Proyectos, Tareas, Apuntes,
    Cursos), filtro en cliente sobre providers cacheados. Acceso
    desde el icono lupa en Inicio.
  - **Sesiones de clase recurrentes en Calendario**: las clases del
    horario semanal aparecen en el calendario sin que el usuario
    cree eventos. Domain `SesionClase` + repositorio + provider
    `sesionesDelDiaProvider`. Cards marcadas con badge "SEMANAL".
  - **Repetición de tareas al completar** (cerebro): al marcar como
    completada una tarea con `repeticion` (diaria/semanal/mensual/
    anual), el cerebro crea automáticamente la próxima instancia
    con `vence_en` y `recordar_en` desplazados. 2 tests nuevos
    verifican el comportamiento. 45/45 verde en cerebro.
  - **UX pulidos**: validación `recordar_en < vence_en` en
    `NuevaTareaScreen`; pedir permiso runtime de notificaciones
    proactivamente la primera vez que se programa una notif
    (tareas, eventos y evaluaciones); cuerpo de notif ya legible
    con vencimiento humano.
- 2026-05-25 — **Mega-tirada autónoma**: construidos Pasos 5, 6, 7,
  8, 9 + extensión 11 + apertura 10. Estructura agregada:
  `features/proyectos/`, `features/eventos/`, `features/cursos/`,
  `features/evaluaciones/`, `features/universidad/`,
  `features/apuntes/`. Pantallas nuevas: ProyectosListScreen,
  DetalleProyectoScreen, NuevoProyectoScreen (con bloqueo del tope),
  CalendarioScreen (grid mensual + lista del día), NuevoEventoScreen,
  UniversidadScreen (lista cursos), DetalleCursoScreen (promedio +
  próximas + historial), NuevoCursoScreen, NuevaEvaluacionScreen,
  ApuntesListScreen, EditorApunteScreen. InicioScreen reescrita
  como panel del día real (3 proyectos activos, Para hoy, Próximas
  entregas, Tu día) con acceso a Calendario/Apuntes/Ajustes desde
  el AppBar. Notificaciones integradas con tareas, eventos y
  evaluaciones. Stubs muertos eliminados. 13/13 tests Flutter
  verde, analyze clean. La app pasa de tener 1 sección real
  (Tareas) a tener todo el armazón funcional de Capa 1.
- 2026-05-25 — **Optimización del listado de subtareas**. Antes el
  endpoint `/api/v1/subtareas` devolvía TODAS las subtareas de la
  BD y el provider de Flutter filtraba en cliente por `tarea_id`.
  Ahora el endpoint acepta `?tarea_id=<uuid>` (vía
  `db.list(filters=...)` que ya existía desde 4.A) y el cliente
  solo recibe las que necesita. Test nuevo
  `test_listar_filtrado_por_tarea_id` verifica que no devuelve
  subtareas de otras tareas. Total: 43/43 verde en cerebro.
- 2026-05-25 — Pequeño cumplimiento de regla propia: el provider
  derivado de tareas en `tareas_list_screen.dart` ahora muestra
  `e.message` cuando el error es `MatixApiException`, y solo cae a
  `e.toString()` para errores genéricos. La regla la habíamos
  documentado en `features/tareas/README.md` ("no parsees
  `e.toString()` para mostrar errores"), tocaba aplicarla.
- 2026-05-25 — Pulido infraestructura: `MatixClient` con timeout
  configurable (10 s CRUD, 5 s health) — antes solo `/health`
  tenía timeout y un cerebro caído colgaba la UI indefinidamente.
  `.env.example` ampliado con `SUPABASE_ACCESS_TOKEN` y
  `SUPABASE_PROJECT_REF` para futuras migraciones. `.gitignore`
  añade `matix_*.png` (screenshots de debug por `adb screencap`) y
  `hs_err_pid*.log` (JVM crash dumps de Gradle). 9 PNGs basura
  borrados de la raíz.
- 2026-05-25 — `Plan_Capa1.md` actualizado: Paso 11 marca como
  hechos los tres sub-pasos ya implementados; queda pendiente la
  petición runtime del permiso (Android 13+) y replicar el patrón
  a `eventos` y `evaluaciones`. Paso 10 marca como adelantado el
  trabajo de Ajustes.
- 2026-05-25 — **Integración Notificaciones ↔ Tareas (Paso 11
  parcial)**. `TareasRepository` ahora recibe el `NotificacionesService`
  y lleva la sincronización en sus métodos: `crear` programa (si
  hay `recordar_en` futuro), `actualizar` y `marcarCompletada` hacen
  cancel+reprogramar (idempotente), `borrar` cancela. El cuerpo de
  la notificación se calcula a partir de `vence_en` ("Vence hoy a
  las 14:30", "Vence mañana a las…", "Vence en N días"). El id de
  notificación se deriva del uuid de la tarea vía
  `core/notif_id.dart` (primeros 7 hex = 28 bits → cabe en
  Integer.MAX_VALUE, estable entre runs, colisión <1/268M). Sin
  cambios en UI. Tests: 13/13 verde (añadidos 4 de `notifIdDe`).
- 2026-05-25 — Limpieza pubspec: removidos `riverpod_annotation`,
  `riverpod_generator` y `build_runner`. Quedaron sin usar tras la
  decisión "Riverpod clásico, sin codegen" (2026-05-25). Se quitaron
  42 dependencias transitivas.
- 2026-05-25 — **Bug fix de producción detectado por test**:
  `DateFormat('...', 'es')` en `TareasListScreen` lanzaba
  `LocaleDataException` en dispositivos sin locale 'es' pre-cargado
  (mi Huawei sí lo trae, pero no es garantía). Se añadió
  `initializeDateFormatting('es', null)` en `main.dart` antes de
  `runApp`. Lo descubrió el `widget_test.dart` al pumpear `MatixApp`
  fuera del path `main`.
- 2026-05-25 — Tests Flutter del lado app: `9/9 verde` (`flutter
  test`). Cubren la lógica pura de `tareasFiltradasProvider` (vistas
  hoy / todas / completadas, filtros por prioridad / proyecto, orden
  vencidas primero, `FiltrosTareasNotifier.limpiar()`) más dos
  smoke-widget tests que validan el bottom nav y la navegación
  básica.
- 2026-05-25 — Plantilla del Paso 4.B documentada en
  `app/lib/features/tareas/README.md` para que el Paso 5 (Calendario)
  y siguientes la copien al pie de la letra cuando el usuario apruebe.
- 2026-05-25 — `MatixClient` ahora decodifica el `detail` JSON de
  FastAPI antes de lanzar `MatixApiException`. Cuando el cerebro
  responde 409 con `{"detail": "Ya tienes 3 proyectos activos: aparca
  o termina uno primero."}`, el `e.message` que ve la UI ya es el
  texto plano — antes era el JSON crudo. También maneja el formato
  de lista 422 de Pydantic (une los `msg` con " · ").
- 2026-05-25 — **Setup parcial del Paso 11 (Notificaciones
  locales)** sin integrarlo a Tareas (esa integración espera a luz
  verde de 4.B). Se añadieron al `pubspec` las deps
  `flutter_local_notifications: ^17.2.4` y `timezone: ^0.9.4`. El
  `AndroidManifest` declara `POST_NOTIFICATIONS`,
  `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM` y
  `USE_EXACT_ALARM`. Servicio aislado en
  `app/lib/core/notificaciones_service.dart` con `inicializar()`,
  `pedirPermisos()`, `programar(id, titulo, cuerpo, cuando)`,
  `cancelar(id)`, `cancelarTodo()`, `pendientes()`. Decisiones del
  servicio: zona horaria fija `America/Lima` (Capa 4+ se podría leer
  del perfil); `AndroidScheduleMode.inexactAllowWhileIdle` para
  evitar pedir el permiso extra de alarmas exactas (se cambia a
  exact si la imprecisión molesta); la repetición de tareas la
  maneja el cerebro creando una nueva fila al completar, no el
  servicio. La integración real desde TareasRepository / Eventos /
  Evaluaciones se enchufa en el Paso 11 oficial.
- 2026-05-25 — Mockups del Paso 9 (Proyectos) redactados como
  borrador para revisión del usuario: `Proyectos.html` (lista con los
  3 activos del Documento Maestro, aparcados y terminados),
  `Detalle Proyecto.html` (línea de meta editable, acción siguiente
  con CTA "marcar hecha", meta-rows estado/bloque protegido/última
  actividad, footer "Aparcar / Terminar"), `Nuevo Proyecto.html`
  (vista "tope alcanzado": banner ámbar + lista de los 3 activos con
  acciones "Aparcar/Terminar" antes de habilitar el form). El
  placeholder anterior se reemplazó por la pantalla real.
- 2026-05-25 — Coherencia "acción siguiente ↔ proyecto" en el router:
  si se acepta una tarea libre como `tarea_siguiente_id`, el cerebro
  también la **vincula** al proyecto (le pone `proyecto_id`). Sin
  esto, un proyecto podía apuntar a una acción siguiente que no
  figuraba entre sus tareas.
- 2026-05-25 — Rediseño del bottom nav alineándolo con
  `mockups/matix-nav.jsx`: 5 pestañas con **Matix elevado al
  centro** (FAB con gradiente azul→púrpura). Disposición:
  Inicio · Proyectos · Matix(centro) · Tareas · Universidad.
  Calendario y Apuntes salen de la barra y se accederán desde
  otras pantallas (Calendario desde Inicio; Apuntes desde
  Universidad y Proyectos). El FAB lateral de mic se difiere a
  la Capa 2. Cambios: `home_shell.dart` (bottom nav custom),
  nuevos stubs `matix_screen.dart` y `proyectos_screen.dart`,
  `matix-nav.jsx` (añade Proyectos, reordena), `inicio.jsx`
  (limpia `BottomNav()` muerto), nuevos `Proyectos.html` +
  `proyectos.jsx` como placeholder.

---

## Convenciones que NO deben regresar (bugs de raíz cerrados)

- **Agregar al día = SIEMPRE Tarea, nunca Evento pelado** (2026-06-07). El único
  camino canónico es `horario.agendar_plan` (endpoint `/horario/agendar`,
  repo `HorarioRepository.agendar`): cada bloque tentativo engancha su Tarea
  (existente vía tarea_id, promovida vía set_item_id, o creada nueva) a su
  bloque_inicio/fin, reusando el modelo Tarea↔bloque. Así aparece en Tareas Y en
  Tu día. Se ELIMINÓ `empujar_a_calendario` (insertaba eventos pelados — era el
  bug recurrente). Los EVENTOS solo nacen por la ruta explícita de evento fijo
  (clase, gym / NuevoEventoScreen). La captura rápida ya creaba tarea/apunte.
- **Refresco sistémico**: toda mutación (crear/agendar/completar/posponer/saltar)
  llama a `invalidarHub` (Tareas + Tu día + rollover + Proyectos). Nada de
  estados rancios: el ítem aparece al instante sin refresco manual.
- **Scroll**: TODA pantalla scrolleable reserva `MatixLayout.scrollBottom(ctx)`
  como `padding.bottom` (= inset del sistema + alto de la barra inferior +
  holgura; `conRobot:` añade el robot flotante en Inicio). El bug era que el
  guard leía solo el `viewPadding` y olvidaba el alto de la barra (~64) → cortaba
  el último ítem (p. ej. el domingo del calendario semanal). Pantalla nueva
  hereda la convención (o usa `PantallaScroll`).

## Pendientes y dudas abiertas

- Norte de 2.0 — capa de comandos unificada: ver docs/Matix_2.0_Norte_Capa_de_Comandos.md.
- La pantalla de chat con Matix es de Capa 2; no se diseña ahora.
- Hay un segundo proyecto Supabase en la organización (el viejo
  `xapqlnyzblhnhnnvttyy`). El plan free permite 2 proyectos, así
  que no urge; el usuario puede borrarlo cuando quiera desde el
  panel.
- **Rotación de credenciales pendiente** (quedaron expuestas en el
  chat durante la aplicación de la migración): access token de
  Supabase `sbp_4fa97…1bf4d5` y DB password del proyecto matix.
  El usuario rotará más adelante. Cuando lo haga, además debe
  copiar el `service_role` key al `cerebro/.env`
  (`SUPABASE_SERVICE_ROLE_KEY=`, ahora vacío).

---

## Cómo retomar

1. Leer `CLAUDE.md` (visión y reglas), `docs/Mapa_del_Hub.md` (qué
   hay en cada pantalla) y `docs/Plan_Capa1.md` (plan de la capa).
2. Leer este archivo: ver qué paso tiene `→` y qué casillas faltan
   en él.
3. Continuar por el siguiente `·` del paso en curso.

---

## Capa 2 — bitácora detallada

### Paso 1 — Chat solo texto (2026-05-26)

- Decisión: **OpenAI como único proveedor LLM**. La llamada vive
  aislada en `cerebro/app/matix/llm.py`; ningún otro módulo importa
  `openai`. Si en el futuro hay que mover a Claude/Gemini/local, se
  reescribe ese archivo y nada más.
- `cerebro/app/matix/` con `__init__.py`, `llm.py`, `system_prompt.py`,
  `contexto.py`, `chat.py`. El system prompt = reglas/tono + el
  `Documento Maestro` literal. El contexto vivo va aparte por turno
  con proyectos activos + sus ids, tareas hoy/vencidas, eventos,
  cursos. Prompt caching automático de OpenAI lo aprovecha (prefijo
  estable ≥1024 tokens).
- `POST /api/v1/matix/chat` devuelve `{respuesta, tools_usadas,
  tablas_cambiadas}`. La app usa los dos últimos para invalidar
  providers (los chips verdes y refresh del hub).
- Flutter: `features/matix/` con domain/data/providers/presentation.
  Pantalla de chat real con burbujas, "Matix está pensando…",
  reintentar inline, limpiar conversación. Stub `MatixScreen`
  eliminado.

### Paso 2 — Tool calling, primera tanda (2026-05-26)

- 6 tools aditivas/reversibles: `crear_tarea`, `crear_evento`,
  `crear_apunte`, `completar_tarea`, `marcar_accion_siguiente_hecha`,
  `registrar_cierre`. `reabrir_tarea` se sumó casi en el acto como
  escape hatch (la voz puede malinterpretar y completar por error).
- `cerebro/app/matix/tools.py`: `TOOL_DEFINITIONS` (schemas JSON
  Schema) + `ejecutar_tool(db, name, args)` dispatcher. Cada handler
  valida con Pydantic, atrapa excepciones y devuelve `{ok, ...}` o
  `{ok: false, tipo, mensaje, sugerencia}` — nunca un error HTTP
  crudo.
- `chat.py` reescrito como loop modelo↔tools con tope de 6 vueltas.
- `system_prompt.py` reescrito: lista de tools, regla "Capa 2 = solo
  conversación" REEMPLAZADA por la lista de capacidades, y "lo que
  todavía no podés hacer". Regla nueva: si faltan datos, preguntar,
  no inventar.
- Contexto vivo expone ids inline (`id=...`) para que el modelo pueda
  citarlos en tool calls sin alucinarlos.
- Flutter: chip de acciones bajo cada turno de Matix ("Tarea
  creada", "Apunte guardado"…). El `ChatMatixNotifier` invalida los
  providers de las tablas afectadas tras cada turno.

### Paso 3 — Voz de entrada con Whisper (2026-05-26)

- `POST /api/v1/matix/transcribir` recibe multipart `audio/mp4`,
  llama a Whisper, devuelve `{texto}`. Validación: 400 si vacío,
  413 si >24 MB, 503 si no hay OPENAI_API_KEY, 502 si Whisper
  rechaza.
- Flutter: `record ^5.2.1` + `permission_handler ^11.3.1` +
  `path_provider`. AAC mono 16 kHz a 32 kbps (compacto y nítido).
- Botón mic en el composer del chat; estados visuales `idle ·
  grabando · transcribiendo · error`. La transcripción cae en el
  input, NO se manda sola — el usuario revisa y aprieta enviar.
- Dependency override de `record_linux: 1.3.1` por desfasaje de
  versiones transitivas con `record_platform_interface 1.6.0` en el
  build de Android (afecta el bundle aunque no se use Linux).

### Paso 4 — Modo manos libres con TTS (2026-05-26)

- Bucle: escuchar → transcribir → pensar → hablar → repetir, con
  detección de silencio del lado app para auto-cortar al final de
  cada turno.
- Pantalla overlay con indicador de fase + animaciones + cards de
  los dos últimos mensajes.
- TTS inicial: `flutter_tts` ^4.2.0. AndroidManifest declara
  `TTS_SERVICE` intent para Android 11+. Voz `es-ES` por defecto.

### Paso 5 — Hub indulgente + capacidad total + medidor (2026-05-27)

- **Borrado suave**. Migración `0004_papelera.sql` añade
  `eliminado_en timestamptz` a `tareas`, `eventos`, `apuntes` +
  índices parciales. Routers reescritos: `GET ?papelera=true`,
  `DELETE` ahora soft, `POST /{id}/restaurar`, `DELETE /{id}/permanente`
  (la única destructiva, no expuesta como tool).
- `contexto_vivo` filtra eliminados — Matix no ve la papelera.
- **Medidor de uso** (`matix/uso.py`): singleton thread-safe.
  Captura `usage` de chat (incluye `cached_tokens`), estima
  segundos de Whisper, cuenta chars de TTS. Costo USD con tarifas
  como constantes editables. `GET /api/v1/matix/uso` lo expone.
- **18 tools** (suma 11 nuevas): crear/editar/completar/reabrir/eliminar
  tareas; crear/editar/eliminar eventos y apuntes; crear/editar +
  aparcar/terminar/reactivar proyectos (con tope de 3 enforced);
  `marcar_accion_siguiente_hecha`; `registrar_cierre`.
- System prompt extendido: ahora Matix puede hacer todo salvo
  vaciar la papelera, y la regla "si falta info, preguntá — no
  inventes ni sustituyas" cubre el escape hatch crítico.
- Flutter: repositorios con `listarPapelera()`, `restaurar(id)`,
  `borrarPermanente(id)`. Pantalla `PapeleraScreen` en Ajustes →
  Hub con secciones por entidad y "Vaciar papelera" con doble
  confirmación. Snackbar "Deshacer" tras completar/borrar (`core/
  undo_snackbar.dart`). Banner medidor sobre el chat. Chips
  ampliados a 18 etiquetas.

### Paso 5.1 — Correcciones (2026-05-27)

- **Limpieza BD**. Borrados 3 proyectos `_test_*` huérfanos.
- **Aislamiento tests**. Conftest reescrito: fixture session-level
  `_barrer_residuos_test` que barre `_test_*` / `test_*` al cerrar.
  Audit de cleanups → todos los `delete` de tareas/eventos/apuntes
  ahora usan `/permanente`. Soporte para `.env.test` que apunta a
  un proyecto Supabase aparte (cargado antes de importar
  `app.config`). Sin `.env.test` cae al `.env` real con las redes
  de seguridad. Documentado en `docs/Plan_Capa2.md` y
  `cerebro/.env.test.example`.
- **Bug medidor banner**: la lógica `vacio` lo escondía cuando el
  contador era cero o cuando el endpoint cargaba lento. Ahora el
  banner se muestra SIEMPRE con su estado actual (cargando · error
  · cero · datos). Marco visual estable.
- **Bug vaciar papelera**: `Future.wait` propagaba la primera
  excepción y abortaba sin invalidar. Reescrito con try/catch por
  item + snackbar con `okCount` / `failCount`.
- **VAD de dos fases** en `grabacion_voz_service.dart`: fase 1
  espera la primera voz (-30 dB) hasta 6s; si no llega, devuelve
  `sinVoz` y nada va a Whisper. Fase 2 corta tras 1.3s de
  silencio sostenido o tope de 60s.
- **Estado "en pausa"** en manos libres: por silencio sin voz o
  por botón "Pausar" manual. Mic CERRADO; un completer espera a
  `reanudar()` para arrancar otra ronda.
- **Filtro de alucinaciones de Whisper** en `llm.py`:
  `_es_alucinacion_de_whisper()` descarta "Subtítulos ... Amara.org",
  "[Música]", "♪", repeticiones de la misma frase, solo signos. El
  endpoint devuelve `""` y el modo manos libres reanuda sin
  contaminar a Matix.
- **Voz onyx (OpenAI TTS)**. Razón: el motor TTS del Huawei solo
  expone voces femeninas en es-ES que suenan sintéticas. Cambiamos
  `flutter_tts` por `audioplayers` + `POST /api/v1/matix/voz` (cerebro
  llama a `tts-1`). Costo despreciable (~$0.003/respuesta). La API
  key sigue solo en el cerebro. Medidor extendido para trackear
  TTS chars.
- **Pantalla manos libres rehecha**: transcript scrolleable (mismo
  historial que el chat normal, sin recortes con `...`), indicador
  compacto, botones contextuales "Pausar" / "Hablar" / "Detener" /
  "Salir".
- **Tool `consultar_uso`** (solo lectura): Matix puede responder
  "¿cuánto he gastado?" leyendo el medidor.
- Cobertura de tests aumentada: `test_matix_tools_extra.py` (7
  tests), `test_matix_uso_endpoint.py` (2), `test_whisper_alucinaciones.py`
  (8). Total cerebro: 105 tests verdes.

---

## Decisiones acumuladas de Capa 2

- LLM provider: **OpenAI**. Único, aislado en `matix/llm.py`.
- Modelo de chat: **gpt-4o-mini**. Costo bajo, calidad suficiente.
  Cambiar a `gpt-4o` solo si la calidad se queda corta.
- Modelo de transcripción: **whisper-1** con `language="es"` fijo.
- Modelo de voz: **tts-1 con voz `onyx`** (masculina grave). `tts-1-hd`
  cuesta el doble y la diferencia perceptual es menor.
- Borrado en `tareas`, `eventos`, `apuntes`: **soft delete** via
  `eliminado_en`. Hard delete solo desde la UI vaciando la papelera.
- Proyectos: ciclo de vida `activo / aparcado / terminado` — no
  entran a la papelera. El tope de 3 activos vive en el cerebro
  (`crear_proyecto` y `reactivar_proyecto` lo enforce-an).
- Medidor de uso: **en memoria, sin persistir**. Si se reinicia el
  cerebro vuelve a cero. Es consumo de sesión, no histórico.
- Detección de silencio del lado app (VAD por amplitud), filtro de
  alucinaciones de Whisper del lado cerebro. Doble red.
