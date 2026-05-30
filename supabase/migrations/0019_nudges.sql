-- ============================================================================
-- 0019 · nudges intensos de tareas por push (Push Capa 3b)
-- ----------------------------------------------------------------------------
-- Los nudges (recordatorios escalados de tareas con plazo) pasan a push del
-- cerebro: el scheduler manda más seguido al acercarse el plazo. Intenso por
-- defecto (se quitó el selector Suave/Normal/Fuerte).
--
-- `config_nudges`: una fila. Maestro on/off, horas de silencio y la
--   disponibilidad por día (espejo de la del planificador, para que el
--   scheduler solo nudgee dentro de esas ventanas). La app la sincroniza.
-- `tareas.nudges_silenciada`: apagado por tarea.
-- `nudges_enviados`: marca cada nudge (tarea, minuto) para no duplicar y para
--   saber cuándo fue el último (rate limit de la curva).
--
-- Idempotente: aplicable a mano.
-- ============================================================================

alter table public.tareas
  add column if not exists nudges_silenciada boolean not null default false;

create table if not exists public.config_nudges (
  id              uuid        primary key default gen_random_uuid(),
  -- Interruptor maestro de TODOS los nudges.
  activo          boolean     not null default true,
  -- Horas de silencio (no se nudgea dentro). Cruza medianoche si inicio>fin.
  silencio_inicio smallint    not null default 22,
  silencio_fin    smallint    not null default 8,
  -- Disponibilidad por día ISO (1=lun..7=dom): {"1":{"activo":true,
  -- "inicio":8,"fin":22}, ...}. Solo se nudgea dentro de la ventana del día.
  disponibilidad  jsonb       not null default
    '{"1":{"activo":true,"inicio":8,"fin":22},
      "2":{"activo":true,"inicio":8,"fin":22},
      "3":{"activo":true,"inicio":8,"fin":22},
      "4":{"activo":true,"inicio":8,"fin":22},
      "5":{"activo":true,"inicio":8,"fin":22},
      "6":{"activo":true,"inicio":8,"fin":22},
      "7":{"activo":true,"inicio":8,"fin":22}}'::jsonb,
  -- Modo de prueba (dev): comprime la curva a minutos para verla sin
  -- esperar horas. Lo activo/desactivo a mano; no va en la UI.
  modo_prueba     boolean     not null default false,
  actualizado_en  timestamptz not null default now()
);

-- Por si la tabla ya existía sin la columna (re-aplicación).
alter table public.config_nudges
  add column if not exists modo_prueba boolean not null default false;

-- Sembramos la única fila de config (si no hay ninguna).
insert into public.config_nudges (activo)
select true
where not exists (select 1 from public.config_nudges);

drop trigger if exists trg_config_nudges_actualizado on public.config_nudges;
create trigger trg_config_nudges_actualizado
  before update on public.config_nudges
  for each row execute function public.tocar_actualizado();

create table if not exists public.nudges_enviados (
  id          uuid        primary key default gen_random_uuid(),
  tarea_id    uuid        not null references public.tareas(id) on delete cascade,
  -- El minuto en que se mandó (truncado). Único por tarea para no duplicar.
  momento     timestamptz not null,
  enviado_en  timestamptz not null default now(),
  unique (tarea_id, momento)
);

create index if not exists idx_nudges_enviados_tarea
  on public.nudges_enviados (tarea_id, momento desc);

alter table public.config_nudges enable row level security;
alter table public.nudges_enviados enable row level security;
