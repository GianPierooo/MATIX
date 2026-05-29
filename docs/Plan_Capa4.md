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
- **Paso 2**: reemplaza el anterior por `https://www.googleapis.com/auth/calendar` (full — lectura + escritura + gestión de calendarios).
- **Paso 3**: + `https://www.googleapis.com/auth/tasks` (full por la misma razón que Paso 2).
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

### Paso 2 — Escribir al Calendar (bidireccional)

Cierra el círculo: lo que pasa en el hub se refleja en el Google
Calendar del usuario, y lo que pasa en Google se sigue trayendo
al hub. Sin loops ni duplicados.

#### Qué se sincroniza

- **Solo eventos**. Tareas se quedan para Paso 3 (con scope `tasks`).
- **Solo el calendario primario** del usuario (sin selector multi-calendario).
- Crear, editar y borrar — los tres se propagan en ambas direcciones.

#### Quién puede editar qué

Decisión: **máxima libertad**. El hub trata todos los eventos como
editables — los `origen='manual'` (creados en Matix) y los
`origen='google'` (importados). La diferencia es solo el orden
de las operaciones:

| origen | flujo de edición/borrado |
|---|---|
| `manual` | Hub primero, push a Google después (best-effort). Si Google falla, el cambio queda local y el próximo sync lo reintenta. |
| `google` | Push a Google primero. Si Google rebota (403 porque no sos organizador, 410 si el evento ya fue borrado, etc.), el hub NO aplica el cambio y propaga el error al cliente. Evita desync. |

Para crear, no aplica esa distinción — todo evento nuevo nace
`origen='manual'`, lo guarda el hub y dispara el push.

#### Loop prevention y dedup

El loop natural sería: hub crea → push → Google → pull → hub crea
otro duplicado. Lo cortamos con dos llaves:

1. **`external_id` en eventos manuales**. Después del primer push,
   guardamos el `id` que devolvió Google en la misma fila del hub,
   manteniendo `origen='manual'`. El próximo pull encuentra la fila
   por `(external_account, external_id)` y la trata como existente.
   No duplica. No degrada el origen.
2. **UNIQUE `(external_account, external_id)`** (sin filtrar por
   origen, distinto al Paso 1) — la BD garantiza la unicidad
   transversal a los orígenes.

Importante: el `_actualizar` del sync **no toca la columna `origen`**.
Si el evento empezó como manual y fue pusheado, sigue siendo
manual aunque el pull lo vuelva a tocar.

#### Conflictos: última escritura gana

Sumamos `eventos.google_updated_at` (timestamptz) — guarda el
`updated` que Google reporta cada vez que ve el evento (sea por pull
o por respuesta a push). Es nuestro reloj canónico del lado Google.

Reglas:

- **Pull (Google → hub)**: aplico el evento al hub solo si
  `google_updated > hub.actualizado_en + 2s`. Si el hub es más
  reciente (porque el usuario acaba de editar local), skipeo.
- **Push (hub → Google)**: tras el ack, guardo el nuevo
  `google_updated_at` que devuelve Google. El próximo pull verá
  que `google_updated == google_updated_at` (mismo estado) y no
  hace nada.
- **Epsilon de 2s** para tolerar drift entre relojes y el lag
  Supabase ↔ Google.

Trade-off documentado: si editás en Google web Y en el hub entre
dos syncs, la edición más vieja se pierde silenciosa. Con polling
razonable (al abrir el calendario / al tocar Sync) es rarísimo.
Si en el futuro necesitamos resolución de conflictos con UI, suma
una columna `pendiente_revision` y un endpoint dedicado — fuera
del alcance del Paso 2.

#### Backfill al conectar Google

Los eventos manuales creados ANTES de conectar Google (o mientras
Google estaba caído) no tienen `external_id`. Antes de cada pull,
el `sincronizar` corre un sweep:

```
para cada evento WHERE origen='manual' AND external_id IS NULL
                AND eliminado_en IS NULL:
    pushear a Google → guardar external_id + google_updated_at
```

Esto cubre dos casos:
1. El usuario conectó Google después de haber creado N eventos.
2. Un push inline falló (Google estaba caído / rate-limit) y nadie
   reintentó.

Si el sweep tropieza con un evento que Google rechaza, lo loggeamos
y seguimos con el resto. El evento queda local hasta que el usuario
lo arregle (o el caso se autorresuelva).

#### Scope OAuth

Paso 1 era `calendar.readonly`. Paso 2 lo reemplaza por **`calendar`
(full)** — incluye lectura, creación, edición y borrado de eventos
y gestión de calendarios. El usuario reautoriza una vez para
conceder el scope nuevo.

Detección desde la app: si `oauth_google.scopes` no incluye
`calendar` (o `calendar.events`), la pantalla de Ajustes → Google
muestra un banner ámbar con CTA "Reconectar para sincronización
bidireccional". El CTA invoca el mismo flujo OAuth que ya existe.

Cloud Console: hay que sumar el scope a la pantalla de
consentimiento (Data Access → Add scopes). Documentado en
`SETUP_GOOGLE.md`.

#### Restaurar y borrado permanente

- DELETE en el hub sobre un evento con `external_id`:
  - `origen='manual'`: soft-delete local + `events().delete()` en
    Google (best-effort; si Google da 404 ya estaba borrado allá,
    seguimos).
  - `origen='google'`: tiene que aceptar Google primero (mismo
    patrón que la edición). Si rebota, no soft-delete.
- **Restaurar** desde papelera de hub: INSERT nuevo en Google →
  nuevo `external_id`. El ID original se pierde — aceptable porque
  restauraciones son raras.
- DELETE permanente (`/permanente`): solo BD, no toca Google.
  El evento ya no existía en Google (porque el soft-delete lo
  borró). Si por alguna razón sigue en Google, el próximo pull
  lo re-importará — el usuario lo borra de nuevo.

#### Lo que NO entra en Paso 2

- **Adopción** de un `origen='google'` para "hacerlo mío" (cambiar
  el origen). Trabajamos con todos editables sin convertir.
- **Selector de calendarios** (siempre `primary`).
- **Multi-cuenta** Google.
- **Webhooks `watch`** de Google para push instantáneo. Polling +
  sweep alcanza.
- **Recurrencias creadas desde el hub** — Matix sigue creando solo
  eventos puntuales; las recurrencias vienen de Google y se
  expanden a singleEvents al pull.
- **UI de resolución de conflictos**. Last-write-wins en silencio.

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
