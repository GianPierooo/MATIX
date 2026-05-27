-- ============================================================================
-- Matix · Capa 1 · Cierre del día (ritual nocturno)
-- ----------------------------------------------------------------------------
-- Una fila por día con las cosas que el usuario sí hizo. El Documento
-- Maestro lo sugiere como "3 cosas", pero modelamos `items text[]`
-- libre (típicamente 3, pero el usuario puede poner menos o más).
--
-- `fecha` es UNIQUE: solo un cierre por día. Re-cerrar el mismo día
-- equivale a editar el cierre existente (UPSERT con `on_conflict`).
--
-- Mismo modelo de seguridad: RLS activa, sin políticas. Solo
-- service_role accede.
-- ============================================================================

create table public.cierres_dia (
  id          uuid        primary key default gen_random_uuid(),
  fecha       date        not null unique,
  items       text[]      not null default '{}',
  nota_extra  text,
  creado_en   timestamptz not null default now()
);

create index idx_cierres_dia_fecha on public.cierres_dia (fecha desc);

alter table public.cierres_dia enable row level security;
