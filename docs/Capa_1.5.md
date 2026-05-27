# Capa 1.5 — pulidos que no bloquean Capa 2

Lo que quedó pendiente al cerrar Capa 1 visualmente y que **no
bloquea** la construcción de Capa 2 (chat con Matix). Son mejoras que
hacen la app más completa pero ya tiene la funcionalidad nuclear.

Se retoman cuando Capa 2 esté estable, o intercalados si una pausa lo
permite.

---

## A — UI faltante

1. **Editar el bloque protegido del proyecto desde la app.**
   Hoy la BD guarda `bloque_protegido` (JSONB) y `DetalleProyecto` lo
   muestra si existe (`L / Mi / V · 06:00 – 09:00`). Falta UI para
   crearlo / editarlo / borrarlo. Diseño: bottom sheet con chips de
   días (Lun..Dom) + dos `TimePicker` (inicio, fin) + botón "Quitar".
   Endpoint del cerebro ya lo soporta vía PATCH `/proyectos/{id}` con
   `{"bloque_protegido": {...}}`.

2. **Pantalla "Detalle de tarea" rica** (mockup `Detalle Tarea.html`).
   Hoy al tocar una tarea se abre `NuevaTareaScreen` en modo edición
   — funcional pero plano. La versión rica del mockup tiene barra de
   progreso de subtareas, sección de adjuntos, tarjeta de sugerencia
   de Matix. Recomendado hacerla después de Capa 2 (la tarjeta de
   sugerencia ya hablará con Matix de verdad).

3. **Vista "Por curso/categoría/proyecto" agrupada en Tareas**. Hoy
   la quinta pestaña es "Por curso". Documento Maestro pide poder
   también agrupar por categoría o por proyecto sin abandonar la
   vista. Patrón: pulsar la pestaña la cicla entre "Por curso →
   Por categoría → Por proyecto".

4. **Botón "Definir bloque protegido"** en `DetalleProyecto` cuando
   el proyecto no tiene uno todavía. Hoy si no está, simplemente no
   se muestra nada.

5. **Editar / borrar evaluaciones y sesiones de clase** desde la app.
   Hoy se pueden crear (Diálogos en Universidad) pero no editar más
   que vía API directa. Acción de "long press → menú" en cada fila.

6. **Pantalla "Detalle de evento"** completa. Hoy tocar un evento del
   calendario no hace nada — solo se ve en la lista. Diseño:
   `NuevoEventoScreen` en modo edición + acción borrar.

---

## B — Mockups por ajustar a datos reales

7. **Mockup `Calendario.html`** con tus 7 cursos reales del Documento
   Maestro y horario semanal exacto. Ahora tiene placeholders
   genéricos (Cálculo III, Física II).

8. **Mockup `Universidad.html`** con los 7 cursos reales como cards.

9. **Mockup `Tareas.html`** con datos consistentes con los proyectos
   reales (Matix, OnExotic, Shadows Games) en lugar de Estadística
   II / Filosofía de la Ciencia.

---

## C — Funcionalidad menor

10. **APK release firmada con keystore propio**. Hoy la release usa
    la debug-key — funciona pero no se puede subir a Play Store.
    Genera keystore con `keytool`, configurar `signingConfig` en
    `build.gradle.kts`, guardar password en `key.properties`
    (gitignored).

11. **Validación de fecha de evento (inicio < fin)** en
    `NuevoEventoScreen`. La BD ya tiene el `CHECK (termina_en >=
    inicia_en)` pero la UI no avisa antes del 422.

12. **Mejor manejo de errores transitorios en `MatixClient`**.
    Reintento exponencial 3 veces para 5xx y errores de red — ahora
    los muestra directo al usuario.

13. **Pantalla "Notificaciones"** del mockup ya está diseñada pero no
    enchufada. Si el usuario quiere ver el historial de notifs (las
    locales no se guardan, pero las que envíe la app sí podrían).

14. **Tests UI Flutter** con `pumpWidget` + providers mockeados para
    Inicio, Proyectos, Calendario. Hoy solo hay tests unitarios de
    lógica pura + smoke widget.

---

## D — Higiene

15. **Rotar credenciales expuestas en chat**: access token de
    Supabase, DB password, `MATIX_API_KEY`, `OPENAI_API_KEY`. Cuando
    rotes, actualizar `cerebro/.env`.

16. **Limpieza de `_stub_screen.dart`** cuando se elimine el último
    stub (queda Matix, que se va en Capa 2 Paso 3).

17. **README global** con un diagrama de las 12 entidades de la BD y
    sus relaciones — útil cuando alguien (o yo, en 6 meses) entre al
    repo sin contexto.

---

## E — Documento Maestro pendiente

18. **Bloque protegido del proyecto** ya tiene UI de lectura ✓ pero
    falta UI de escritura (A1 arriba). Y falta **detectar conflictos
    del bloque** con clases / eventos (si Matix tiene su bloque
    L/Mi/V 6–9 am y el usuario crea un evento ahí, advertencia).

19. **Recordatorios graduados por importancia**. Hoy todos van con la
    misma intensidad. El Documento Maestro §11 dice "lo fuerte para
    absolutamente todo tiende a perder efecto". Capa 8
    (Proactividad) lo cubrirá; mientras tanto, dejar el canal de
    notificación con `Importance.high` está bien.

20. **Detectar choques con el bloque protegido**. El choque
    horario-vs-horario ya está (Calendario). Falta:
    proyecto-con-bloque-protegido + evento-que-pisa-bloque.

---

## Priorización sugerida

Cuando Capa 2 esté estable, atacar en este orden:
1. **A1 + A4** (editar bloque protegido) — destraba un concepto del
   Documento Maestro completamente.
2. **A2** (Detalle de tarea rica) — la app se siente más madura.
3. **C10** (APK release firmada) — cuando sea momento de instalar
   "en serio" y no dependerme.
4. El resto, a gusto, sin prisa.

Capa 2 destrabará automáticamente la utilidad de muchas de estas: una
vez Matix puede crear tareas por voz, la pantalla de Detalle de tarea
rica importa menos porque la creación rápida se hace hablando.
