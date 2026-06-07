# Rendición de cuentas — push con botones de acción

Notificaciones push **del sistema** que, cuando hay tareas sin completar,
empujan un aviso con **3 botones** (Sí lo hice / Más tarde hoy / Mañana) que
funcionan **con la app cerrada**, sin abrir la UI.

## Cómo se compone una notificación

- **Contenido determinista** (cero LLM, cero tokens): plantilla con datos
  inyectados (`cerebro/app/matix/rendicion_cuentas.py:armar_contenido`).
- **Tono escalado por nivel** (1 suave / 2 firme / 3 final). Tope en 3.
- **Botón "Más tarde hoy" SOLO si hay ventana útil real** antes de tu ancla de
  dormir (reusa `horario.ventanas_libres` con `buffer_pre_sueno_min`).

## Cuándo dispara

- **Cierre del día** (ritual): tras el push del cierre, una primera ronda nivel 1.
- **Chequeo periódico** (scheduler cada minuto): respeta `permitido_ahora`
  (silencio nocturno + disponibilidad del día).
- **Dedup**: una tarea no se vuelve a pingar dentro de su nivel actual ni antes
  de 20h tras el último ping. Una tarea **resuelta** (botón tocado) queda en
  silencio definitivo.

## Cómo funcionan los botones con la app cerrada

1. El cerebro manda un FCM con `data.tipo = "rendicion_cuentas"` + el bloque
   `notification` como fallback.
2. La app, en su **background handler de FCM** (`push_service.dart:
   manejarPushEnBackground`), repinta la notificación con
   `flutter_local_notifications` y los `actions` (3 botones).
3. Cuando el usuario toca un botón:
   - `flutter_local_notifications` dispara
     `manejarTapNotificacionEnBackground` (top-level con
     `@pragma('vm:entry-point')`).
   - El handler llama `POST /api/v1/push/rendicion-cuentas/accion` con
     `{tarea_id, accion}`.
   - El cerebro aplica:
     - `hecho` → marca la tarea completada.
     - `manana` → `rollover.aplicar_rollover(decision="otro_dia")`.
     - `mas_tarde` → mueve el bloque al próximo hueco real de HOY antes del
       ancla de dormir. Si ya no hay ventana, responde `tipo=sin_ventana`.
   - La notificación se cierra (`cancelNotification: true`). No abre la UI.

## MagicOS / Honor — límites honestos

Honor (MagicOS), Huawei (EMUI), Xiaomi (MIUI) y otros OEM chinos matan apps de
fondo agresivamente. Eso afecta:

- La **entrega de FCM**: aunque Google se las arregla para hacerlo prioritario,
  el SO puede retrasar minutos u horas si la app está "optimizada".
- El **handler de tap de los botones**: cuando el SO ha matado el isolate, el
  tap puede no disparar el HTTP — el botón se queda en `cancelNotification: true`
  pero la acción no se aplica.

Mitigación implementada:
- **Exención de optimización de batería**: en `Ajustes → Notificaciones →
  Entrega en background`. Detecta el estado y guía al usuario a concederla. Si
  el OEM bloquea el diálogo directo, abre Ajustes de la app como fallback.
- **`priority: high`** en FCM (ya está) — el push entra como heads-up,
  saltándose la cola lenta.
- **Tick periódico cada minuto**: si un push se cae, el siguiente lo recoge.

Lo que **NO** podemos garantizar:
- Que MagicOS no mate Matix después de horas sin uso. Si el usuario quiere
  máxima confiabilidad: además de la exención de batería, en MagicOS conviene
  ir a `Ajustes del teléfono → Aplicaciones → Matix → Inicio de aplicaciones`
  y poner **"Gestionar manualmente"** con los tres switches encendidos
  (inicio automático, inicio secundario, ejecución en segundo plano). Es
  específico del OEM y no se puede automatizar desde la app.

## Tablas y endpoints

- **Tabla `pings_rendicion_cuentas`** (migración `0041`):
  `tarea_id`, `nivel` (1-3), `enviado_en`, `resuelta_en` (nullable), `accion`.
- **Endpoint `POST /api/v1/push/rendicion-cuentas/accion`**:
  body `{tarea_id, accion}`, accion ∈ {`hecho`, `manana`, `mas_tarde`}.

## Cobertura de tests

- **cerebro** (`tests/test_rendicion_cuentas.py`, 18 tests): contenido
  determinista (singular/plural/truncado/tono por nivel), ventana útil
  (queda tiempo / ya es tarde / ancla temprana), escalada con tope (cooldown,
  niveles, dedup), próximo slot real.
- **app** (`tests/features/push/rendicion_cuentas_background_test.dart`, 5
  tests): handler de background traga errores y timeouts sin crashear; POSTea
  las 3 acciones con el body correcto.
- **Lo que solo el device puede validar**: que el push llegue con MagicOS
  matando la app, que los `actions` se rendericen con la app cerrada, y que
  el handler de tap dispare en isolate frío. El gate del CI no lo cubre.
