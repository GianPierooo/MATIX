# Pendientes de revisión del usuario

Cosas que necesitan **ojos del usuario** (revisión visual, decisión de
producto, decisión de arquitectura) y que no se pueden verificar solo con
`flutter analyze` o `pytest`. La IA las anota aquí y sigue con otro
trabajo que no dependa de ellas.

Convención: `[ ]` pendiente, `[x]` resuelto. Eliminar cuando lo apruebes.

---

## Bloqueantes (paralizan trabajo aguas abajo)

- [ ] **Reconectar el teléfono por USB** (con depuración USB activa
      como antes). Hay una APK debug recién compilada
      (`app/build/app/outputs/flutter-apk/app-debug.apk`, 12 s de
      build) lista para instalar — incluye fix del locale `es`,
      parser de errores legibles, plugin de notificaciones (sin
      integrar aún) y todas las mejoras de la última tirada. En
      cuanto lo reconectes te la instalo en segundos.
- [ ] **Visto bueno a la plantilla del Paso 4.B (Sección Tareas).** Es la
      plantilla que los Pasos 5–8 (Calendario, Universidad, Apuntes,
      Inicio) van a copiar. Hasta que la apruebes no propago el patrón.
      Validar en el teléfono:
  - Pestaña **Tareas**: AppBar con fecha + título, icono filtros arriba
    a la derecha, 5 pills (Hoy activo · Esta semana · Todas · Completadas
    · Por curso), mensaje vacío "No tienes tareas para hoy", FAB
    "+ Nueva tarea" abajo a la derecha.
  - **+ Nueva tarea**: formulario con título, nota, prioridad
    (segmented), vencimiento (date+time picker), recordatorio,
    repetición, dropdowns Curso/Categoría/Proyecto (vacíos o con lo que
    pre-existe en la BD), botón "Crear tarea".
  - Crear una tarea de prueba: se cierra el form, vuelve a la lista, la
    tarea aparece.
  - Tocar la tarea creada → reabre el form en modo "Editar tarea" con
    sección **Subtareas** inline (input para añadir, checkbox para
    marcar, botón eliminar).
  - Tocar el icono de filtros: bottom sheet con prioridad / vencimiento
    / curso / categoría / proyecto. Combinable con la vista activa.
  - Comportamiento de **vencidas**: si la tarea tiene fecha pasada y no
    está completada, su card se ve resaltada en rojo suave y el chip de
    fecha en rojo intenso.

## No bloqueantes

- [ ] **Rotar credenciales expuestas en chat** (apuntado en
      `ESTADO.md`): access token de Supabase, DB password,
      `MATIX_API_KEY`, y la **`OPENAI_API_KEY`** que pasaste en
      2026-05-26 (también quedó en el chat). Cuando rotes, actualiza
      `cerebro/.env` con las nuevas.
- [ ] **Revisar mockups de Proyectos** (los redacté yo siguiendo el
      Documento Maestro). Los tres están en `mockups/`:
      `Proyectos.html` (lista con Matix #1, OnExotic #2, Shadows Games
      #3 activos + aparcados + terminados), `Detalle Proyecto.html`
      (hero, línea de meta, acción siguiente, meta-rows, tareas,
      apuntes, footer "Aparcar / Terminar"), `Nuevo Proyecto.html`
      (con el caso "tope alcanzado" mostrando los 3 actuales y forzando
      aparcar/terminar antes de crear el cuarto). Si te encaja, los
      tomamos como definitivos para el Paso 9; si quieres cambios, los
      ajusto.
- [ ] **¿Subir RAM del AVD a 4 GB**? Si quieres tener el emulador como
      red de seguridad por si el teléfono no está disponible, esa subida
      lo deja usable. No urge — el teléfono físico va de sobra.

---

## Convención para añadir aquí

Cuando la IA escribe en este archivo:
- **Bloqueante** si lo que se pause aquí impide trabajo aguas abajo
  (plantillas, contratos, decisiones de arquitectura).
- **No bloqueante** si la IA puede seguir trabajando en otras partes
  sin que esto se resuelva.

Cuando el usuario marca `[x]`, la IA lo limpia del archivo en el
siguiente turno.
