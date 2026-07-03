# Operación de Matix

Guía operativa del cerebro: monitoreo de costo, errores, backups y la higiene
de siempre. Todo es instrumentación aditiva — no cambia el comportamiento de
las features.

## Monitoreo de costo de API

- Cada llamada externa (OpenAI chat/visión/embeddings/TTS/Whisper y Tavily) se
  cuenta en el medidor (`app/matix/uso.py`) con su costo estimado en USD.
- Un tick del scheduler (`app/matix/costos.py`, cada minuto) toma snapshot del
  medidor y SUMA el delta al gasto del DÍA en la tabla `costos_api` (el mes = la
  suma de los días). Sobrevive a reinicios: el medidor en memoria se pierde,
  pero lo ya persistido queda.
- Por chat: pregúntale a Matix «¿cuánto gasté hoy?», «¿cuánto va este mes?»
  (tool `consultar_gasto`). El consumo de la SESIÓN actual sigue en
  `consultar_uso`.
- Alertas: si el gasto del día o del mes cruza el umbral, manda un push (FCM),
  una sola vez por día/mes y respetando el silencio (22:00–08:00, hora de Lima).
- Umbrales editables en la tabla `config_costos`
  (`umbral_diario_usd`, `umbral_mensual_usd`, `activo`). Defaults: 1 USD/día,
  15 USD/mes. Para cambiarlos, edita esa fila (un solo registro) en Supabase.
- Los precios viven como constantes en `uso.py`; si OpenAI/Tavily los mueven,
  se ajustan ahí. El gasto mostrado es un ESTIMADO (sobre todo Tavily).

## Monitoreo de errores

- Cada job del scheduler corre AISLADO con `recordatorios.correr_job`: un fallo
  se loguea con contexto (nombre del job + tipo de error, sin datos sensibles) y
  NO tumba a los demás jobs del tick.
- Jobs críticos (hoy: el backup) avisan por push si fallan, una vez por día y
  respetando el silencio (`_avisar_error_critico`).
- Los logs nunca incluyen claves, tokens ni contenido personal — solo el tipo de
  error y el nombre del job.

## Backup de la base de datos

- Job diario (`app/matix/backup.py`, ~04:00 Lima) que exporta las tablas CLAVE
  (datos del usuario: proyectos, árbol, tareas, eventos, apuntes, cursos,
  movimientos, memoria, etc.) a un JSON y lo sube al bucket privado `backups` de
  Supabase Storage. Conserva los últimos 14 y rota los viejos.
- No incluye tablas de embeddings (pesadas y reconstruibles).
- El bucket se crea solo la primera vez. Si quieres descargarlos: Supabase →
  Storage → bucket `backups`.

### Red de seguridad real: backup nativo de Supabase

El job de arriba es una conveniencia; el backup serio actívalo en Supabase:

1. Entra a https://supabase.com → tu proyecto `matix`.
2. Project Settings → Database → Backups.
3. En el plan Pro: activa los Daily backups (retención 7 días) y, si está
   disponible, Point-in-Time Recovery (PITR). En el plan Free no hay backups
   automáticos gestionados — por eso el job propio cubre el hueco mínimo.
4. Anota dónde quedan y prueba una restauración al menos una vez.

## Checklist de operación

Higiene de credenciales
- Todas las claves (OpenAI, Anthropic, Tavily, Supabase service_role/access
  token, Firebase) van SIEMPRE en variables de entorno del cerebro, NUNCA en el
  repo, ni en logs, ni en resúmenes. El repo es privado igual.
- `tools/.env.prod.local` (gitignored) guarda el access token de Supabase para
  migraciones; el `service_role` se obtiene en runtime, nunca se imprime.
- Si una clave se expone, rótala y actualiza el entorno (Railway / `.env`).

Teléfono (acceso del dispositivo)
- Revisa la allowlist/denylist de apps del acceso al teléfono: solo lo mínimo
  necesario. WhatsApp es la única acción de escritura; el resto es lectura o
  intents pre-llenados que el usuario confirma.
- Las acciones sensibles piden confirmación antes de ejecutarse.

Validación / release
- Valida SIEMPRE con el APK release que construye el CI (no solo en debug):
  algunos fallos (permiso INTERNET, cleartext) solo aparecen en release.
- Tras un cambio de cerebro (sin app), no hace falta APK nuevo; el cambio toma
  efecto en el próximo deploy de Railway.
- Migraciones: las aplica el asistente con `tools/aplicar-migracion.sh`
  (Management API). Las normales sin preguntar; las destructivas, solo con
  confirmación explícita.

## Keep-alive de Supabase (anti-pausa del free tier)

El plan free de Supabase PAUSA el proyecto tras ~7 días sin ninguna request. El
GitHub Action `.github/workflows/keepalive.yml` corre cada ~3 días y hace una
query mínima a la BD (`tools/keepalive.sh` → `GET /rest/v1/app_versions?limit=1`)
para mantenerlo activo. Reusa los secrets `SUPABASE_URL` +
`SUPABASE_SERVICE_ROLE_KEY` del release (no requiere secrets nuevos). Se puede
disparar a mano desde Actions → «Keep-alive Supabase» → Run workflow.

Nota: este keep-alive cubre la PAUSA POR INACTIVIDAD, no la restricción por
cuota de storage (esa se resuelve borrando objetos; ver el incidente del bucket
`apks`). Si se quisiera un keep-alive que además funcione con el proyecto
restringido por cuota, habría que añadir el secret `SUPABASE_ACCESS_TOKEN` (hoy
NO está en GitHub Secrets) y pegar por la Management API — queda ANOTADO, no se
crea aquí.
