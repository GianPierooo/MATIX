-- ============================================================================
-- Matix · Capa 1 · Sección Proyectos
-- ----------------------------------------------------------------------------
-- Suma la tabla `proyectos` (los 3 proyectos activos del usuario, los
-- aparcados y los terminados) y la conecta con `tareas`, `apuntes` y
-- `eventos` mediante una FK opcional `proyecto_id`.
--
-- El tope de 3 proyectos activos NO se aplica aquí: lo valida el cerebro
-- (FastAPI). Razón: queremos un mensaje de error legible para el usuario
-- ("Ya tienes 3 activos: aparca o termina uno primero") y que la regla
-- viva donde se gestionan los cambios de estado.
--
-- Mismo modelo de seguridad que 0001: RLS activa, sin políticas. Solo
-- service_role accede.
-- ============================================================================

-- ============================================================================
-- 11. proyectos · contenedores vitales del usuario
-- ============================================================================
create table public.proyectos (
  id                    uuid        primary key default gen_random_uuid(),
  nombre                text        not null,
  descripcion           text,
  estado                text        not null default 'activo'
                        check (estado in ('activo', 'aparcado', 'terminado')),
  prioridad             smallint,                  -- ranking entre los activos (1/2/3); el cerebro lo gobierna
  linea_meta            text,                      -- definición de "terminado" del proyecto
  tarea_siguiente_id    uuid        references public.tareas(id) on delete set null,
  ultima_actividad_en   timestamptz not null default now(),
  bloque_protegido      jsonb,                     -- ej. {"dias_semana":[0,2,4],"hora_inicio":"06:00","hora_fin":"09:00"}
  color                 text,                      -- hex '#RRGGBB'
  inactivo_desde        timestamptz,               -- cuándo dejó de estar activo (al aparcar o al terminar)
  creado_en             timestamptz not null default now(),
  actualizado_en        timestamptz not null default now()
);

create index idx_proyectos_estado          on public.proyectos (estado);
create index idx_proyectos_tarea_siguiente on public.proyectos (tarea_siguiente_id);

create trigger trg_proyectos_actualizado
  before update on public.proyectos
  for each row execute function public.tocar_actualizado();

-- ============================================================================
-- Conexiones: tareas, apuntes y eventos pueden colgar de un proyecto.
-- `proyecto_id` es opcional (nullable) y se pone a NULL si el proyecto se
-- borra, para no perder la tarea/apunte/evento.
-- ============================================================================
alter table public.tareas
  add column proyecto_id uuid references public.proyectos(id) on delete set null;

create index idx_tareas_proyecto on public.tareas (proyecto_id);

alter table public.apuntes
  add column proyecto_id uuid references public.proyectos(id) on delete set null;

create index idx_apuntes_proyecto on public.apuntes (proyecto_id);

alter table public.eventos
  add column proyecto_id uuid references public.proyectos(id) on delete set null;

create index idx_eventos_proyecto on public.eventos (proyecto_id);

-- ============================================================================
-- Seguridad: RLS activada en `proyectos`, sin políticas. Las tablas
-- `tareas`, `apuntes` y `eventos` ya tienen RLS activo desde 0001.
-- ============================================================================
alter table public.proyectos enable row level security;
