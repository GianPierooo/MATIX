-- ============================================================================
-- 0022 · memoria personal de Matix
-- ----------------------------------------------------------------------------
-- Almacén persistente de lo que Matix sabe del usuario: hechos duraderos
-- (quién es, sus metas, personas importantes, su situación, preferencias,
-- contexto de proyectos). Matix inyecta lo ESENCIAL siempre en su contexto y
-- recupera lo extenso por RAG (similitud semántica) cuando hace falta.
--
-- `memoria`:
--   - `contenido`  · el hecho, en una o pocas frases.
--   - `categoria`  · libre (quien_soy, metas, personas, situacion,
--                    preferencias, proyectos…). Solo para organizar la UI.
--   - `esencial`   · true = va SIEMPRE en el bloque inyectado ("lo que sé de
--                    ti"); false = solo se recupera por RAG si es relevante.
--   - `embedding`  · vector(1536) (text-embedding-3-small). Nullable y
--                    best-effort: si el embed falla, el hecho igual se guarda
--                    y se inyecta/lista; solo no aparece en la búsqueda RAG.
--
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

create extension if not exists vector;

create table if not exists public.memoria (
  id              uuid          primary key default gen_random_uuid(),
  contenido       text          not null,
  categoria       text,
  esencial        boolean       not null default true,
  embedding       vector(1536),
  creado_en       timestamptz   not null default now(),
  actualizado_en  timestamptz   not null default now()
);

create index if not exists idx_memoria_esencial on public.memoria (esencial);

-- HNSW para la búsqueda por similitud coseno. Parcial: solo las filas con
-- embedding (las que fallaron el embed quedan fuera del índice, sin romper).
create index if not exists idx_memoria_embedding
  on public.memoria using hnsw (embedding vector_cosine_ops)
  where embedding is not null;

drop trigger if exists trg_memoria_actualizado on public.memoria;
create trigger trg_memoria_actualizado
  before update on public.memoria
  for each row execute function public.tocar_actualizado();

alter table public.memoria enable row level security;

-- ============================================================================
-- Búsqueda semántica de memoria (RAG)
-- ----------------------------------------------------------------------------
-- Igual que `buscar_apunte_chunks`: el cerebro embebe la consulta y llama a
-- esta función vía `POST /rpc/buscar_memoria`. Devuelve los hechos más
-- relevantes por distancia coseno (0 = idéntico, 2 = opuesto).
-- ============================================================================
create or replace function public.buscar_memoria(
  query_embedding vector(1536),
  match_count     int default 5
)
returns table (
  id         uuid,
  contenido  text,
  categoria  text,
  distancia  float4
)
language sql
stable
as $$
  select
    m.id,
    m.contenido,
    m.categoria,
    (m.embedding <=> query_embedding) as distancia
  from public.memoria m
  where m.embedding is not null
  order by m.embedding <=> query_embedding
  limit match_count;
$$;
