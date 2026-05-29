-- ============================================================================
-- Matix · Fase 2 · Tracks de aprendizaje
-- ----------------------------------------------------------------------------
-- Cada skill que el usuario aprende de forma CONTINUA (inglés, calistenia,
-- guitarra…) es un "track": tiene una posición (en qué bloque va) y un
-- estado (activo / en pausa). NO son proyectos — los proyectos se terminan
-- y van topados; los tracks no se terminan, solo se pausan.
--
-- Tope de 3 ACTIVOS: igual que los proyectos, la regla la valida el cerebro
-- (FastAPI), no la BD, para dar un mensaje legible ("Ya tienes 3 tracks
-- activos: pausa uno primero").
--
--   nombre         el skill (ej. "Calistenia").
--   descripcion    descripción corta.
--   estado         'activo' | 'pausado'.
--   bloque_actual  posición: en qué bloque/etapa va (texto libre, ej.
--                  "Bloque 3"). Cuando exista la biblioteca (Fase 1), este
--                  texto enlazará con el material por el tag de bloque.
--   semana / dia   posición fina opcional dentro del bloque.
--
-- Mismo modelo de seguridad que el resto: RLS activa, sin políticas; solo
-- el service_role accede.
-- ============================================================================

create table public.tracks (
  id              uuid        primary key default gen_random_uuid(),
  nombre          text        not null,
  descripcion     text,
  estado          text        not null default 'activo'
                  check (estado in ('activo', 'pausado')),
  bloque_actual   text,
  semana          smallint,
  dia             smallint,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create index idx_tracks_estado on public.tracks (estado);

create trigger trg_tracks_actualizado
  before update on public.tracks
  for each row execute function public.tocar_actualizado();

alter table public.tracks enable row level security;
