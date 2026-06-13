-- ============================================================================
-- Matix · Capa 3 (memoria) · RAG UNIFICADO de la vida del usuario
-- ----------------------------------------------------------------------------
-- Hasta hoy el recall era TODO por herramienta (el modelo decidía llamar
-- buscar_apuntes / buscar_memoria / buscar_en_historial) → a menudo NO lo hacía
-- y Matix "no recordaba la vida" del usuario. Además tareas, proyectos y
-- universidad no tenían NINGÚN embedding.
--
-- `recuerdos` es la tienda semántica UNIFICADA que el chat recupera SOLO
-- (auto, cada turno) e inyecta como contexto. Indexa los datos núcleo del hub:
--   tarea · nota · proyecto · universidad   (chat sigue en memoria_conversacional).
--
-- Mismo stack que el resto del RAG (0005/0015/0022/0028):
--   OpenAI text-embedding-3-small (1536 dims), distancia coseno `<=>`, HNSW.
--
-- Decisiones:
-- - UNA fila por entidad (unique(fuente_tipo, fuente_id)) → re-indexar es un
--   UPSERT, no acumula chunks. Las entidades del hub son cortas (título, meta,
--   nota): un solo "chunk" por entidad alcanza.
-- - `contenido_hash` permite SALTAR el embedding si el texto no cambió
--   (incremental real, sin re-embeber cada edición).
-- - `embedding` NULLABLE: la ingesta es best-effort (si OpenAI no responde, la
--   fila se guarda igual y solo no participa de la búsqueda hasta re-indexar).
-- - `fecha` = la fecha relevante del recuerdo (vence_en de la tarea, inicia_en
--   del evento, actualizado del proyecto…) para poder ordenar/mostrar por tiempo.
-- - `metadata` jsonb: subtipo y campos útiles (estado, prioridad, curso…) sin
--   inflar columnas.
-- - RLS habilitado SIN políticas → solo el service role (el cerebro) accede.
-- ============================================================================

create extension if not exists vector;

create table if not exists public.recuerdos (
  id              uuid        primary key default gen_random_uuid(),
  fuente_tipo     text        not null,   -- tarea | nota | proyecto | universidad | chat
  fuente_id       text        not null,   -- id de la entidad (uuid en texto)
  contenido       text        not null,
  contenido_hash  text        not null,   -- sha256 del contenido (skip re-embed)
  embedding       vector(1536),           -- nullable: best-effort
  fecha           timestamptz not null default now(),
  metadata        jsonb       not null default '{}'::jsonb,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  unique (fuente_tipo, fuente_id)
);

create index if not exists idx_recuerdos_fuente
  on public.recuerdos (fuente_tipo, fuente_id);

-- HNSW para similitud coseno (parcial: solo filas con embedding).
create index if not exists idx_recuerdos_embedding
  on public.recuerdos
  using hnsw (embedding vector_cosine_ops)
  where embedding is not null;

alter table public.recuerdos enable row level security;

-- actualizado_en se refresca en cada update.
create or replace function public.trg_recuerdos_touch()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

drop trigger if exists trg_recuerdos_touch on public.recuerdos;
create trigger trg_recuerdos_touch
  before update on public.recuerdos
  for each row execute function public.trg_recuerdos_touch();

-- ============================================================================
-- Búsqueda semántica unificada
-- ----------------------------------------------------------------------------
-- El cerebro embebe el mensaje del usuario y llama por RPC. `tipos` opcional
-- filtra por fuente (p.ej. solo 'proyecto'). Devuelve los más cercanos por
-- distancia coseno (0 = idéntico, 2 = opuesto); un match razonable suele estar
-- por debajo de ~0.6.
-- ============================================================================
create or replace function public.buscar_recuerdos(
  query_embedding vector(1536),
  match_count     int default 8,
  tipos           text[] default null
)
returns table (
  fuente_tipo  text,
  fuente_id    text,
  contenido    text,
  fecha        timestamptz,
  metadata     jsonb,
  distancia    float4
)
language sql
stable
as $$
  select
    r.fuente_tipo,
    r.fuente_id,
    left(r.contenido, 700) as contenido,
    r.fecha,
    r.metadata,
    (r.embedding <=> query_embedding) as distancia
  from public.recuerdos r
  where r.embedding is not null
    and (tipos is null or r.fuente_tipo = any(tipos))
  order by r.embedding <=> query_embedding
  limit match_count;
$$;
