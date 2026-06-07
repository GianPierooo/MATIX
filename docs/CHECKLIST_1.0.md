# Checklist Matix 1.0

Foto honesta de qué cierra la versión 1.0, sacada cruzando el inventario de
`docs/ESTADO.md` con el código real del repo. Es el archivo de referencia para
preguntarle a Matix en chat "qué falta para 1.0" / "qué me sugieres atacar
ahora". Lo mantiene el flujo estándar (ver regla §0.9 de `CLAUDE.md`): cada
prompt que cierra o destapa un ítem mueve la línea entre secciones acá.

**Definición de "1.0":** Matix es el hub diario del usuario, usable a fondo en
device, con el chat de Matix como puerta principal (texto + voz), las capacidades
de scheduling y rollover trabajando el tiempo de verdad, y validación en device
estable. **NO** entra polish de UI/animaciones ni features de capas posteriores
(RAG sobre código, casa inteligente, sincronía bidireccional con servicios
externos más allá del calendario Google que ya está parcial). La meta es
"sólido y honesto para uso diario", no "perfecto".

Marcas: ✅ Hecho · ⚠️ Parcial (sirve pero le falta algo concreto) · ❌ Falta ·
↩️ Post-1.0 (consciente y explícito).

---

## ✅ Hecho (capacidades cerradas)

### Hub diario y CRUD
- ✅ Esquema de datos completo (`supabase/migrations/0001 → 0038`).
- ✅ Navegación principal (`home_shell` · 5 pestañas + secciones fuera de barra).
- ✅ CRUD completo en device: tareas, eventos, apuntes, proyectos, finanzas,
  cursos/clases, evaluaciones, cuadernos, categorías.
- ✅ Papelera + restaurar + borrado permanente para tareas/eventos/apuntes.
- ✅ Notificaciones locales + push (FCM) con scheduler cada minuto.
- ✅ Widgets de pantalla de inicio Android ("Próximo" + "Hoy", RemoteViews):
  la app empuja el plan determinista vía home_widget; solo lectura + deep link
  (marcar hecho es Fase 2). Refresco on-change + WorkManager. Render nativo se
  valida en dispositivo.
- ✅ Rendición de cuentas con botones de acción (app cerrada): tareas
  "¿Hiciste X?" (Sí / No, mañana / No, más tarde) + asistencia a eventos fuera
  de casa "¿Fuiste a X?" (Sí fui / No fui / Reprogramar). Alimentan el motor de
  evolución (tasas de cierre + asistencia).
- ✅ Intensidad graduable de los avisos (dial Ajustes: suave/medio/intenso/
  máximo, default intenso) → mecanismos Android (heads-up / persistente /
  full-screen) con canales por importancia; re-alerta escalada por intensidad;
  silencio nocturno gatea todo (ni el máximo dispara full-screen de noche).
  MagicOS: guía honesta (batería + full-screen intent + autoarranque). Lo
  nativo de timing/entrega es de dispositivo (no corre en CI).

### Chat con Matix (Capa 2)
- ✅ Chat de texto con tool-calling (83 tools del hub).
- ✅ Voz de entrada (Whisper `whisper-1`, filtro de alucinaciones).
- ✅ Modo manos libres con TTS (OpenAI `tts-1` voz `onyx`).
- ✅ Selección de modelo OpenAI/Anthropic (auto-router por mensaje).
- ✅ Memoria personal + memoria conversacional con recall semántico.
- ✅ TTS desacoplado y async con reintentos (no tumba cámara ni chat).
- ✅ Red anti-markdown en el chokepoint del display (asteriscos muertos).

### Wake word
- ✅ Pipeline ONNX local (`oye_matix.onnx`) en primer plano y en foreground
  service nativo (segundo plano).
- ✅ Entrenamiento de voz del usuario (pantalla + endpoints).
- ✅ Multi-window: `resizeableActivity=true` + `configChanges` completo —
  funciona como ventana flotante sobre un juego sin recrear.
- ✅ Overlay flotante al disparo (gated default-OFF; opt-in en Ajustes con
  permiso `SYSTEM_ALERT_WINDOW`; degrada honesto a fullscreen).

### Cámara en vivo
- ✅ Sesión continua con muestreo inteligente (cambio de escena + topes de
  frames/min, duración, auto-stop).
- ✅ Narración por frame (gpt-4o-mini detail=low) + TTS no bloqueante.
- ✅ Reintentos transitorios en `narrar-frame` y en TTS (502/timeout no la matan).
- ✅ Ritmo en vivo sin trabas: captura/visión desacopladas (último frame gana,
  sin cola), una sola petición de visión en vuelo, TTS interrumpible por época
  (nada de audio viejo acumulado), timeout agresivo por proveedor (~3.5 s) +
  failover rápido respetando el proveedor pinneado, e indicador "mirando…".

### Planificación / scheduling
- ✅ Vista «Hoy» (timeline del plan) en Inicio.
- ✅ Plan del día determinístico (`/horario`) con ventanas libres, colocación
  del set en el pico (trabajo profundo) y skills/tareas en ventanas ligeras.
- ✅ Transición tras compromisos fuera de casa (clase / evento con ubicación):
  buffer configurable (`config_horario.transicion_min` default 1h + override por
  evento, migración 0043) donde NO se coloca trabajo de casa.
- ✅ Ningún proyecto activo sin acción siguiente: si no quedó en el set ni con
  tarea de hoy, se deriva el siguiente paso del árbol o se sintetiza "Definir el
  siguiente paso de X" (mata el bug "0%, sin acción").
- ✅ Apartado «Huecos libres» en Tu día: ventanas libres legibles con UNA
  sugerencia dosificada que de verdad cabe por hueco (motor determinista del
  cerebro, instantáneo y sin tokens).
- ✅ Práctica de skill SIEMPRE tentativa (nunca fija): `anclas_fijas` excluye
  las anclas que son skill → liberan el pico para trabajo de proyecto.
- ✅ Backlog vivo: tareas sin fecha se ofrecen como tier ligero al final;
  el robot las surfacea ("tienes N sin fecha, ¿las acomodo en un hueco?").
- ✅ Set del día con propuesta a hora configurada + escalación dosificada.
- ✅ Rollover de tareas no cumplidas + guardrail honesto anti-acumulación
  ("ya no es de mover de día, toca re-escopar / bajar la carga").
- ✅ Modelo Tarea↔bloque enlazado: completar desde cualquier surface
  sincroniza tareas + plan + rollover + set del día (`invalidarHub`).

### Robot-compañero (mascota)
- ✅ Avatar visible (halo + cuerpo claro · contraste real sobre el fondo).
- ✅ Tarjeta única con robot integrado (no dos cajas separadas; sombra
  completa; padding del ListView reserva espacio → no tapa contenido).
- ✅ Modo persona alineado a las ANCLAS del usuario (despertar/dormir),
  NO al horario de silencio de pings.
- ✅ Pool de mensajes ambiental con rotación, opciones tocables, captura
  rápida desde la burbuja, dosificado y minimizable.

### Proyectos / skills / evolución (mucho por chat)
- ✅ Perfil profundo de proyecto + entrevista (0029).
- ✅ Árbol de descomposición con elaboración progresiva (0030).
- ✅ Intake analítico con tipos + gate de meta medible + realismo (0032).
- ✅ Flag `es_skill` con tope blando aparte del de 3 proyectos (0034).
- ✅ Evolución/seguimiento: check-in semanal, hitos %, estancamiento +
  re-scope, adaptación al ritmo (0033).
- ✅ RAG/biblioteca de material por (skill, bloque) con embeddings + tool
  `buscar_material` (0015).

### Rituales y vistas
- ✅ Briefing matutino + Cierre del día + Repaso semanal.
- ✅ Búsqueda global, Memoria («Sobre mí»), Auto-update in-app.

### Teléfono (Capa 6)
- ✅ Fase 1: intents (abrir, llamar, SMS/correo prellenado, leer galería).
- ✅ Tier C.0: leer pantalla (accesibilidad, solo lectura).
- ✅ Tier C.1: enviar WhatsApp tras confirmación.

### Calidad e ingeniería
- ✅ Gate del CI verde: `flutter analyze --no-fatal-infos` + `flutter test`
  (app) y tests PUROS del cerebro (`uv run pytest`). Si el gate falla, el APK
  NO se construye ni publica.
- ✅ Auto-update in-app (APK release publicado en Supabase Storage).
- ✅ Toolchain local completo (Flutter 3.44.1 + uv + Android SDK 36.1 con
  licencias aceptadas + `flutter build apk --debug` end-to-end verde).

---

## ❌ Falta para 1.0

Las cosas que cierran el chat-como-puerta-principal y el "Matix sabe su propio
estado" — para que el dueño NO dependa de un advisor externo para saber qué
hay y qué falta.

### Auto-conciencia del propio estado
- ❌ Tool `obtener_cambios_recientes(n=10)` — el chat de Matix puede responder
  "qué se actualizó hoy / esta semana" leyendo commits reales del repo, no
  inventando. Necesario para los tres intents del chat de auto-conciencia.
- ❌ Exposición de `docs/ESTADO.md` y `docs/CHECKLIST_1.0.md` como contexto
  fresco del chat (cada turno los lee). Sin esto, "qué falta para 1.0" no
  puede responderse con datos reales.
- ❌ Regla en `CLAUDE.md` (auto-update al cerrar prompts que cambian
  capacidades o cierran ítems): debe vivir en §0 para que el flujo estándar
  la enforze (no como sugerencia suelta).

### Validación en device estable
- ⚠️ Vista «Hoy» (timeline): falta validación en device (lo apuntó el
  inventario · listada como "falta validación en device" en ESTADO §INVENTARIO).
- ⚠️ Overlay flotante del wake (multi-window): la lógica Dart y el manifiesto
  están testeados, pero **el comportamiento on-device** (render real de la
  burbuja sobre un juego, audio headless mientras el juego corre, "flash" al
  mandar Matix al fondo, audio focus) no se ha visto en pantalla todavía.

### Operación
- ⚠️ Migración `0038_rollover_tareas.sql` (`tareas.veces_reprogramada`):
  está commiteada pero NO confirmada aplicada en prod desde esta máquina (no
  hay token Supabase local). El código degrada sin ella (best-effort), pero
  el guardrail por repeticiones del rollover no cuenta hasta aplicarla.
- ❌ Rotación de credenciales que quedaron expuestas (ESTADO §Pendientes:
  access token Supabase + DB password). Bloqueante para "1.0 seguro".

### Limpieza honesta
- ⚠️ Tabla `tracks` legacy (código retirado en 2026-06-04 pero la migración
  con 1 fila de Calistenia quedó sin uso). Decidir si se DROPea con migración
  destructiva o se ignora; documentarlo.

---

## ↩️ Post-1.0 (consciente y explícito · NO entra a 1.0)

### Polish de UI / animaciones / cambios visuales
- ↩️ Animaciones más pulidas en la mascota (más allá del bob + brinco + parpadeo
  actual).
- ↩️ Transiciones de pantalla más cuidadas.
- ↩️ Iconografía custom (hoy se usan iconos del sistema).
- ↩️ Modo claro (la app vive bien en dark; no es 1.0).

### Features fuera del foco actual
- ↩️ Cámara en vivo "frame-perfect" en tiempo real (el muestreo actual con
  ~3s es deliberado y suficiente para 1.0).
- ↩️ Teléfono Tier B (automatización libre de tocar/escribir en apps
  arbitrarias). Tier C.1 alcanza para 1.0.
- ↩️ Google Calendar bidireccional COMPLETO (hoy es PARCIAL/temprano; alcanza
  para 1.0 como tile en Ajustes).
- ↩️ RAG sobre el código del repo (no es lo que pidió la versión 1.0; los dos
  archivos `ESTADO.md` + `CHECKLIST_1.0.md` van como contexto directo).
- ↩️ UI dedicada para árbol/perfil/intake de proyectos (hoy se operan por chat;
  funciona para 1.0).
- ↩️ UI para navegar la biblioteca de material (hoy se trae por chat).
- ↩️ Pantalla propia para skills (hoy se ven como proyectos).
- ↩️ Pantalla propia para automatizaciones (hoy se operan por chat).

### Capas posteriores
- ↩️ Capa 5 — casa inteligente (Home Assistant).
- ↩️ Capa 6 — PC y archivos: **6.0a + 6.0b + 6.1 HECHO** (agente local
  `agente_pc/`, canal WebSocket/TLS con secreto compartido, registry tipado, rails
  allowlist/denylist + traversal/symlink/TOCTOU + audit + kill switch). Lectura:
  listar, buscar, leer, resumir. Organización con gate (la app confirma): mover,
  renombrar, crear carpeta, organizar por tipo/fecha/proyecto. **Borrado** y
  **escritura** de contenido quedan post-1.0, con confirmación reforzada (ver
  `docs/Capa6_Agente_PC.md`).
- ↩️ Capa 7 — visión por cámara (la foto→apunte ya cuenta como Capa 7 parcial;
  el resto es post-1.0).
- ↩️ Capa 8 — proactividad en su versión final (ya hay base sólida con el
  motor de proactividad + rollover; "final" implica más triggers y aprendizaje
  de patrones del usuario · post-1.0).
