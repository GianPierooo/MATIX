# Plan de la Capa 1 — Armazón del hub

Este documento es el plan detallado de la Capa 1 de Matix. Lo que está
acá manda sobre lo que la conversación recuerda: si la sesión se
reinicia, se vuelve a leer este archivo y `ESTADO.md` para retomar.

La Capa 1 termina cuando Matix es un **organizador personal real y
útil por sí solo**: el usuario puede crear, ver y editar proyectos,
tareas, notas, cursos y eventos a mano, y el teléfono le avisa antes
de que algo venza. Nada de IA todavía — eso es Capa 2.

---

## Arquitectura de la Capa 1

```
Flutter (Android)  ──HTTP──>  FastAPI (PC local)  ──supabase-py──>  Supabase (Postgres)
     app/                          cerebro/                            proyecto remoto
```

- **App Flutter** habla **únicamente** con el cerebro. Nunca llama a
  Supabase directamente. Esto mantiene el `service_role` key fuera del
  móvil.
- **Cerebro FastAPI** corre en local (Capa 1) en `http://localhost:8000`.
  Usa el `service_role` key para leer y escribir en Supabase.
- **Supabase** tiene RLS activada en todas las tablas y **sin
  políticas** — solo el cerebro (service_role) puede acceder.
- Entre la app y el cerebro: header `X-Matix-Key` con un token
  compartido fijo por ahora. Capa 2 lo endurecerá.

---

## Modelo de datos · 11 tablas

| #  | Tabla              | Para qué                                                     |
|----|--------------------|--------------------------------------------------------------|
| 1  | `profile`          | Perfil del usuario (fila única): nombre, zona horaria, tema. |
| 2  | `categorias`       | Categorías libres para tareas (Personal, Trabajo, …).        |
| 3  | `cursos`           | Materias de la universidad: nombre, profesor, color.         |
| 4  | `sesiones_clase`   | Horario recurrente de cada curso (lunes 08:00–10:00…).       |
| 5  | `tareas`           | Pendientes con prioridad, fecha, categoría, curso o proyecto. |
| 6  | `subtareas`        | Pasos dentro de una tarea.                                   |
| 7  | `evaluaciones`     | Entregas, exámenes y proyectos académicos con su calificación. |
| 8  | `eventos`          | Eventos del calendario personal.                             |
| 9  | `cuadernos`        | Agrupadores de apuntes.                                      |
| 10 | `apuntes`          | Notas con `etiquetas TEXT[]` y `adjuntos JSONB`.             |
| 11 | `proyectos`        | Proyectos vitales del usuario: activos, aparcados y terminados. Acción siguiente y línea de meta. |

Las tablas 1–10 se crearon en `supabase/migrations/0001_initial_schema.sql`.
La tabla 11 y las FK `proyecto_id` en `tareas`, `apuntes` y `eventos` se
añaden en `0002_proyectos.sql`.

Decisiones que conviene tener presentes:

- **Recordatorios** viven inline como columna `recordar_en timestamptz`
  en `tareas`, `evaluaciones` y `eventos`. No hay tabla aparte; las
  notificaciones locales se programan desde la app a partir de ese
  campo.
- **Etiquetas de apuntes** son un `TEXT[]` con índice GIN — más
  simple que tabla aparte y suficiente para Capa 1.
- **Calificaciones** son columnas de `evaluaciones` (`nota_obtenida`,
  `nota_maxima`, `peso`). No hay tabla separada.
- **Proyectos** se conectan a `tareas`, `apuntes` y `eventos` vía
  `proyecto_id` opcional (FK con `on delete set null`). Cada proyecto
  activo tiene una **acción siguiente** como FK opcional
  `tarea_siguiente_id` a `tareas`.
- **Tope de 3 proyectos activos**: NO vive en la BD. Lo valida el cerebro
  en `POST /proyectos` y `PATCH /proyectos/{id}` y devuelve 409 con un
  mensaje legible para el usuario ("Ya tienes 3 activos: aparca o termina
  uno primero"). Razón: el error debe ser legible y el sitio natural
  para validar reglas de negocio es la API, no un trigger.
- **Coherencia acción siguiente ↔ proyecto**: si una tarea es
  `tarea_siguiente_id` de un proyecto, su `proyecto_id` debe apuntar a
  ese mismo proyecto. El cerebro lo valida; la BD no lo fuerza para no
  meter triggers complejos.
- **Bloque protegido** del proyecto: `jsonb` libre (ej.
  `{"dias_semana":[0,2,4],"hora_inicio":"06:00","hora_fin":"09:00"}`).
  En Capa 1 se almacena; la visualización fina puede esperar.
- **"En riesgo a los 3 días"** se calcula desde `ultima_actividad_en`;
  el cerebro lo refresca al editar el proyecto, al cambiar la acción
  siguiente y al completar una tarea asociada al proyecto.
- **"Proyecto" se usa en dos sentidos** en el dominio. (a)
  `evaluaciones.tipo = 'proyecto'`: un tipo de entrega académica dentro
  de un curso. (b) Tabla `proyectos`: proyectos vitales del usuario
  (Matix, OnExotic, Shadows Games). Son cosas distintas y no se
  cruzan.
- Toda PK es `uuid` con `gen_random_uuid()`.
- Toda tabla "vivible" tiene `creado_en/creada_en` y `actualizado_en/
  actualizada_en` mantenida por trigger.

---

## Pasos de la Capa 1

Cada paso se termina y se prueba antes de pasar al siguiente. El
usuario da el visto bueno explícito al cerrar cada paso.

### Paso 1 — Cimientos  *(en curso)*

- [ ] Estructura de carpetas: `app/`, `cerebro/`, `supabase/`, `docs/`.
- [ ] `supabase/migrations/0001_initial_schema.sql` con las 10 tablas,
      triggers de `actualizado_en` y RLS activada sin políticas.
- [ ] Aplicar la migración al proyecto Supabase existente.
- [ ] Esqueleto del cerebro: `pyproject.toml` (uv), `app/main.py` con
      `GET /health`, `app/config.py` cargando `.env`, `.env.example`.
- [ ] Esqueleto de la app Flutter (`flutter create`).
- [ ] `.gitignore` raíz (Python, Flutter, secretos, OS).
- [ ] `README.md` raíz con cómo arrancar cerebro y app.

**Listo cuando:** `uv run uvicorn app.main:app --reload` levanta el
cerebro y `GET /health` devuelve 200; `flutter run` abre la app vacía;
las 10 tablas existen en Supabase.

### Paso 2 — Conexión BD ↔ Cerebro

- [ ] Cliente Supabase configurado en el cerebro.
- [ ] Modelos Pydantic v2 para las 10 entidades.
- [ ] Endpoints CRUD (`GET`/`POST`/`PATCH`/`DELETE`) por entidad bajo
      `/api/v1/...`.
- [ ] Middleware que valida `X-Matix-Key`.
- [ ] Pruebas con `pytest` que cubran cada CRUD.

**Listo cuando:** los tests pasan y se puede crear una tarea de prueba
con `curl`.

### Paso 3 — App: navegación y tema

- [ ] Bottom nav personalizado con **cinco pestañas** y **Matix elevado al
      centro** (estilo FAB con gradiente azul → púrpura), siguiendo
      `mockups/matix-nav.jsx`:
      Inicio · Proyectos · **Matix (centro)** · Tareas · Universidad.
- [ ] Apuntes y Calendario **no** viven en la barra inferior. Calendario
      se abrirá desde Inicio (header + "Ver agenda"); Apuntes desde
      Universidad y desde Proyectos. Sus pantallas siguen existiendo en
      `app/lib/screens/` y se enchufan a las entradas en los pasos
      correspondientes.
- [ ] Stub vacío de cada pestaña (placeholder de "próximamente"),
      incluido Matix (el chat real llega en Capa 2).
- [ ] Theme + design tokens derivados de los mockups (colores,
      tipografía, radios, sombras).
- [ ] Cliente HTTP que apunta al cerebro vía `--dart-define MATIX_API_URL`.
- [ ] Manejo estándar de cargando / error / vacío / con datos.

**Listo cuando:** se navega entre las cinco pestañas, el centro elevado
de Matix se ve correctamente sobre la barra, y la app pinga al cerebro
al arrancar.

> Nota: el Paso 3 se cerró antes con un bottom nav distinto (5 ítems con
> Calendario en lugar de Matix y sin Proyectos). El rediseño aquí
> descrito reorganiza esas pestañas — no rehace el Paso 3 — y crea dos
> stubs nuevos: `matix_screen.dart` y `proyectos_screen.dart`.

### Paso 4 — Sección Tareas  *(vertical slice de extremo a extremo)*

- [ ] Pantalla de lista con vistas: Hoy, Esta semana, Todas, Completadas,
      por categoría / curso.
- [ ] Pantalla de creación y edición (matcha `mockups/Nueva Tarea`).
      **Incluye selector de proyecto** (FK opcional `proyecto_id`), junto
      a curso y categoría — se construye desde el inicio, no se remienda
      después.
- [ ] Subtareas inline.
- [ ] Vencidas resaltadas visualmente; no se ocultan.
- [ ] Repetición (diaria/semanal/mensual/anual) reflejada al completar.
- [ ] Hoja de filtros (`mockups/Filtros`): incluye **filtro por proyecto**
      junto a curso, categoría, prioridad y vencimiento.

Este paso valida el patrón completo UI ↔ cerebro ↔ BD; las secciones
siguientes lo replican.

### Paso 5 — Sección Calendario

Calendario no tiene pestaña propia: se accede desde Inicio (icono en el
header y enlace "Ver agenda" del bloque "Tu día"). El stub de
`calendario_screen.dart` ya existe; este paso lo convierte en pantalla
real y lo enchufa a las entradas desde Inicio.

- [ ] Vistas mes / semana / día.
- [ ] Crear y editar eventos.
- [ ] Horario de clases recurrente derivado de `sesiones_clase`.
- [ ] Las evaluaciones aparecen también en el calendario.
- [ ] Enlaces desde Inicio (header + "Ver agenda") navegan a la pantalla.

### Paso 6 — Sección Universidad

- [ ] Lista de cursos (nombre, profesor, horario, color).
- [ ] Detalle de curso: entregas, exámenes, calificaciones, apuntes.
- [ ] Cuenta regresiva a los exámenes próximos.
- [ ] Promedio calculado desde `nota_obtenida` / `nota_maxima` / `peso`.

### Paso 7 — Sección Apuntes

Apuntes no tiene pestaña propia: se accede desde Universidad (apuntes por
curso) y desde Proyectos (apuntes ligados al proyecto). El stub de
`apuntes_screen.dart` ya existe; este paso lo convierte en pantalla real
y lo enchufa a las entradas desde Universidad y Proyectos.

- [ ] Cuadernos y lista de apuntes.
- [ ] Editor de apunte con etiquetas y adjuntos (imágenes locales).
- [ ] Captura rápida manual desde el FAB.
- [ ] Enlace "Ver apuntes" desde el detalle de curso (Universidad) y
      desde el detalle de proyecto (Proyectos) navegan a la pantalla
      filtrando por `curso_id` o `proyecto_id`.

### Paso 8 — Sección Inicio (panel del día)

- [ ] Saludo + fecha.
- [ ] **"Tus 3 proyectos activos"**: card por proyecto con línea de meta,
      acción siguiente y badge de calor / "en riesgo" (3+ días sin
      avance).
- [ ] "Para hoy" (tareas del día).
- [ ] "Próximas entregas" (evaluaciones).
- [ ] "Tu día" (eventos de hoy).
- [ ] Resumen textual simple (la versión IA llega en Capa 2).

### Paso 9 — Sección Proyectos

Se construye después de Inicio porque ya hay tareas, apuntes y eventos
con `proyecto_id` listos para colgarse del proyecto.

Esquema previo: aplicar la migración `0002_proyectos.sql` (tabla
`proyectos` + FK `proyecto_id` en `tareas`, `apuntes` y `eventos`).

- [ ] Aplicar la migración `0002_proyectos.sql` al proyecto Supabase.
- [ ] Schemas Pydantic v2 (`Create` / `Update` / `Read`) para `proyectos`
      en el cerebro.
- [ ] Router CRUD `/api/v1/proyectos` con el mismo patrón de los otros 10.
- [ ] **Validación del tope de 3 activos en el cerebro** (no en la BD):
      `POST /proyectos` con `estado='activo'` y `PATCH /proyectos/{id}`
      que dejarían el total de activos a > 3 devuelven 409 con mensaje
      legible ("Ya tienes 3 activos: aparca o termina uno primero").
- [ ] El cerebro mantiene `ultima_actividad_en`: lo refresca al editar el
      proyecto, al cambiar la acción siguiente y al completar una tarea
      asociada al proyecto.
- [ ] El cerebro valida la **coherencia acción siguiente ↔ proyecto** (si
      una tarea es `tarea_siguiente_id` de un proyecto, su `proyecto_id`
      apunta a ese proyecto).
- [ ] El cerebro fija `inactivo_desde` al pasar a `aparcado` o
      `terminado`, y lo limpia al volver a `activo`.
- [ ] Pruebas pytest del router de proyectos, incluyendo: tope de 3
      activos (409), coherencia acción siguiente, `ultima_actividad_en`
      refrescada por edición.
- [ ] Pantalla **Lista de Proyectos**: 3 activos arriba en cards
      grandes con línea de meta, acción siguiente y badge de calor;
      aparcados aparte; terminados en sección colapsable.
- [ ] Pantalla **Detalle de Proyecto**: línea de meta editable, acción
      siguiente con botón "hecha → ¿siguiente?", tareas asociadas,
      apuntes asociados, eventos asociados, cambio de estado y
      `ultima_actividad_en` visible.
- [ ] Pantalla **Nuevo Proyecto** con *gating* del tope de 3: si ya hay
      3 activos, la UI obliga a aparcar/terminar uno antes de crear el
      cuarto (no espera a que el cerebro devuelva 409 — lo anticipa).
- [ ] **Modal de cambio de estado** (activar / aparcar / terminar) como
      confirmación explícita. Reutiliza el patrón de
      `mockups/Modal Borrar`.
- [ ] La pestaña Proyectos ya está en el bottom nav desde el rediseño
      del Paso 3 (es la posición 2, antes de Matix). Este paso solo
      reemplaza el stub `proyectos_screen.dart` por la pantalla real.

**Mockups nuevos a crear antes de empezar esta sección** (se añadirán a
`mockups/` cuando toque diseñarlos; no van en esta tanda de
planificación):

- `mockups/Proyectos.html` + `proyectos.jsx` — lista de proyectos.
- `mockups/Detalle Proyecto.html` + `detalle-proyecto.jsx` — detalle.
- `mockups/Nuevo Proyecto.html` + `nuevo-proyecto.jsx` — creación con
  el bloqueo del tope de 3.
- Actualización de `mockups/Inicio` para incluir el bloque "Tus 3
  proyectos activos".
- Actualización de `mockups/Nueva Tarea` y `mockups/Filtros` para el
  selector y filtro por proyecto (lo cubre el Paso 4).

### Paso 10 — Transversales

- [ ] Captura rápida manual (FAB en todas las pantallas).
- [ ] Búsqueda global sobre proyectos, tareas, apuntes y cursos.
- [x] **Ajustes**: pantalla informativa con URL del cerebro, ping,
      permisos de notificación, ver y cancelar notificaciones
      programadas, versión. Accesible vía icono settings en el
      AppBar de los stubs (mientras existan). *(adelantado el
      2026-05-25 como trabajo independiente; no edita
      configuración porque los valores vienen de `--dart-define`)*.

### Paso 11 — Recordatorios y notificaciones locales

- [x] `flutter_local_notifications` configurado para Android 13+.
      Permisos en `AndroidManifest`, core library desugaring en
      `build.gradle.kts`. *(2026-05-25)*
- [x] **Programar notificación al crear tarea con `recordar_en`**.
      `TareasRepository.crear` llama a `_reprogramarRecordatorio`.
      *(2026-05-25)*
- [x] **Reprogramar al editar; cancelar al completar o borrar**.
      Idempotente (cancel+programar) en `actualizar`,
      `marcarCompletada`, `borrar`. *(2026-05-25)*
- [ ] Pedir el permiso runtime de notificaciones (Android 13+) la
      primera vez que el usuario crea una tarea con recordatorio
      (ahora solo se pide desde Ajustes).
- [ ] Programar notificaciones también para **eventos** y
      **evaluaciones** con `recordar_en` (mismo patrón —
      `EventosRepository`, `EvaluacionesRepository` pasan a recibir
      `NotificacionesService` y replican `_reprogramarRecordatorio`).
- [ ] Probar end-to-end en el teléfono real (notif disparada,
      botón de la notif lleva al detalle).

### Paso 12 — Cierre de Capa 1

- [ ] Build de APK de release firmado de debug.
- [ ] Pruebas en dispositivo real cubriendo cada sección.
- [ ] Lista de regresiones marcada en `ESTADO.md`.
- [ ] Documentación de cómo correr todo desde cero.

---

## Convenciones del repo

- Idioma del código y la BD: español para nombres de dominio
  (`tareas`, `evaluaciones`, `proyectos`), inglés para términos técnicos
  (`created_at` → `creado_en`, `health`, `client`).
- Commits: pequeños y enfocados; mensaje en español.
- Secretos: nunca en el repo. `cerebro/.env` está ignorado;
  `cerebro/.env.example` documenta las variables.
- Sin frameworks JS para los mockups: viven en `mockups/` como
  referencia visual, no se importan al proyecto.
