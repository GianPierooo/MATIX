-- ============================================================================
-- Matix · Ancla de despertar POR DÍA (botón "Me acabo de levantar")
-- ----------------------------------------------------------------------------
-- El botón registra a qué hora despertó el usuario HOY, sin tocar su rutina
-- estándar (config_horario.hora_despertar sigue siendo, p. ej., 7:00). El plan
-- del día (ventanas, franja mañana/tarde) se calcula desde esta hora SOLO para
-- la fecha registrada; mañana vuelve la rutina normal.
--
-- `minutos` = minutos desde medianoche (hora Lima) en que despertó.
-- Una fila por fecha (upsert por `fecha`).
--
-- Solo aditiva (no destructiva).
-- ============================================================================

create table if not exists public.despertar_dia (
    fecha       date primary key,
    minutos     smallint not null check (minutos between 0 and 1439),
    creado_en   timestamptz not null default now()
);
