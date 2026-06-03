-- 0027_automatizaciones.sql
-- Automatizaciones que el usuario define por chat/voz (proactividad · v1).
-- El usuario las crea con la tool crear_automatizacion; el scheduler del cerebro
-- (el mismo de rituales/recordatorios) las dispara a su hora (America/Lima) y
-- empuja por FCM.
--
-- Motor de cadencia: `proxima_ejecucion` guarda la próxima vez (UTC) que toca.
-- El tick dispara las vencidas y AVANZA proxima_ejecucion a la siguiente
-- ocurrencia → nunca se dispara dos veces en el mismo período (sin tabla de
-- dedup aparte).

create table if not exists automatizaciones (
    id uuid primary key default gen_random_uuid(),
    -- Resumen corto de qué hace (para listarla).
    descripcion text not null,
    -- 'diaria' (a una hora) | 'semanal' (un día ISO + hora). v1: nada de cron crudo.
    recurrencia text not null check (recurrencia in ('diaria', 'semanal')),
    hora smallint not null check (hora between 0 and 23),
    minuto smallint not null default 0 check (minuto between 0 and 59),
    -- ISO 1=lunes … 7=domingo. Solo para 'semanal'; null en 'diaria'.
    dia_semana smallint check (dia_semana between 1 and 7),
    -- 'recordatorio' (empuja un texto) | 'accion_ia' (corre un prompt y empuja el resultado).
    tipo text not null check (tipo in ('recordatorio', 'accion_ia')),
    -- recordatorio: el texto a empujar. accion_ia: el prompt a ejecutar.
    accion text not null,
    activa boolean not null default true,
    -- Próxima vez (UTC) que el scheduler la dispara. La fija/avanza el cerebro.
    proxima_ejecucion timestamptz,
    creada_en timestamptz not null default now()
);

-- El scheduler lee las activas ordenadas por su próxima ejecución.
create index if not exists idx_automatizaciones_activa_prox
    on automatizaciones (activa, proxima_ejecucion);
