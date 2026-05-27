# `features/tareas/` — plantilla de feature

Esta carpeta es la **plantilla** que el resto de pasos de la Capa 1
(Calendario, Universidad, Apuntes, Inicio, Proyectos) copia. Si vas a
construir una sección nueva, lee esto antes de empezar.

## Estructura

```
features/tareas/
├── README.md               (este archivo)
├── data/
│   ├── tareas_repository.dart        ← wrapper de MatixClient
│   └── selectores_repository.dart    ← carga categorias / cursos / proyectos
├── domain/
│   ├── tarea.dart           ← entity Tarea + Subtarea + enums (Prioridad, Repeticion)
│   └── selectores.dart      ← entities ligeras para dropdowns (CategoriaRef, CursoRef, ProyectoRef)
├── providers/
│   └── tareas_providers.dart        ← providers Riverpod: repos, FutureProviders, Notifiers, derived
└── presentation/
    ├── tareas_list_screen.dart      ← pantalla principal
    ├── nueva_tarea_screen.dart      ← crear / editar
    └── widgets/
        ├── tarea_tile.dart
        └── filtros_sheet.dart
```

## Reglas del patrón

### 1. `data/` no conoce Flutter, solo HTTP (y servicios)

Los repositorios envuelven al `MatixClient` y devuelven entities del
`domain/`. Nada de `BuildContext` ni `Widget`. Si la entidad tiene
`recordar_en`, el repo también recibe el `NotificacionesService`
para mantener sincronizadas las notificaciones locales:

```dart
class TareasRepository {
  TareasRepository(this._client, this._notif);
  final MatixClient _client;
  final NotificacionesService _notif;
}
```

**Patrón de notificaciones recordatorias** (ver
`tareas_repository.dart`):

- `crear()`, `actualizar()` y `marcarCompletada()` llaman al final a
  un helper privado `_reprogramarRecordatorio(entity)`.
- `borrar()` llama a `_notif.cancelar(notifIdDe(id))`.
- `_reprogramarRecordatorio` es idempotente: cancela siempre +
  programa solo si `recordar_en` es futuro y la entity no está
  completada/cerrada. No depende del valor previo, así no hace falta
  un GET extra antes de cada PATCH.

Eventos y Evaluaciones replican este patrón cuando se construyan
(usan el mismo `NotificacionesService` con `notifIdDe(id)`).

### 2. `domain/` es inmutable, con `fromJson`

Entities anotadas con `@immutable`, todos los campos `final`,
`fromJson` que parsea desde el formato de la API del cerebro
(snake_case → camelCase). Nada de `toJson` salvo que se necesite
serializar para PATCH; en general el repositorio construye el body
directamente.

```dart
@immutable
class Tarea {
  const Tarea({required this.id, ...});
  factory Tarea.fromJson(Map<String, dynamic> json) => ...;
}
```

Computed getters útiles van como métodos (`estaVencida`, `venceHoy`).

### 3. `providers/` usa Riverpod **clásico** (sin codegen)

Una sola hoja por feature; cuando crezca demasiado, se parte por
sub-dominio. Patrones recurrentes:

- **Repositorio** como `Provider` global.
- **Lista cruda desde red** como `FutureProvider`.
- **Lista por argumento** como `FutureProvider.family`.
- **Estado local de UI** (filtros, vista activa) como
  `NotifierProvider`.
- **Derivado** (lista + filtros) como `Provider` que devuelve
  `AsyncValue<List<T>>` haciendo `whenData` sobre el FutureProvider
  base.

Ver `tareas_providers.dart` como referencia.

### 4. `presentation/` consume providers, nunca el repo directo

`ConsumerWidget` o `ConsumerStatefulWidget`. Para mutaciones:
`ref.read(repo)` + `await repo.crear(...)` + `ref.invalidate(provider)`
para refrescar.

```dart
onPressed: () async {
  await ref.read(tareasRepositoryProvider).borrar(id);
  ref.invalidate(tareasProvider);
}
```

### 5. Errores con `MatixApiException`

El `MatixClient` decodifica `{"detail": "..."}` de FastAPI antes de
lanzar la excepción. En la UI muestra `e.message` directo — ya es
legible. No re-parsees JSON.

### 6. Estados estándar: cargando / error / vacío / con datos

Usa `AsyncValue.when(loading:, error:, data:)`. Vista vacía con
mensaje propio según el contexto, no genérico. Ver `_Vacio` en
`tareas_list_screen.dart`.

### 7. Vencidas se resaltan, no se esconden

Si una entity tiene fecha pasada y no está completada/cerrada, su
card va con borde y fondo rojo suave. Patrón anti-olvido del
Documento Maestro.

### 8. Bottom sheet de filtros, no pantalla aparte

Los filtros viven en un `showModalBottomSheet` con `isScrollControlled:
true` y fondo `MatixColors.cardHi`. Estado en un `NotifierProvider`
separado del estado de la lista, para que se preserve al cerrar el
sheet.

## Cómo replicar en una sección nueva

1. `mkdir app/lib/features/<nombre>/{data,domain,presentation/widgets,providers}`.
2. Crear `domain/<entity>.dart` con la entity y sus enums.
3. Crear `data/<nombre>_repository.dart` envolviendo `MatixClient`.
4. Crear `providers/<nombre>_providers.dart` con el repositorio, el
   FutureProvider de la lista, los notifiers de vista/filtros y el
   provider derivado.
5. Crear `presentation/<nombre>_list_screen.dart` con AppBar + pills
   + lista + FAB + bottom sheet.
6. Crear `presentation/nuevo_<entity>_screen.dart` con form +
   validación + manejo de error legible.
7. Reemplazar el stub en `app/lib/screens/<nombre>_screen.dart` por
   un re-export del `<nombre>_list_screen.dart` o, mejor, borrar el
   stub y enchufar la nueva pantalla directamente en
   `home_shell.dart`.

## Lo que NO copies

- **No** uses `StatefulWidget + FutureBuilder` cada vez. Pasa por
  Riverpod desde el inicio.
- **No** parsees `e.toString()` para mostrar errores. Usa
  `e.message`.
- **No** dupliques iconos del bottom nav. Si necesitas el icono de
  Matix o Proyectos en otro sitio, importa desde `matix_colors` /
  decide un esquema común.
