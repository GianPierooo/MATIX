# `core/` — servicios compartidos

Código que no pertenece a un feature concreto. Vive aquí lo que
varias secciones del hub van a consumir.

## Archivos

### `providers.dart`
- `matixClientProvider`: `Provider<MatixClient>` global, no
  autoDispose. La conexión vive toda la sesión; al cerrarse, libera
  el `http.Client` interno.

### `notificaciones_service.dart`
- `NotificacionesService` envuelve `flutter_local_notifications` con
  4 operaciones: `programar(id, titulo, cuerpo, cuando)`,
  `cancelar(id)`, `cancelarTodo()`, `pendientes()`. Inicialización
  lazy (`inicializar()` se llama en el primer uso) — carga timezones
  + plugin Android.
- `notificacionesServiceProvider`: `Provider` singleton.
- Decisión: `AndroidScheduleMode.inexactAllowWhileIdle` para evitar
  el permiso extra de alarmas exactas (Android 12+). Si la
  imprecisión molesta, se cambia a `exactAllowWhileIdle` y se
  gestiona `SCHEDULE_EXACT_ALARM`.
- Zona horaria fija `America/Lima`. En Capa 4+ podría leerse del
  perfil del usuario.

### `notif_id.dart`
- `notifIdDe(String uuid) → int` deriva un id de notificación
  estable a partir de un uuid v4. Primeros 7 caracteres hex = 28
  bits (cabe en `Integer.MAX_VALUE`). Colisión ≈ 1/268M.

## Convenciones

- Nada de Flutter en lo "puro": `MatixClient` y `notif_id.dart` no
  importan `package:flutter/material.dart`.
- `NotificacionesService` sí importa Flutter (necesita el plugin),
  pero NO `BuildContext` — la UI no aparece aquí.
- Todos los providers son `Provider`/`FutureProvider` clásicos, no
  `@riverpod`. Razón: evitar `build_runner` antes de cada compilación.
