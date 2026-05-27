# Matix — Contexto del Proyecto

Documento de contexto. Cualquier chat nuevo dentro de este proyecto puede
leerlo para entender Matix sin que haya que re-explicarlo desde cero.

---

## Qué es Matix

Matix es un asistente personal y centro de mando ("hub") para organizar la
vida del usuario, un estudiante universitario. Es de uso personal, no un
producto comercial.

- **Problema que resuelve:** olvidar las cosas que hay que hacer.
- **Principio de diseño:** captura sin fricción + resurgir confiable. Anotar
  algo tiene que ser instantáneo, y el sistema tiene que volver a traerlo
  (recordatorios) en el momento justo.
- **El rol de la IA:** "Matix" (la IA) es UNA pieza dentro del hub, a la que
  se accede por un botón flotante. No es toda la app — la app es el hub
  completo de secciones.

---

## Arquitectura — 3 piezas

- **App** — Flutter (Android). La interfaz del hub.
- **Cerebro** — Python + FastAPI. La inteligencia, las conexiones y el RAG.
  Corre localmente en la PC del usuario durante la Capa 1; se mueve a la nube
  más adelante.
- **Base de datos** — Supabase (PostgreSQL). Fuente única de verdad de todo
  el hub.

La base de datos se llena de tres formas: entrada manual, por voz a través de
Matix, y sincronización con Google.

---

## El hub — secciones

Inicio (dashboard), Tareas, Calendario, Universidad y Apuntes — más el botón
flotante de Matix.

Ideas aparcadas para más adelante: Hábitos, Finanzas, Metas, Salud.

---

## Construcción por capas (8 capas)

Matix se construye en 8 capas. Cada capa funciona de forma sólida y probada
antes de empezar la siguiente.

1. **Armazón del hub** — navegación + las 5 secciones + base de datos + CRUD
   manual + notificaciones locales.
2. **Matix: chat y voz.**
3. **Memoria (RAG) y modo tutor.**
4. **Sincronización con Google.**
5. **Casa inteligente** (Home Assistant).
6. **PC y archivos.**
7. **Visión por cámara.**
8. **Proactividad.**

---

## Sistema de diseño

- Tema oscuro.
- Paleta: fondo `#0B0F1A`, tarjetas `#161B2E`, azul de acento `#2D7FF9`,
  verde `#21D07A`, rojo `#FF4D5E`, ámbar `#E0A33A`, texto `#E8ECF4`, texto
  tenue `#8A93A8`.
- Tipografía: Inter para el texto, JetBrains Mono para lo monoespaciado.
- Cada curso tiene su propio color.
- Los design tokens viven en `app/lib/theme/` (colores, tipografía, radios,
  sombras, espaciados).

---

## Cómo se construye

- Por capas y con disciplina: cada paso sólido y probado antes del siguiente.
  No se construye todo a la vez.
- Herramientas: Claude Code dentro de Cursor escribe el código; este proyecto
  de Claude.ai funciona como mentor y segunda opinión en las decisiones.
- Documentos clave dentro del repositorio: `CLAUDE.md` (contexto para Claude
  Code), `docs/Mapa_del_Hub.md` (plano de todas las pantallas),
  `docs/Plan_Capa1.md` y `docs/ESTADO.md`.

---

## Estado actual

Para saber en qué capa y en qué paso va el proyecto, ver el documento
**"Matix — Estado del Proyecto"**, que se actualiza con el avance.
