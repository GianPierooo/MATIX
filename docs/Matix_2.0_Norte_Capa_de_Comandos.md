# Matix 2.0 — Norte de Arquitectura: Capa de Comandos Unificada

> Documento de diseño. Captura la decisión arquitectónica para que Matix (la IA)
> tenga **control total de la app, hasta lo más específico**.
>
> **No se construye hasta que 1.0 esté cerrado y validado con los 7 días.**
> Esta convergencia es el primer gran proyecto de 2.0.

---

## El objetivo

Que cualquier cosa que el usuario pueda hacer en la app a mano, Matix pueda
hacerla también: navegar, crear, editar, configurar, archivar, en cualquier
sección y hasta el detalle más específico.

## El principio (el corazón de todo)

No se logra haciendo que la IA manipule la pantalla. Se logra con **una sola capa
de comandos que invocan por igual la UI, la IA, la voz y las automatizaciones.**
Es el patrón de **núcleo headless con clientes delgados**.

- Cada capacidad del usuario = una **acción tipada** en un registro central.
- El botón de la UI no tiene lógica propia; llama a la acción.
- La IA no toca la pantalla; llama a la misma acción.
- Resultado: la IA hereda **exactamente** la superficie de la UI. El control total
  deja de ser una feature que se persigue y se vuelve una propiedad de la
  arquitectura.

El antipatrón (lo que probablemente hay hoy en parte): la UI tiene su lógica y la
IA tiene una superficie paralela de tools. El gap entre ambas listas ES el límite
actual de control de Matix.

## Prácticas profesionales de referencia

- **Command palette** (Linear, Slack, Superhuman, Notion): el cmd-K que lista toda
  acción de la app en un registro único y buscable. La UI normal y el palette
  llaman las mismas acciones. Una app con buen command palette ya tiene, sin
  querer, la capa que una IA necesita para controlarla entera.
- **App Intents (Apple) / App Actions (Android):** las apps declaran sus
  capacidades una vez, y cualquier orquestador externo las invoca. La lección:
  declarar capacidades en un manifiesto, no reimplementar por canal.
- **Tools / function-calling / MCP:** las tools del cerebro ya son la superficie
  del lado IA. El objetivo es que cubran TODO lo que la UI puede hacer.
- **Flujo unidireccional / fuente única de verdad** (Riverpod o Bloc, con
  disciplina): toda acción muta un estado central y la UI reacciona. La IA mutando
  estado pasa por el mismo camino que un tap. Nunca hay dos realidades.

## Capas de soporte (no negociables a esta escala)

- **Manifiesto de capacidades** generado desde el registro: la IA siempre conoce su
  superficie completa, y se mantiene solo al agregar acciones.
- **Filtrado de tools por turno:** con control total habrá cientos de acciones;
  mandarlas todas en cada turno funde tokens. Se filtran por contexto.
- **Capa de permisos / gate:** acciones consecuentes con confirmación. Reusar el
  patrón de 3 clases (segura / consecuente / prohibida) ya hecho para teléfono y PC.
- **Idempotencia y audit:** cada acción registrada y repetible sin daño.

## El plan por fases (para que sea TERMINABLE, no un big-bang)

Un refactor de toda la arquitectura, hecho de golpe, es justo lo que se abandona al
80%. Por fases, cada una sólida y validada antes de la siguiente:

- **Fase 0 — Auditoría de gap (solo lectura).** Mapear las acciones de la UI contra
  las tools/endpoints del cerebro. Listar las acciones de UI que la IA hoy NO puede
  hacer. Sin tocar código. Da el mapa exacto de cuánto falta.
- **Fase 1 — Registro de comandos como fuente única.** Establecer el registro
  tipado. Toda acción NUEVA pasa por ahí desde ya.
- **Fase 2 — Migrar la UI al registro, sección por sección** (Inicio, Tareas,
  Calendario, Universidad, Apuntes…), validando cada sección antes de la siguiente.
- **Fase 3 — Proyectar el registro como catálogo de tools de la IA**, con filtrado
  por turno.
- **Fase 4 — Gate de acciones consecuentes** (reusar el patrón existente).

## Cuándo

Después de cerrar 1.0: criterio de "terminada" escrito + 7 días viviéndolo sin
construirle nada encima. Recién entonces, Fase 0.
