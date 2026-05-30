-- ============================================================================
-- 0017 · recordatorios_enviados · dedupe del scheduler de push (Push Capa 2)
-- ----------------------------------------------------------------------------
-- El cerebro corre un job cada minuto que manda por FCM los recordatorios
-- de eventos y tareas que vencen. Para no mandar el mismo recordatorio dos
-- veces (ticks solapados, catch-up tras un reinicio), registra cada envío
-- acá. La clave (tipo, entidad_id, recordar_en) es el MOMENTO exacto que se
-- notificó: si el usuario cambia la hora del recordatorio, es otra clave y
-- se vuelve a mandar.
--
-- Idempotente (if not exists / drop ... if exists): aplicable a mano.
-- ============================================================================

create table if not exists public.recordatorios_enviados (
  id          uuid        primary key default gen_random_uuid(),
  tipo        text        not null check (tipo in ('tarea', 'evento')),
  entidad_id  uuid        not null,
  -- El instante del recordatorio que se notificó (no cuándo se mandó).
  recordar_en timestamptz not null,
  enviado_en  timestamptz not null default now(),
  unique (tipo, entidad_id, recordar_en)
);

create index if not exists idx_recordatorios_enviados_recordar
  on public.recordatorios_enviados (recordar_en);

alter table public.recordatorios_enviados enable row level security;
