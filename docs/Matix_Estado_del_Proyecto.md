# Matix — Estado del Proyecto

Snapshot al 24 de mayo de 2026.

---

## 1. Qué es Matix

Matix es un asistente personal y centro de mando ("hub") para organizar la
vida del usuario — tareas, universidad, calendario y apuntes — con una IA
integrada. Es de uso personal.

Arquitectura: una app móvil en Flutter (Android), un "cerebro" en Python con
FastAPI, y una base de datos en Supabase (PostgreSQL).

Se construye por capas: 8 capas en total, cada una sólida y probada antes de
pasar a la siguiente.

Fase actual: **Capa 1 — Armazón del hub, en construcción.**

---

## 2. Lo que está implementado

### Diseño — completo
- Concepto, arquitectura y plan de 8 capas definidos.
- Documentos base del proyecto: CLAUDE.md, docs/Mapa_del_Hub.md,
  docs/Plan_Capa1.md, docs/ESTADO.md.
- Mockups de las pantallas del hub, con paleta de color (tema oscuro) y
  design tokens derivados de ellos.

### Entorno de desarrollo — completo
- Python, uv, Flutter, Android Studio (toolchain de Android verificado),
  Claude Code, Cursor y Git instalados y funcionando.
- Supabase: cuenta, organización y proyecto "matix" creados.

### Capa 1 — Armazón del hub — en construcción (3 de ~11 sub-pasos)

- **Paso 1 — Base de datos y esqueletos · Completado.**
  Esquema inicial con 10 tablas (perfil, categorías, cursos, sesiones de
  clase, tareas, subtareas, evaluaciones, eventos, cuadernos, apuntes), con
  RLS activo en todas. Migración aplicada al proyecto matix. Esqueletos de
  app/ y cerebro/ creados.

- **Paso 2 — API del cerebro · Completado.**
  CRUD completo de las 10 entidades en el cerebro (esquemas, routers
  /api/v1, autenticación por clave). 24 de 24 pruebas en verde.

- **Paso 3 — Navegación y tema de la app · Completado a nivel de código.**
  Tema visual (colores, tipografía, radios, sombras, espaciados),
  navegación inferior con las 5 secciones, pantallas base ("stubs"),
  cliente HTTP hacia el cerebro. Compila y pasa pruebas.
  Pendiente: la validación visual corriendo la app.

---

## 3. Lo que falta

### Para terminar la Capa 1
- Validar visualmente el Paso 3 (correr la app en el emulador).
- Paso 4 — Sección Tareas: la primera pantalla con funcionalidad real
  contra el cerebro.
- Pasos 5 a 11 — el resto de secciones (Calendario, Universidad, Apuntes,
  e Inicio con datos reales) y las funciones transversales (recordatorios y
  notificaciones, búsqueda, ajustes), hasta cerrar el armazón del hub. El
  detalle exacto de cada sub-paso está en docs/Plan_Capa1.md.

### Las siguientes capas (2 a 8)
- Capa 2 — Matix: chat y voz.
- Capa 3 — Memoria (RAG) y modo tutor.
- Capa 4 — Sincronización con Google (calendario, tareas, correo).
- Capa 5 — Casa inteligente (Home Assistant).
- Capa 6 — PC y archivos.
- Capa 7 — Visión por cámara.
- Capa 8 — Proactividad.

### Pendientes de seguridad y configuración
- Rotar el access token de Supabase.
- Resetear la contraseña de la base de datos.
- Regenerar el MATIX_API_KEY.
- Instalar Tailscale en la PC y en el Android (para cuando la app, en un
  teléfono real, deba alcanzar el cerebro).
- Confirmar que cerebro/.env esté completo (incluida la clave service_role).

---

## 4. Próximo paso inmediato

Correr la app por primera vez y validar el Paso 3:

1. En una terminal, levantar el cerebro.
2. En otra, arrancar el emulador Pixel 9 y correr la app.
3. Revisar que la base visual (fondo oscuro, navegación de 5 secciones)
   encaje con los mockups. Las pantallas saldrán vacías con un badge
   "Próximamente" — eso es lo esperado en esta etapa.
4. Si encaja, dar luz verde al Paso 4; si algo se ve raro, anotarlo.

Los comandos exactos los entregó Claude Code en su último reporte.

---

## 5. El principio que guía el proyecto

Matix se construye por capas. Cada capa funciona de forma sólida y probada
antes de empezar la siguiente. No se construye todo a la vez. Tener el mapa
completo no cambia eso — solo da claridad de hacia dónde se avanza.
