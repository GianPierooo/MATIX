-- ============================================================================
-- 0037 · motor de proactividad (Capa 8)
-- ----------------------------------------------------------------------------
-- Matix avisa y propone por iniciativa propia, ANTICIPÁNDOSE: antes de un rato
-- libre, cuando a un proyecto le quedan pocas tareas (repone días antes), al
-- acercarse un plazo, o al detectar un hueco. Corre en el tick del scheduler
-- que ya existe, reusa FCM y el motor de evolución; estas tablas son el estado.
--
-- `config_proactividad` (una fila): el DIAL. `nivel` controla cuán proactivo es
--   (suave | equilibrado | exigente). Arranca EXIGENTE (proactivo y encima),
--   pero con frenos firmes en el código (tope diario, silencio, anti-fatiga).
--   `lead_libre_min`: cuántos minutos antes de un bloque libre avisa.
-- `proactividad_enviados`: dedup por TEMA (`clave`) + base del tope diario y de
--   la adaptación al ritmo (si se ignora, se baja el volumen).
--
-- No destructiva, idempotente.
-- ============================================================================

create table if not exists public.config_proactividad (
  id              uuid        primary key default gen_random_uuid(),
  activo          boolean     not null default true,
  -- Cuán proactivo: suave (poco), equilibrado (medio), exigente (encima, default).
  nivel           text        not null default 'exigente'
                    check (nivel in ('suave', 'equilibrado', 'exigente')),
  -- Minutos de anticipación para el aviso de "pronto tienes un rato libre".
  lead_libre_min  smallint    not null default 30 check (lead_libre_min between 5 and 180),
  actualizado_en  timestamptz not null default now()
);

insert into public.config_proactividad (activo)
select true where not exists (select 1 from public.config_proactividad);

drop trigger if exists trg_config_proactividad_actualizado on public.config_proactividad;
create trigger trg_config_proactividad_actualizado
  before update on public.config_proactividad
  for each row execute function public.tocar_actualizado();

create table if not exists public.proactividad_enviados (
  id        uuid        primary key default gen_random_uuid(),
  -- 'pre_libre' | 'reposicion' | 'deadline' | 'hueco'
  tipo      text        not null,
  -- Clave de dedup por TEMA del día (p. ej. 'deadline:<tarea_id>',
  -- 'reposicion:<proyecto_id>', 'pre_libre:<HH:MM>'): un tema se avisa una vez.
  clave     text        not null,
  fecha     date        not null,
  momento   timestamptz not null default now()
);

create unique index if not exists uq_proactividad_enviados_tema
  on public.proactividad_enviados (clave, fecha);
create index if not exists idx_proactividad_enviados_fecha
  on public.proactividad_enviados (fecha, momento desc);

alter table public.config_proactividad   enable row level security;
alter table public.proactividad_enviados enable row level security;
