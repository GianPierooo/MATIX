# Matix — Mapa completo del hub

Este documento es la visión completa de Matix: todas las secciones, todo lo
que habrá en cada pantalla y en qué capa se construye cada cosa.

Importante: esto es el mapa, no la orden de construcción de todo a la vez.
Matix se construye capa por capa; cada capa funciona sólida antes de la
siguiente. La lista larga solo nos da claridad de hacia dónde vamos.

---

## EL PROBLEMA QUE RESUELVE

El objetivo central de Matix es que no se te olvide lo que tienes que hacer
— y que termines lo que empiezas. Todo el diseño gira alrededor de dos
principios:

1. Capturar sin fricción — meter algo (una tarea, una idea, un evento) debe
   tomar segundos: por voz a Matix o con la captura rápida. Lo que cuesta
   registrar es lo que se pierde.
2. Que las cosas vuelvan a ti — recordatorios, el resumen del día y las
   tareas vencidas que se resaltan en vez de esconderse. Matix no espera a
   que te acuerdes; te lo recuerda él.

---

## CÓMO SE ORGANIZA LA APP

- Una pantalla de Inicio que es tu panel del día.
- El hub tiene **siete secciones** en total. La **barra inferior** muestra
  cinco: Inicio · Proyectos · **Matix (centro)** · Tareas · Universidad.
- Las otras dos (**Calendario** y **Apuntes**) son secciones del hub pero
  viven fuera de la barra: Calendario se abre desde Inicio (botón en el
  header y "Ver agenda" del bloque "Tu día"); Apuntes se abre desde
  Universidad (por curso) y desde Proyectos (apuntes ligados al proyecto).
- El **botón central de Matix** sobresale como FAB elevado. En Capa 1 es
  un stub "próximamente"; toma vida en Capa 2.

---

## LAS SECCIONES

### 1. Inicio — el panel del día  (Capa 1)
La primera pantalla al abrir la app. De un vistazo:
- Saludo y fecha.
- Resumen de Matix: qué tienes hoy y qué urge.
- "Tus 3 proyectos activos": una card por proyecto con su línea de meta,
  su acción siguiente y el badge de calor ("en riesgo" si lleva 3+ días
  sin avance).
- "Para hoy": las tareas del día.
- "Próximas entregas": los vencimientos de la universidad.
- "Tu día": los eventos del calendario de hoy.
Si algo importante existe, aparece aquí. Es tu centro de control.

### 2. Proyectos  (Capa 1, manual)
Tus proyectos vitales — el corazón de "terminar lo que empiezas".
- Vista principal: los **3 activos** en cards grandes, con nombre, línea
  de meta, acción siguiente, prioridad (1/2/3), última actividad y badge
  de calor.
- **Aparcados** aparte: en pausa consciente, esperando su turno. No es
  abandono.
- **Terminados**: sección colapsable, como historial.
- Cada proyecto tiene: nombre, descripción, estado
  (activo/aparcado/terminado), línea de meta (la definición de
  "terminado"), acción siguiente (una tarea concreta), última actividad,
  prioridad, bloque de tiempo protegido (ej. L/Mi/V 6–9 am) y color.
- Tareas, apuntes y eventos pueden colgarse de un proyecto vía
  `proyecto_id` opcional.
- **Tope de 3 activos**: crear un cuarto proyecto activo está bloqueado.
  La pantalla obliga a elegir cuál aparcar o terminar primero — decisión
  explícita, no silenciosa.
- **Cambios de estado** (activar / aparcar / terminar) requieren un modal
  de confirmación, no un dropdown silencioso.
- Pantallas: Lista de Proyectos, Detalle de Proyecto, Nuevo Proyecto
  (con el bloqueo del tope), modal de cambio de estado.

### 3. Tareas  (Capa 1, manual)
Todas tus pendientes en un solo lugar.
- Vistas: Hoy, Esta semana, Todas, Completadas y por categoría.
- Hoja de filtros sobre la vista activa: combinar curso, categoría,
  proyecto, prioridad y vencimiento sin salir de Tareas.
- Cada tarea tiene: título, fecha y hora límite, prioridad (alta, media,
  baja), categoría o curso o proyecto, una nota opcional y opción de
  repetición.
- Subtareas para dividir algo grande en pasos.
- Pantalla para crear o editar una tarea (incluye selector de proyecto).
- Las tareas vencidas no desaparecen: se resaltan hasta que las atiendas.

### 4. Calendario  (Capa 1 manual · Capa 4 sincronizado)
Tu tiempo, visto en grande.
- Vistas de mes, semana y día.
- Eventos: clases, cosas personales; las entregas también se reflejan aquí.
- Tu horario de clases recurrente de la semana.
- Crear y editar eventos.
- En la Capa 4 se sincroniza con Google Calendar.

### 5. Universidad  (Capa 1, manual)
El apartado para tu vida académica.
- Lista de cursos: cada uno con nombre, profesor, horario y un color.
- Dentro de un curso: sus entregas, sus exámenes, sus calificaciones y sus
  apuntes.
- Cuenta regresiva para los exámenes próximos.
- Tu promedio, si vas registrando las notas.

### 6. Apuntes  (Capa 1 manual · Capa 3 inteligente)
Donde guardas lo que no quieres perder.
- Notas organizadas por cuaderno, curso, proyecto o etiqueta.
- Cada nota: título, texto y la posibilidad de adjuntar imágenes.
- Captura rápida: una idea suelta entra en segundos.
- Desde la Capa 3, Matix puede resumir tus apuntes y hacerte preguntas de
  práctica con ellos.

### 7. Matix — conversación  (Capa 2)
La pantalla del asistente, se abre con el botón flotante.
- Hablas o escribes.
- Matix responde y, sobre todo, actúa: crea y edita proyectos, tareas,
  eventos y notas por ti.
- Guarda el historial de la conversación.

### 8. Cierre del día  (Capa 1)
Ritual nocturno del Documento Maestro: cada noche, registrar 3 cosas
que sí hice. Se accede desde el icono de luna en el header de Inicio.
- Campos numerados (sugerencia 3, máximo libre).
- Espacio para "descarga mental nocturna" (lo que ronda antes de dormir).
- UPSERT por fecha: si vuelves a entrar al mismo día, edita el cierre
  existente.
- Tabla `cierres_dia` (migración 0003).

---

## PRESENTE EN TODA LA APP (transversal)

- Botón flotante de Matix — en cada pantalla, a un toque.  (Capa 2)
- Captura rápida — desde donde estés, sueltas algo y va al lugar correcto.
  (Capa 1 en versión manual · Capa 2 por voz)
- Recordatorios y notificaciones — el teléfono te avisa antes de que algo
  venza. Es el corazón anti-olvido de Matix.  (Capa 1)
- Búsqueda global — una palabra, y la encuentras en proyectos, tareas,
  apuntes y cursos. Se abre desde el icono de lupa en el header de
  Inicio.  (Capa 1)
- Ajustes — conexión con el cerebro, voz, notificaciones y tema.  (Capa 1)

---

## LO QUE HACE MATIX (la inteligencia)

- Crear y editar por voz — le dictas y aparece en tu hub.  (Capa 2)
- Briefing de la mañana y cierre del día — te habla para arrancar y cerrar
  el día.  (Capa 2)
- Matix tutor — explica temas, resume material y te hace preguntas de
  práctica desde tus apuntes.  (Capa 3)
- Filtro de correo — te dice solo lo importante de tu bandeja.  (Capa 4)
- Foto a apunte — fotografías la pizarra y se convierte en una nota.
  (Capa 7)
- Proactividad — Matix te avisa solo: "tienes una entrega mañana y no la
  has empezado" o "llevas 4 días sin tocar OnExotic".  (Capa 8)

---

## EL PLAN DE CONSTRUCCIÓN — 8 CAPAS

CAPA 1 — Armazón del hub
Navegación completa, las seis secciones (incluida Proyectos), base de
datos en Supabase, crear/ver/editar a mano, y recordatorios y
notificaciones. Ya es un organizador personal real y útil por sí solo.

CAPA 2 — Matix: chat y voz
API de Claude, botón flotante, conversación. Le hablas y crea o edita tus
proyectos, tareas, eventos y notas.

CAPA 3 — Memoria (RAG)
Matix conoce tus apuntes y tu contexto. Incluye el modo tutor.

CAPA 4 — Sincronización
Google Calendar, Tasks y correo entran al hub vía MCP.

CAPA 5 — Casa inteligente
Integración con Home Assistant.

CAPA 6 — PC y archivos
Acceso y control de tu computadora.

CAPA 7 — Visión por cámara
Detección de acciones por cámara; incluye foto a apunte.

CAPA 8 — Proactividad
Matix avisa y actúa por iniciativa propia.

No se avanza a una capa hasta que la anterior funcione y esté probada.

---

## GUARDADO PARA DESPUÉS

Ideas buenas que no entran al plan ahora, pero que el hub —al diseñarse
modular— podrá recibir más adelante sin rehacer nada:

- Hábitos y rutinas
- Finanzas personales
- Metas y objetivos (a más largo plazo que un proyecto)
- Salud y bienestar
<!-- Cierre del día YA está construido — ver sección 8 arriba. -->
- Modo enfoque (temporizador tipo Pomodoro)
- Resumen semanal
- Widget de Android en la pantalla de inicio del teléfono

---

## EL PRINCIPIO QUE NO SE ROMPE

Esto es la visión completa de Matix. No se construye de golpe: se construye
capa por capa, y cada capa funciona de forma sólida antes de empezar la
siguiente. Tener el mapa completo no cambia eso — solo nos deja claro hacia
dónde vamos en cada paso.
