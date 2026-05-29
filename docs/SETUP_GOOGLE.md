# Setup · Google OAuth (Capa 4 Paso 1)

Guía paso a paso para habilitar la integración con Google Calendar.
Esta es la **Fase B** del Paso 1 — el código en la app y el cerebro
ya está listo; lo que falta es darle a Matix las credenciales OAuth
de Google.

Tiempo estimado: 20 minutos.

---

## 1. Proyecto en Google Cloud Console

### 1.1 Crear (o reusar) el proyecto

1. Abrí https://console.cloud.google.com/.
2. Arriba a la izquierda, selector de proyectos → **"+ Nuevo proyecto"**.
3. Nombre: `Matix` (o reusá uno existente).
4. Esperá ~30 s a que se cree y seleccionalo.

### 1.2 Activar la Google Calendar API

1. Menú izquierdo → **APIs y servicios** → **Biblioteca**.
2. Buscá **"Google Calendar API"**.
3. Tocá la card → **Habilitar**.

(Hace falta porque Google bloquea las llamadas a APIs no habilitadas
en el proyecto, aunque tengas un token válido.)

---

## 2. Pantalla de consentimiento OAuth

Esto es lo que el usuario ve cuando autoriza. Hay que configurarlo
**una vez** antes de poder generar credenciales.

1. Menú izquierdo → **APIs y servicios** → **Pantalla de
   consentimiento de OAuth**.
2. **User Type**: **Externo** (cualquier cuenta Google puede
   autorizar, no solo las de tu organización). Continuar.
3. **Información de la app**:
   - **App name**: `Matix`
   - **User support email**: tu mail.
   - **Developer contact information**: tu mail.
   - Logo opcional.
4. **Guardar y continuar**.
5. **Scopes**: tocá "Add or Remove Scopes" y agregá:
   - `.../auth/userinfo.email` (para que sepamos qué cuenta se conectó)
   - `openid`
   - `https://www.googleapis.com/auth/calendar.readonly`
6. **Guardar y continuar**.
7. **Test users**: agregá tu propio email (`shadowgames.devteam@gmail.com`)
   y cualquier otra cuenta Google donde quieras usar Matix.
   - Mientras la app esté en modo **"Testing"** (default), solo los
     test users pueden autorizar.
   - Para "Publishing" + verificación de Google se necesitaría un
     proceso largo; para uso personal **dejalo en Testing**, no hace
     falta más.
8. **Guardar y continuar** → **Volver al panel**.

---

## 3. Credenciales OAuth (Client ID)

1. Menú → **APIs y servicios** → **Credenciales**.
2. **+ Crear credenciales** → **ID de cliente de OAuth**.
3. **Tipo de aplicación**: **Aplicación web**.
4. **Nombre**: `Matix Cerebro`.
5. **URI de redireccionamiento autorizados**: agregá:
   ```
   https://matix-production.up.railway.app/api/v1/google/oauth/callback
   ```
   (Es la URL que el cerebro expone para recibir la respuesta de
   Google tras la autorización.)

   Si tu URL pública de Railway es distinta, ajustala.
6. **Crear**.

Google te muestra un diálogo con:
- **Client ID** (`...apps.googleusercontent.com`)
- **Client secret** (algo tipo `GOCSPX-...`)

**Copialos**. Los necesitamos en el paso siguiente.

---

## 4. Configurar el cerebro

El cerebro necesita 3 variables nuevas. Dos formas:

### 4.1 En Railway (producción)

1. Railway → tu proyecto → **Variables**.
2. Agregá:
   ```
   GOOGLE_CLIENT_ID=<el que copiaste>
   GOOGLE_CLIENT_SECRET=<el que copiaste>
   GOOGLE_REDIRECT_URI=https://matix-production.up.railway.app/api/v1/google/oauth/callback
   ```
3. Railway redeploya automáticamente. En ~30 s el cerebro arranca
   con OAuth habilitado.

### 4.2 En local (para desarrollo)

En `cerebro/.env` agregá las mismas 3 variables. La `redirect_uri`
en local apunta al cerebro local:
```
GOOGLE_REDIRECT_URI=http://localhost:8000/api/v1/google/oauth/callback
```

Pero entonces tenés que también agregar esa URI a las "URIs de
redireccionamiento autorizados" en Google Cloud (paso 3.5).

---

## 5. Probar desde la app

1. Abrí Matix en el teléfono (build con el código de Capa 4 Paso 1).
2. **Ajustes → Conexiones → Google Calendar**.
3. Tocá **"Conectar Google"**. Se abre Chrome.
4. Elegí tu cuenta de Google (tiene que estar en los "Test users"
   del paso 2.7).
5. Pantalla de consentimiento → confirmá los permisos:
   - Ver tu email.
   - Ver eventos de Google Calendar.
6. Google redirige al cerebro, que muestra **"✓ Listo · Cuenta
   conectada: tu@email.com. X eventos sincronizados…"**.
7. Volvé a Matix.
8. En la card de Google Calendar, tocá **"Ya autoricé"**.
9. La card cambia a **"Conectado · tu@email.com"** + último sync.
10. Abrí la pestaña **Calendario**. Tus eventos reales de Google
    aparecen junto a los manuales.

---

## 6. Troubleshooting

### "OAuth Google no habilitado en el cerebro"

Las 3 variables no están seteadas en Railway. Volvé al paso 4.1.

### "Error 400: redirect_uri_mismatch"

La URL de callback que Google envía no coincide con ninguna de las
autorizadas en Cloud Console. Verificá que la URI en el paso 3.5
sea **exactamente** la misma que en `GOOGLE_REDIRECT_URI` del
cerebro — sin barra final, mismo dominio, mismo schema (https).

### "Error 403: access_denied"

Tu cuenta no está en la lista de Test Users. Volvé al paso 2.7,
agregala, esperá un minuto y reintentá.

### Después de autorizar, en "Ya autoricé" sigo viendo "no conectado"

Mirá los logs de Railway → buscá errores en `/google/oauth/callback`.
Causas comunes: `refresh_token` no llegó (Google no manda refresh
si no le pedís `prompt=consent`; el cerebro ya lo hace, pero si
viniste reusando un grant viejo, revocá manualmente en
https://myaccount.google.com/permissions y volvé a autorizar
desde cero).

### Tus eventos no aparecen en el Calendario del hub

1. Confirmá que la sincronización corrió: en Ajustes → Google,
   el "Último sync" debe ser reciente.
2. Tocá **"Sincronizar"** para forzar.
3. Si dice "+0 nuevos", revisá que tu Calendar tenga eventos en
   el rango sincronizado (desde ayer hasta dentro de 90 días).
4. Si dice 401, tu token se invalidó (lo revocaste, expiró sin
   refresh, etc.): tocá **"Desconectar"** y volvé a conectar.

---

## 7. Día a día

- Cada vez que abras el Calendario, podés tocar **"Sincronizar"**
  en Ajustes si querés traer cambios recientes.
- En el futuro (Capa 4 Paso 2) los eventos manuales que crees
  desde Matix se propagarán a Google. Por ahora solo lectura.
- Si querés desconectar y limpiar, **"Desconectar"** borra los
  tokens del cerebro. Los eventos sincronizados se quedan en el
  hub (porque están en Supabase). Si también querés borrarlos,
  Papelera no aplica — habría que purgar manualmente desde la BD
  por ahora.
- Para revocar el grant del lado de Google:
  https://myaccount.google.com/permissions → buscás "Matix" → quitar acceso.

---

## 8. Habilitar escritura (Capa 4 Paso 2)

El Paso 1 te conectó con scope **`calendar.readonly`** — Matix solo
lee tus eventos. El Paso 2 sumó **push** (lo que creás en Matix
sube a tu Google Calendar). Para eso hace falta el scope
**`calendar`** (full).

Si Matix detecta que tu conexión actual es la del Paso 1, en
Ajustes → Conexiones → Google Calendar te aparece un banner ámbar:
**"Sincronización bidireccional · Reconectar para conceder
escritura"**. El proceso lleva 1 minuto y es lo mismo que la primera
vez, solo que ahora vas a ver más checkboxes en la pantalla de
consentimiento.

### 8.1 Sumar el scope en Cloud Console

(Si ya está, salteá al 8.2.)

1. Cloud Console → **APIs y servicios** → **Pantalla de
   consentimiento de OAuth** → tab **Data Access** → botón
   **"Add or Remove Scopes"**.
2. En "Manually add scopes" (abajo), pegá:
   ```
   https://www.googleapis.com/auth/calendar
   ```
3. Tocá **"Add to Table"** → **"Update"** → **"Save"**.

Ahora la pantalla de consentimiento incluye permiso de lectura +
escritura en Calendar.

### 8.2 Reconectar desde la app

1. Ajustes → Conexiones → Google Calendar → tocá **"Reconectar
   para bidireccional"** (botón ámbar del banner).
2. Se abre Chrome con la misma pantalla de la primera vez, pero
   ahora vas a ver dos permisos:
   - "Ver tu email" (igual).
   - **"Ver, editar y borrar eventos de tus calendarios"** (nuevo).
3. Aceptás. Google redirige al cerebro como siempre, muestra
   "Listo".
4. Volvés a Matix. El banner ámbar desaparece y todo evento manual
   nuevo va a empujarse al Google Calendar.

### 8.3 ¿Qué pasa con los eventos manuales que creaste antes?

Al primer sync después de reconectar (botón "Sincronizar" en Ajustes
o auto-disparado al abrir el calendario), el cerebro hace un
**backfill**: busca todos los eventos manuales del hub sin
`external_id` y los empuja a Google. En el resumen del sync vas a
ver "+N subidos a Google". A partir de ahí están unidos.

Si alguno falla el push (Google rebota, lo que sea), queda local y
se reintenta al siguiente sync.

### 8.4 Editar eventos importados de Google

Después del Paso 2 podés editar/borrar los eventos `origen='google'`
directamente desde Matix. El cerebro intenta el cambio en Google
primero — si Google acepta, también se aplica en el hub; si Google
rebota (típicamente por no ser organizador, ej. una clase a la que
estás invitado), Matix te muestra "Google rechazó la edición" y el
evento queda como estaba.
