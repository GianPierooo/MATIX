# CLAUDE.md — Matix

Este archivo es el contexto global del proyecto Matix. Léelo completo antes
de escribir cualquier código. Junto a este archivo hay dos referencias más
que también debes leer antes de empezar:

- `docs/Mapa_del_Hub.md` — el detalle completo de todas las secciones.
- `mockups/` — la referencia visual del diseño.

Las decisiones de arquitectura, el plan por capas y las reglas de seguridad
son obligatorias.

---

## 1. QUÉ ES MATIX

Matix es un asistente personal y centro de mando de la vida del usuario, de
uso privado. NO es un producto para vender.

El problema central que resuelve: al usuario se le olvidan las cosas que
tiene que hacer. Por eso Matix no es una app de chat — es un hub donde el
usuario ve y organiza su vida (tareas, universidad, calendario, apuntes), y
"Matix", la IA, es una pieza dentro de ese hub que le ayuda a capturar y
gestionar todo.

Todo el diseño gira en torno a dos principios:

1. Capturar sin fricción — registrar algo debe tomar segundos, por voz o
   con la captura rápida. Lo que cuesta registrar es lo que se pierde.
2. Que las cosas vuelvan al usuario — recordatorios, notificaciones, el
   resumen del día y las tareas vencidas que se resaltan en vez de
   esconderse.

---

## 2. ARQUITECTURA — TRES PIEZAS

PARTE A — App móvil (Android), en Flutter
La interfaz del hub. Tiene estructura propia: una pantalla de Inicio y
varias secciones. Captura entrada (texto, voz), muestra la información y
permite gestionarla. La lógica pesada e inteligente NO vive aquí.

PARTE B — El cerebro, en Python con FastAPI
Donde vive la inteligencia: razonamiento con la API de Claude, RAG,
automatizaciones y conexiones a servicios externos. Alojado en la nube,
siempre encendido. En la Capa 1 corre en local, en la PC del usuario,
para desarrollo.

PARTE C — La base de datos, en Supabase (PostgreSQL)
La fuente única de verdad de todo el hub: tareas, notas, cursos, eventos.
Es cimiento desde la Capa 1. En capas posteriores usa la extensión
pgvector para el RAG.

La app se comunica con el cerebro mediante una API. El cerebro lee y
escribe en la base de datos.

---

## 3. EL MODELO DE DATOS — UN HUB, TRES ENTRADAS

Toda la información del hub vive en una sola base de datos. Se llena de tres
formas, y las tres terminan en el mismo lugar:

1. Manual — el usuario crea y edita desde la app.
2. Por voz con Matix — el usuario habla, el cerebro entiende la intención
   con la API de Claude y crea o edita el registro.
3. Sincronizada — desde servicios externos como Google Calendar (capas
   posteriores).

El hub simplemente muestra, ordenado, lo que hay en la base de datos.

---

## 4. EL HUB — SECCIONES

El detalle completo de cada sección está en `docs/Mapa_del_Hub.md`.

El hub tiene **siete secciones**. La **barra inferior** muestra cinco, con
Matix elevado en el centro como FAB; las otras dos (Calendario y Apuntes)
viven fuera de la barra:

**En la barra inferior** (Inicio · Proyectos · Matix · Tareas · Universidad):

- Inicio — el panel del día: resumen de Matix, tus 3 proyectos activos,
  tareas de hoy, próximas entregas y eventos del día. Desde aquí se abre
  el Calendario.
- Proyectos — los 3 proyectos activos a la vez, cada uno con su línea de
  meta y su acción siguiente; los aparcados y los terminados aparte.
  Crear un cuarto activo está bloqueado hasta aparcar o terminar otro.
- Matix (centro, FAB elevado) — la conversación con la IA. En Capa 1 es
  un stub "próximamente"; toma vida en Capa 2.
- Tareas — todas las pendientes, con prioridad, categoría, curso o
  proyecto, fecha y subtareas.
- Universidad — cursos, entregas, exámenes, calificaciones y apuntes por
  curso. Desde aquí se accede también a los Apuntes.

**Fuera de la barra** (accesibles desde el header de Inicio):

- Calendario — eventos + horario de clases recurrente (vista mensual +
  lista del día). Icono `calendario` en el AppBar de Inicio.
- Apuntes — notas con etiquetas. Icono `note` en el AppBar de Inicio
  (y desde Universidad / Proyectos cuando se construyan esas
  asociaciones por contexto).
- **Búsqueda global** — icono `lupa` en el AppBar de Inicio. Filtra
  proyectos, tareas, apuntes y cursos.
- **Cierre del día** — icono `luna` en el AppBar de Inicio. Ritual
  nocturno: 3 cosas que sí hice + descarga mental.
- **Ajustes** — icono `engranaje` con gradiente en el AppBar de Inicio
  (y también accesible desde el AppBar de los stubs que queden).

Transversal a toda la app: los recordatorios y notificaciones locales
programados desde `recordar_en` de cada entidad. El FAB de micrófono
que aparece en los mockups llega en la Capa 2 (junto al resto de
Matix).

---

## 5. PLAN POR CAPAS

Matix se construye POR CAPAS. Cada capa debe funcionar de forma sólida y
estar probada antes de empezar la siguiente. No se construye todo a la vez.

CAPA 1 — Armazón del hub
App Flutter con la navegación completa (cinco pestañas en la barra inferior
con Matix elevado al centro; Calendario y Apuntes accesibles desde otras
pantallas). Cerebro Python con FastAPI. Base de datos en Supabase con sus
tablas. El usuario puede crear, ver y editar proyectos, tareas, notas,
cursos y eventos a mano. Incluye recordatorios y notificaciones locales.
Resultado: un organizador personal funcional y útil por sí solo.

CAPA 2 — Matix: chat y voz
El cerebro conectado a la API de Claude. Botón flotante de Matix. El
usuario habla o escribe, y Matix crea y edita tareas, eventos y notas.

CAPA 3 — Memoria (RAG)
RAG con pgvector en Supabase. Matix conoce los apuntes y el contexto del
usuario. Incluye el modo tutor: explicar temas, resumir, generar preguntas
de práctica.

CAPA 4 — Sincronización
Calendario, tareas y correo de Google entran al hub mediante MCP.

CAPA 5 — Casa inteligente
Integración con Home Assistant.

CAPA 6 — PC y archivos
Acceso y control de la computadora del usuario.

CAPA 7 — Visión
Visión por cámara; incluye convertir una foto en un apunte.

CAPA 8 — Proactividad
Matix avisa y actúa por iniciativa propia.

Capa en construcción: CAPA 1.

---

## 6. STACK TÉCNICO

- App: Flutter (Android).
- Captura de voz: speech-to-text. Reproducción de voz: en la Capa 1 se usa
  el TTS del sistema (gratis); más adelante se puede usar una voz premium
  como ElevenLabs.
- Cerebro: Python con FastAPI.
- Inteligencia: API de Claude (Anthropic).
- Conexiones a herramientas: MCP (Model Context Protocol).
- Base de datos y memoria: Supabase (PostgreSQL) con pgvector.
- Casa inteligente: Home Assistant.
- Alojamiento del cerebro: Railway o Render (en la Capa 1 corre en local).

---

## 7. SEGURIDAD Y PRIVACIDAD (CRÍTICO)

Matix maneja información muy personal. La seguridad es prioridad máxima.

- Todas las claves de API, tokens y credenciales van en variables de
  entorno, nunca en el código ni en el repositorio.
- El acceso al cerebro está protegido con autenticación: solo la app del
  usuario puede comunicarse con él.
- La información personal se almacena de forma privada, con acceso
  restringido al usuario.
- Las conexiones a servicios externos usan los permisos mínimos
  necesarios.
- Para acciones sensibles o irreversibles (enviar correos, borrar cosas),
  Matix pide confirmación antes de ejecutar.
- Nunca exponer datos personales en logs.
- El repositorio del proyecto es privado.

---

## 8. CONVENCIONES DE CÓDIGO

- Código limpio, modular y bien organizado.
- Python: type hints, PEP 8, funciones pequeñas y con propósito claro.
- Flutter: componentes separados; manejar siempre los estados cargando,
  error, vacío y con datos.
- Cada capa y cada sección se desarrollan de forma modular, para poder
  ampliar sin romper lo anterior.
- Manejo de errores robusto: Matix nunca debe quedar mudo ante un fallo;
  siempre responde algo útil.
- Documentar las partes complejas.
- Nunca hardcodear secretos.

---

## 9. ESTÁNDAR DE CALIDAD

Matix se construye con ambición y a conciencia. No hay prisa por terminar;
hay prioridad por hacerlo bien. Arquitectura sólida, código mantenible,
cada capa probada. El objetivo es un asistente personal real y potente,
construido de forma profesional y sostenible en el tiempo.

---

## 10. CÓMO TRABAJAR EN ESTE PROYECTO

- Antes de empezar una capa, presentar un plan claro y esperar revisión
  del usuario. No lanzarse a codear de inmediato.
- No avanzar a la siguiente capa hasta que la actual funcione y esté
  probada de forma sólida.
- Construir cada capa sección por sección, no todo de golpe.
- Ante una duda de diseño, preguntar antes de asumir.

### Commit + push al cerrar cada paso (norma estable)

- **Cada paso se cierra con un commit + push a `main`** — no se
  acumulan pasos sin commitear. Acumular rompe el ciclo de validación
  en device: el usuario necesita que el APK que construye el CI
  contenga el trabajo del paso para poder probarlo en el teléfono.
- Un commit por paso, con mensaje `feat(capaN/M): <descripción>` (o
  `fix(...)`, `docs(...)` según corresponda). Esto mantiene la
  historia limpia y permite rollback selectivo por paso.
- Esta norma rige aunque el paso haya pedido "detente para validación":
  primero se entrega y valida el trabajo, y el cierre del paso incluye
  dejarlo commiteado y pusheado, no en el working tree.
