# Plan de la Capa 2 — Matix: chat y voz

**Estado al 2026-05-27**: Pasos 1–5 completos + Paso 5.1 de
correcciones. Quedan los Pasos 6 (rituales por voz), 7 (memoria
conversacional) y 8 (auth + presupuesto) — pendientes de
validación final del usuario sobre lo entregado y de las decisiones
de los planes complementarios (`Plan_Despliegue.md`,
`Plan_Rituales_Voz.md`, `Plan_Memoria_Conversacion.md`).

La Capa 2 termina cuando el botón central de Matix abre una conversación
real: el usuario habla o escribe, y Matix entiende, responde con voz y
**crea / edita / completa cosas del hub** (tareas, eventos, apuntes,
proyectos) por su cuenta. **Hito alcanzado de facto** al cerrar el
Paso 5.1 — falta validación del usuario y los pasos 6–8.

---

## Decisiones tomadas

1. **Proveedor LLM: OpenAI**. El usuario ya tiene su `OPENAI_API_KEY`
   en `cerebro/.env`. No es multi-proveedor.
2. **Llamada al modelo aislada en un módulo único**:
   `cerebro/app/matix/llm.py`. Toda la app del cerebro habla con ese
   módulo, no con OpenAI directo. Si en el futuro hay que mover a otro
   proveedor (Claude, Gemini, modelo local), se reescribe ese archivo y
   nada más cambia.
3. **System prompt** = `docs/Matix_Documento_Maestro_del_Usuario.md` ya
   tal cual, con prompt caching desde el día 1 para abaratar tokens.
4. **Tono** del Documento Maestro §9 va dentro del system prompt como
   reglas no negociables (duro con la tarea, jamás con la persona, etc.).
5. **Voz**: STT con Whisper API de OpenAI (mismo proveedor) en Capa 2
   inicial. ~~TTS con `flutter_tts` del sistema~~ → **TTS con OpenAI
   `tts-1` voz `onyx`** desde el Paso 5.1: el motor del dispositivo
   solo exponía voces femeninas robóticas en es-ES. Coste despreciable
   y la calidad gana de lejos.
6. **Borrado suave (Paso 5)** en `tareas`/`eventos`/`apuntes`. Vaciar
   la papelera = hard delete; única acción destructiva que existe y
   solo es accesible desde la UI, **nunca como tool de Matix**.
7. **Tope de 3 proyectos activos** vive en el cerebro (router CRUD y
   tools `crear_proyecto`/`reactivar_proyecto`). Si la regla se viola,
   la tool devuelve `{ok: false, tipo: "tope_proyectos"}` y el modelo
   traduce a lenguaje humano.

---

## Arquitectura

```
Flutter (Android)
   │  audio + texto
   ▼
FastAPI (cerebro local)
   │
   ├─ matix/contexto.py   (arma el contexto del hub)
   │
   ├─ matix/llm.py        ← ÚNICO PUNTO DE ENTRADA AL MODELO
   │                        (HTTP a OpenAI: chat, whisper)
   │
   ├─ matix/tools.py      (definiciones JSON Schema de tools)
   │
   └─ matix/chat.py       (loop: prompt → tools → ejecutar → repetir)
        │
        ▼
   CRUD existente (routers/) — sin tocar
```

- La app envía audio o texto a `POST /api/v1/matix/chat` y recibe
  audio + texto + lista de acciones ejecutadas.
- Las "acciones" son tool calls de OpenAI que el cerebro ejecuta
  contra el CRUD que ya existe en Capa 1.

---

## Stack nuevo

- `openai` Python SDK (oficial) en el cerebro.
- `record` o `speech_to_text` en la app para capturar audio.
- `flutter_tts` para reproducir la respuesta hablada.
- Caching: el SDK de OpenAI permite reutilizar `system` con `cache_control`
  desde el primer commit.

---

## Pasos de la Capa 2

### Paso 1 — Chat solo texto ✓ (2026-05-26)

Hecho. Detalle en `ESTADO.md` § "Capa 2 — bitácora detallada".
Endpoint `/api/v1/matix/chat`, system prompt cacheable + contexto
vivo por turno, pantalla `MatixChatScreen` con burbujas y reintentar
inline.

### Paso 2 — Tool use ✓ (2026-05-26, ampliado en Paso 5)

Primera tanda de 6 tools aditivas, ampliada en el Paso 5 a 18 tools
+ `consultar_uso` en 5.1 (19 total). Loop modelo↔tools con tope de
vueltas. Chips de confirmación en la UI.

### Paso 3 — Pantalla de chat ✓ (2026-05-26)

Hecho como parte del Paso 1. Burbujas + chips + composer.

### Paso 4 — Voz: capturar (STT) ✓ (2026-05-26)

`POST /api/v1/matix/transcribir`. Botón mic en el composer; la
transcripción cae en el input y el usuario la valida antes de
enviar (no se manda sola, para que un Whisper desviado no dispare
acciones).

### Paso 5 — Voz: responder (TTS) ✓ (2026-05-26 → 5.1 corregido)

Empezamos con `flutter_tts`; cambiamos a OpenAI TTS voz `onyx` en
5.1 por calidad (motor del Huawei solo expone voces femeninas
robóticas). Modo manos libres encadena STT → chat → TTS → STT con
detección de silencio en dos fases y estado "en pausa".

### Paso 6 — Briefing mañana + cierre del día por voz · pendiente

Plan detallado en `docs/Plan_Rituales_Voz.md` (2026-05-27).
Resumen: notificación programada a horas del usuario (`06:30`
briefing, `21:30` cierre) cuya tap-action abre el modo manos libres
con un prompt-seed distinto al neutro del chat normal — el cerebro
recibe `?modo=briefing|cierre` y el orquestador genera el primer
turno automáticamente sin esperar voz del usuario.

### Paso 7 — Memoria conversacional · pendiente

Plan detallado en `docs/Plan_Memoria_Conversacion.md` (2026-05-27).
Resumen del enfoque: tabla `mensajes_matix` para persistir + un
resumen rodante con LLM cuando se pasa el tope de turnos en
contexto. Decisión pendiente del usuario: definir el tope.

### Paso 8 — Endurecer auth + presupuesto · pendiente

Plan detallado en `docs/Plan_Despliegue.md` (2026-05-27) — incluye
el endurecimiento del acceso al cerebro hosteado (rate limit, JWT
con expiración si sale del teléfono personal, secreto rotado en
host). El logging de costes ya existe vía el medidor singleton del
Paso 5; el siguiente nivel es persistirlo y exponerlo en una
historia diaria.

---

## Por qué el módulo único

Cuatro razones que hacen que valga la pena el aislamiento:

1. **Cambio de proveedor sin churn**. Si en 6 meses sale GPT-5-turbo
   o Claude 5 con mejor relación calidad/precio, se reescribe
   `llm.py` y nada más.
2. **Testeable**: el resto del cerebro se puede testear con un
   `FakeLlm` que devuelve respuestas predecibles.
3. **Costes en un solo sitio**: logging de tokens y $ vive donde se
   hacen las llamadas, sin tener que perseguirlo por toda la app.
4. **Caching**: la lógica de prompt caching va en `llm.py`, no
   esparcida.

`llm.py` no debe filtrar tipos del SDK de OpenAI hacia el resto del
cerebro. Devuelve `dict`/`str` simples. El resto del cerebro no debe
saber qué proveedor está debajo.

---

## Tono y personalidad (sistema prompt)

Anclas del Documento Maestro §9:
- Tono adaptable según check-in inicial (cómo llegas hoy: energía /
  cansado / disperso). Matix elige entre directo-exigente y
  motivador-cálido.
- **Duro con la tarea, jamás con la persona.** Nunca insultos ni
  refuerzo del "no sirvo". Empuja el trabajo, no hunde a la persona.
- Honestidad: si el tema lo supera, sugiere apoyo de un psicólogo real
  (Documento Maestro §8). No finge ser terapeuta.
- Antes de acciones irreversibles (borrar, enviar correo): pide
  confirmación.

---

## Riesgos previsibles

- **Coste de OpenAI API**: visible. Prompt caching desde el día 1.
- **Latencia STT/TTS**: si supera 2 s la voz pierde naturalidad.
  Métrica clave desde el primer paso.
- **Permisos micrófono Android**: gestión runtime, fácil de olvidar.
- **Tool call que falla**: la conversación tiene que recuperarse con
  un mensaje legible, no con un crash.
- **Modelo alucinando IDs**: validar siempre los uuids que el modelo
  pasa en tools — si no existen, error legible al usuario, no insert
  silencioso.

---

## Lo que NO entra en Capa 2

- **RAG sobre apuntes** → Capa 3 con pgvector + embeddings (Voyage o
  el provider que decidamos).
- **Sincronización con Google** → Capa 4 vía MCP.
- **Casa inteligente** → Capa 5.
- **Proactividad** (Matix avisa por iniciativa) → Capa 8. En Capa 2
  Matix reacciona, en Capa 8 propone.

---

## Tests: aislamiento (estado al 2026-05-27)

Tres mecanismos de aislamiento, en orden de prioridad:

1. **`cerebro/.env.test` opcional**: si existe, los tests usan una
   Supabase aparte (sin tocar la del usuario). Se carga **antes**
   de importar `app.config` para que Pydantic-Settings tome los
   valores correctos. Plantilla en `cerebro/.env.test.example` con
   los pasos manuales (crear proyecto-test, generar key, aplicar
   migraciones). El header de pytest avisa contra qué Supabase
   está corriendo en cada run.
2. **Limpieza por test**: toda fixture o test que crea filas limpia
   con `/permanente` en su `finally` — así no llena la papelera.
3. **Red de seguridad session-level**:
   `tests/conftest.py::_barrer_residuos_test` borra cualquier fila
   cuyo título/nombre empiece con `_test_` / `test_` al cerrar el
   suite. Se ejecuta vía la Management API de Supabase con
   `SUPABASE_PROJECT_REF` + `SUPABASE_ACCESS_TOKEN`; si esos no
   están, el barrido es no-op (no rompe el suite).

**Acción pendiente del usuario** para activar (1): seguir los
pasos en `cerebro/.env.test.example` — crear proyecto-test en
Supabase, aplicar las 4 migraciones, rellenar el archivo. Sin
eso, los tests siguen corriendo contra la Supabase real con (2) y
(3) como redes.
