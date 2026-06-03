-- ============================================================================
-- 0031 · planificador diario + motor de nudge (perfil profundo · Paso 3)
-- ----------------------------------------------------------------------------
-- Lee los árboles (0030) de los proyectos activos y cada día propone un SET
-- chico y finible de subtareas. El usuario acepta/edita/salta; las aceptadas se
-- promueven a Tareas reales del día. Luego el motor INSISTE sobre el set
-- aceptado-no-cerrado (exigente pero sano), con anti-fatiga, y cierra el día
-- celebrando + empujando a dormir a horario.
--
-- Reusa el scheduler y FCM existentes; estas tablas son el estado.
--
-- `config_planificacion` (una fila): parámetros ajustables (tamaño del set,
--   intensidad, hora de la propuesta, hora del nudge de dormir).
-- `set_diario_items`: el set del día. estado propuesto→aceptado/saltado→hecho.
--   `tarea_id` enlaza la subtarea aceptada con su Tarea del hub (y, vía 0030,
--   con el nodo del árbol).
-- `planificacion_enviados`: dedupe + rate-limit de los pushes de planificación
--   (propuesta/escalacion/cierre/dormir) y base del anti-fatiga.
--
-- No destructiva, idempotente.
-- ============================================================================

create table if not exists public.config_planificacion (
  id                 uuid        primary key default gen_random_uuid(),
  activo             boolean     not null default true,
  -- Cuántas subtareas propone el set del día (ambicioso pero finible).
  tamano_set         smallint    not null default 3,
  -- Intensidad de la insistencia sobre el set: alta | media | baja.
  intensidad         text        not null default 'alta'
                       check (intensidad in ('alta', 'media', 'baja')),
  -- Hora (Lima) de la propuesta del día (el usuario se levanta 7am).
  hora_propuesta     smallint    not null default 7 check (hora_propuesta between 0 and 23),
  -- Hora (Lima) del nudge de dormir (meta: dormir antes de las 12).
  hora_nudge_dormir  smallint    not null default 23 check (hora_nudge_dormir between 0 and 23),
  actualizado_en     timestamptz not null default now()
);

insert into public.config_planificacion (activo)
select true where not exists (select 1 from public.config_planificacion);

drop trigger if exists trg_config_planificacion_actualizado on public.config_planificacion;
create trigger trg_config_planificacion_actualizado
  before update on public.config_planificacion
  for each row execute function public.tocar_actualizado();

create table if not exists public.set_diario_items (
  id            uuid        primary key default gen_random_uuid(),
  fecha         date        not null,
  proyecto_id   uuid        references public.proyectos(id) on delete cascade,
  nodo_id       uuid        references public.arbol_nodos(id) on delete set null,
  titulo        text        not null,
  estado        text        not null default 'propuesto'
                  check (estado in ('propuesto', 'aceptado', 'saltado', 'hecho')),
  tarea_id      uuid        references public.tareas(id) on delete set null,
  orden         int         not null default 0,
  creado_en     timestamptz not null default now()
);

create index if not exists idx_set_diario_items_fecha
  on public.set_diario_items (fecha, estado);
create index if not exists idx_set_diario_items_tarea
  on public.set_diario_items (tarea_id) where tarea_id is not null;

create table if not exists public.planificacion_enviados (
  id          uuid        primary key default gen_random_uuid(),
  -- 'propuesta' | 'escalacion' | 'cierre' | 'dormir'
  tipo        text        not null,
  fecha       date        not null,
  momento     timestamptz not null default now()
);

create index if not exists idx_planificacion_enviados
  on public.planificacion_enviados (tipo, fecha, momento desc);

alter table public.config_planificacion   enable row level security;
alter table public.set_diario_items        enable row level security;
alter table public.planificacion_enviados  enable row level security;
