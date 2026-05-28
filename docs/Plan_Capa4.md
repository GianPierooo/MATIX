# Plan — Capa 4: Sincronización con Google

Conectar el hub a la vida real del usuario: el Google Calendar
que ya usa, las tareas que tiene en Google Tasks, y los avisos de
clases/entregas que le llegan por Gmail. Sin moverse de Matix.

Llega después de Capa 3 (RAG + tutor) y antes de Capa 5 (casa
inteligente). Reusa todo lo que ya hay: cerebro FastAPI, Supabase,
tools de Matix, auto-actualización.

---

## Decisiones de arquitectura (transversales a todos los pasos)

### Sync a Supabase como única fuente de verdad

Hay dos formas posibles de exponer datos de Google al hub:

- **Sync**: los traemos a Supabase, los marcamos con `origen='google'`,
  y la app/Matix los ven como cualquier otro evento/tarea.
- **On-demand**: cada lectura pega a Google.

Elijo **sync**. Razones:

1. **Funcionamiento offline.** El usuario tiene sus eventos del día
   visibles aunque esté sin red. Crítico para datos móviles flakeantes.
2. **Una sola query** desde la app, sin importar la fuente.
3. **El contexto vivo de Matix** lee `eventos` directo de Supabase —
   ya tiene los eventos de Google sin lógica extra.
4. **RAG futuro sobre apuntes que mencionen eventos** funciona sin
   pensarlo: todo vive en la misma BD.

Trade-off: hay que sincronizar. Lo manejamos con:
- Sync inicial cuando el usuario conecta la cuenta.
- Sync periódico ligero desde el cliente (cada vez que abre el
  Calendario, llamada al endpoint `/google/sync`).
- Botón "Sincronizar ahora" en Ajustes para forzar.
- Más adelante (Capa 8 o cron de Railway): sync nocturno automático.

### Origen y external_id

Las tablas que reciban data de Google (`eventos`, en el Paso 1;
`tareas` en pasos siguientes) suman dos columnas:

- `origen text default 'manual' check (origen in ('manual','google'))`
- `external_id text` — id estable del item en Google. NULL para manuales.
- UNIQUE constraint `(origen, external_id)` cuando external_id no es null.

La app distingue visualmente con un badge "Google" sutil — el
usuario NO edita esos items desde Matix por ahora (Paso 1 es solo
lectura). En Paso 2 sumamos edición → propaga a Google.

Cuando Google reporta que un evento ya no existe (lo borraste
desde Google), el sync lo manda a la papelera (soft-delete) de Matix.
NO destruye permanente, así si fue un error en Google quedan
recuperables del lado de Matix por unos días.

### Tokens OAuth — almacenamiento

Una tabla `oauth_google` en Supabase con un renglón por cuenta de
Google conectada:

```
email text primary key
access_token text
refresh_token text
token_expiry timestamptz
scopes text[]
conectado_en timestamptz
ultimo_sync_en timestamptz
```

RLS activo, **solo el service_role** (cerebro) puede leer/escribir.
Sin RLS para anon/authenticated. Si el repo se compromete, la BD
no se compromete (los tokens viven en Supabase, no en el código).

**No encriptamos los tokens** en el campo `text`. Razones:
- Es un proyecto single-user, privado.
- Supabase ya nos da row-level encryption del lado de su infra.
- Encryption de aplicación añadiría una clave más que rotar y
  custodiar — más superficie que cubrir, sin reducir el riesgo
  real (un atacante con `service_role` ya leyó todo lo demás).

Si la app crece a multi-user en algún momento, encriptamos con la
PG extension `pgcrypto` que ya usamos para `gen_random_uuid`.

### Scopes mínimos por paso

Cada paso suma el scope necesario, ni uno más. La pantalla de
consentimiento de Google muestra los scopes que el usuario aprueba.

- **Paso 1**: `https://www.googleapis.com/auth/calendar.readonly`
- **Paso 2**: + `https://www.googleapis.com/auth/calendar.events`
- **Paso 3**: + `https://www.googleapis.com/auth/tasks.readonly`
- **Paso 4**: + `https://www.googleapis.com/auth/gmail.readonly`

Cada salto requiere reautorización del usuario.

### Flujo OAuth (el del usuario tocando "Conectar Google")

1. App → cerebro: `GET /api/v1/google/oauth/url` → cerebro arma la URL
   de consentimiento y la devuelve.
2. App abre esa URL en el navegador del teléfono.
3. Usuario autoriza en Google.
4. Google redirige a `https://matix-production.up.railway.app/api/v1/google/oauth/callback?code=…`
5. Cerebro intercambia el `code` por `access_token + refresh_token` y los guarda en Supabase.
6. Cerebro responde con una página simple "Listo, ya podés volver a Matix".
7. App, al volver del navegador, hace polling de `/api/v1/google/status` y muestra "Conectado · <email>".

(No usamos deep links a la app por ahora — agrega complicación de
intent filters sin valor crítico. Polling + página de éxito alcanza.)

---

## Pasos

### Paso 1 — OAuth + leer Calendar (Capa 4 base)

Establece toda la maquinaria OAuth y trae el primer dato real.

- Migración 0007: tabla `oauth_google`, columnas `origen` y
  `external_id` en `eventos`.
- Cerebro:
  - `cerebro/app/google/oauth.py` con la lógica de intercambio y
    refresh de tokens.
  - `cerebro/app/google/calendar.py` que llama a Google Calendar
    API y sincroniza a Supabase.
  - Router `/api/v1/google/` con endpoints OAuth + status + sync +
    disconnect.
- App:
  - Pantalla Ajustes → sección "Conexiones" → tile "Google Calendar"
    con estado (conectado/no, email, último sync) y acciones
    (conectar / sincronizar / desconectar).
  - En el Calendario, los eventos de Google muestran un badge sutil.
- Doc: `docs/SETUP_GOOGLE.md` con la guía para crear el proyecto
  Google Cloud, pantalla de consentimiento OAuth, descargar las
  credenciales y configurar los secrets.

### Paso 2 — Escribir al Calendar

Una vez que la lectura funciona y los eventos de Google se ven en
el hub, sumamos:

- Scope nuevo: `calendar.events` (lectura + escritura).
- Cuando Matix llame a `crear_evento` / `editar_evento` /
  `eliminar_evento` y el usuario lo pida explícitamente para
  Google (o si el evento ya tiene `origen='google'`), propagamos
  al Calendar API además de a Supabase.
- Sin sobrescribir invitaciones de eventos del trabajo / clase
  donde Gian Piero NO es organizador — solo edita los suyos.

### Paso 3 — Google Tasks

Las tareas que tiene en Google Tasks entran al hub como tareas con
`origen='google'`. Mismo patrón que eventos: sync, badge, edición
en Paso 4.

### Paso 4 — Gmail read-only

Lectura mínima del Gmail para que Matix detecte automáticamente
mails que mencionan entregas o clases. NO indexa todo: solo
busca patrones específicos ("entrega", "examen", "evaluación",
nombres de cursos) y ofrece crear tareas/eventos. El usuario
confirma antes de que algo entre al hub.

---

## Lo que NO entra en Capa 4

- **Multi-cuenta** (un Matix conectado a varios Google a la vez).
  Single-user por ahora.
- **Apple Calendar / Microsoft / Notion**. Si en el futuro hace
  falta, el patrón es el mismo: agregar origen `apple`, `notion`,
  etc.
- **Webhooks/push de cambios** en tiempo real (Google los soporta
  con `watch`). Polling cada N horas + sync manual alcanza para
  Capa 4. Para Capa 8 (proactividad) se evalúa.
