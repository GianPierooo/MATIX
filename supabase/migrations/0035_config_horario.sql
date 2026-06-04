-- ============================================================================
-- 0035 · config_horario · anclas y límites del día para el planificador de horario
-- ----------------------------------------------------------------------------
-- La capa de horario coloca el set del día en las ventanas libres reales. Para
-- eso necesita los LÍMITES (despertar/dormir), el BLOQUE PICO (trabajo profundo
-- en la mañana), los BUFFERS entre bloques, las duraciones por tipo de bloque, y
-- las ANCLAS fijas diarias (p. ej. calistenia en la mañana).
--
-- Reusa lo que ya existe (no duplica): las clases viven en `sesiones_clase`, el
-- gym y demás recurrentes en `eventos` (con su recurrencia), y el silencio en
-- `config_nudges`. Acá SOLO van las anclas/parametría del horario, editables.
--
-- Singleton (una fila). No destructiva, idempotente: crea si no existe y siembra
-- una fila con defaults sensatos si está vacía.
-- ============================================================================

create table if not exists public.config_horario (
  id               uuid        primary key default gen_random_uuid(),
  hora_despertar   smallint    not null default 7  check (hora_despertar between 0 and 23),
  -- "dormir antes de las 12": no se agenda nada después de esta hora.
  hora_dormir      smallint    not null default 23 check (hora_dormir between 1 and 24),
  -- Bloque pico (trabajo profundo): lo más importante/difícil va aquí.
  pico_inicio      smallint    not null default 6  check (pico_inicio between 0 and 23),
  pico_fin         smallint    not null default 9  check (pico_fin between 1 and 24),
  -- Colchón corto alrededor de lo fijo y entre bloques (minutos).
  buffer_min       smallint    not null default 10 check (buffer_min between 0 and 60),
  -- Duraciones por tipo de bloque (minutos).
  dur_trabajo_min  smallint    not null default 90 check (dur_trabajo_min between 15 and 240),
  dur_skill_min    smallint    not null default 30 check (dur_skill_min between 10 and 120),
  dur_tarea_min    smallint    not null default 20 check (dur_tarea_min between 10 and 120),
  -- Anclas fijas diarias, editables: [{titulo, inicio "HH:MM", fin "HH:MM", dias [ISO 1..7]}].
  anclas           jsonb       not null default
    '[{"titulo":"Calistenia","inicio":"07:00","fin":"07:45","dias":[1,2,3,4,5,6,7]}]'::jsonb,
  actualizado_en   timestamptz not null default now()
);

-- Siembra una fila por defecto si la tabla está vacía (idempotente).
insert into public.config_horario (id)
  select gen_random_uuid()
  where not exists (select 1 from public.config_horario);

alter table public.config_horario enable row level security;
