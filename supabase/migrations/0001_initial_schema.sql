-- ============================================================================
-- Matix · Capa 1 · Esquema inicial del hub
-- ----------------------------------------------------------------------------
-- Crea las 10 tablas que sostienen el armazón del hub.
--
-- Modelo de seguridad: la app móvil habla con el cerebro (FastAPI) y el
-- cerebro habla con Supabase usando service_role. Por eso activamos RLS
-- en todas las tablas y NO creamos políticas: ningún cliente
-- anon/authenticated puede acceder; solo service_role pasa (y service_role
-- omite RLS por definición).
-- ============================================================================

create extension if not exists "pgcrypto";  -- para gen_random_uuid()

-- ----------------------------------------------------------------------------
-- Función reutilizable: refresca `actualizado_en` (o `actualizada_en`) en
-- cada UPDATE. Dinámica para servir a ambos géneros del nombre.
-- ----------------------------------------------------------------------------
create or replace function public.tocar_actualizado()
returns trigger
language plpgsql
as $$
begin
  if to_jsonb(new) ? 'actualizado_en' then
    new.actualizado_en := now();
  elsif to_jsonb(new) ? 'actualizada_en' then
    new.actualizada_en := now();
  end if;
  return new;
end;
$$;

-- ============================================================================
-- 1. profile · perfil único del usuario
-- ============================================================================
create table public.profile (
  id              uuid        primary key default gen_random_uuid(),
  nombre          text,
  zona_horaria    text        not null default 'America/Lima',
  tema            text        not null default 'system'
                  check (tema in ('light', 'dark', 'system')),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create trigger trg_profile_actualizado
  before update on public.profile
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- 2. categorias · clasificación libre de tareas
-- ============================================================================
create table public.categorias (
  id          uuid        primary key default gen_random_uuid(),
  nombre      text        not null unique,
  color       text,                       -- hex '#RRGGBB'
  icono       text,                       -- nombre de icono Flutter Material
  creado_en   timestamptz not null default now()
);

-- ============================================================================
-- 3. cursos · materias de la universidad
-- ============================================================================
create table public.cursos (
  id              uuid        primary key default gen_random_uuid(),
  nombre          text        not null,
  profesor        text,
  color           text,                   -- hex '#RRGGBB'
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create trigger trg_cursos_actualizado
  before update on public.cursos
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- 4. sesiones_clase · horario recurrente del curso (lun 08:00–10:00…)
-- ============================================================================
create table public.sesiones_clase (
  id          uuid        primary key default gen_random_uuid(),
  curso_id    uuid        not null references public.cursos(id) on delete cascade,
  dia_semana  smallint    not null check (dia_semana between 0 and 6),  -- 0=lun … 6=dom
  hora_inicio time        not null,
  hora_fin    time        not null,
  ubicacion   text,
  check (hora_fin > hora_inicio)
);

create index idx_sesiones_clase_curso on public.sesiones_clase (curso_id);

-- ============================================================================
-- 5. tareas · pendientes del usuario
-- ============================================================================
create table public.tareas (
  id              uuid        primary key default gen_random_uuid(),
  titulo          text        not null,
  nota            text,
  vence_en        timestamptz,
  prioridad       text        not null default 'media'
                  check (prioridad in ('alta', 'media', 'baja')),
  categoria_id    uuid        references public.categorias(id) on delete set null,
  curso_id        uuid        references public.cursos(id)     on delete set null,
  repeticion      text        check (repeticion in ('diaria', 'semanal', 'mensual', 'anual')),
  recordar_en     timestamptz,                                -- cuándo notificar
  completada      boolean     not null default false,
  completada_en   timestamptz,
  creada_en       timestamptz not null default now(),
  actualizada_en  timestamptz not null default now()
);

create index idx_tareas_vence_en   on public.tareas (vence_en);
create index idx_tareas_completada on public.tareas (completada);
create index idx_tareas_curso      on public.tareas (curso_id);
create index idx_tareas_categoria  on public.tareas (categoria_id);

create trigger trg_tareas_actualizado
  before update on public.tareas
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- 6. subtareas · pasos dentro de una tarea
-- ============================================================================
create table public.subtareas (
  id          uuid        primary key default gen_random_uuid(),
  tarea_id    uuid        not null references public.tareas(id) on delete cascade,
  titulo      text        not null,
  completada  boolean     not null default false,
  orden       int         not null default 0,
  creada_en   timestamptz not null default now()
);

create index idx_subtareas_tarea on public.subtareas (tarea_id, orden);

-- ============================================================================
-- 7. evaluaciones · entregas, exámenes, proyectos y su calificación
-- ============================================================================
create table public.evaluaciones (
  id              uuid          primary key default gen_random_uuid(),
  curso_id        uuid          not null references public.cursos(id) on delete cascade,
  titulo          text          not null,
  tipo            text          not null
                  check (tipo in ('entrega', 'examen', 'proyecto', 'otro')),
  fecha           timestamptz   not null,
  descripcion     text,                                       -- texto libre
  peso            numeric(5,2),                               -- % del curso
  nota_obtenida   numeric(5,2),                               -- la calificación
  nota_maxima     numeric(5,2)  default 20,                   -- escala (PE: 0–20)
  recordar_en     timestamptz,
  creada_en       timestamptz   not null default now(),
  actualizada_en  timestamptz   not null default now()
);

create index idx_evaluaciones_curso on public.evaluaciones (curso_id);
create index idx_evaluaciones_fecha on public.evaluaciones (fecha);

create trigger trg_evaluaciones_actualizado
  before update on public.evaluaciones
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- 8. eventos · calendario personal
-- ============================================================================
create table public.eventos (
  id              uuid        primary key default gen_random_uuid(),
  titulo          text        not null,
  descripcion     text,
  inicia_en       timestamptz not null,
  termina_en      timestamptz,
  todo_el_dia     boolean     not null default false,
  ubicacion       text,
  curso_id        uuid        references public.cursos(id) on delete set null,
  color           text,
  recordar_en     timestamptz,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  check (termina_en is null or termina_en >= inicia_en)
);

create index idx_eventos_inicia_en on public.eventos (inicia_en);
create index idx_eventos_curso     on public.eventos (curso_id);

create trigger trg_eventos_actualizado
  before update on public.eventos
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- 9. cuadernos · agrupadores de apuntes
-- ============================================================================
create table public.cuadernos (
  id          uuid        primary key default gen_random_uuid(),
  nombre      text        not null,
  color       text,
  curso_id    uuid        references public.cursos(id) on delete set null,
  creado_en   timestamptz not null default now()
);

create index idx_cuadernos_curso on public.cuadernos (curso_id);

-- ============================================================================
-- 10. apuntes · notas del usuario
-- ============================================================================
create table public.apuntes (
  id              uuid        primary key default gen_random_uuid(),
  titulo          text        not null,
  contenido       text        not null default '',
  cuaderno_id     uuid        references public.cuadernos(id) on delete set null,
  curso_id        uuid        references public.cursos(id)    on delete set null,
  etiquetas       text[]      not null default '{}',
  adjuntos        jsonb       not null default '[]'::jsonb,   -- [{url, tipo, nombre}, …]
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create index idx_apuntes_cuaderno  on public.apuntes (cuaderno_id);
create index idx_apuntes_curso     on public.apuntes (curso_id);
create index idx_apuntes_etiquetas on public.apuntes using gin (etiquetas);

create trigger trg_apuntes_actualizado
  before update on public.apuntes
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- Seguridad: RLS activada en todas las tablas, sin políticas.
-- Solo service_role (el cerebro) puede leer/escribir.
-- ============================================================================
alter table public.profile        enable row level security;
alter table public.categorias     enable row level security;
alter table public.cursos         enable row level security;
alter table public.sesiones_clase enable row level security;
alter table public.tareas         enable row level security;
alter table public.subtareas      enable row level security;
alter table public.evaluaciones   enable row level security;
alter table public.eventos        enable row level security;
alter table public.cuadernos      enable row level security;
alter table public.apuntes        enable row level security;
