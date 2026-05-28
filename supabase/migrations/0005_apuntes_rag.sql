-- ============================================================================
-- Matix · Capa 3 Paso 1 · RAG sobre apuntes
-- ----------------------------------------------------------------------------
-- Habilita pgvector y agrega la tabla `apunte_chunks` para guardar
-- embeddings. Cada apunte se trocea en uno o más chunks; cada chunk
-- es la unidad de búsqueda semántica.
--
-- Modelo: OpenAI `text-embedding-3-small` (1536 dimensiones).
-- Operador de similitud para HNSW: `vector_cosine_ops` (distancia
-- coseno), que se complementa con el operador `<=>` de pgvector
-- (`a <=> b` = 1 - cosine_similarity, va de 0 idénticos a 2 opuestos).
--
-- Decisiones:
--
-- - Tabla separada `apunte_chunks` en vez de columna `embedding`
--   directa en `apuntes`. Esto permite que un apunte largo se
--   trocee en N chunks (un apunte ≠ una unidad de búsqueda).
--   En Paso 1 indexamos un solo chunk por apunte (título +
--   contenido juntos), pero la forma queda lista para chunking real
--   si en algún momento los apuntes pasan de 8k tokens.
--
-- - FK con `ON DELETE CASCADE`: si purgás un apunte permanente, sus
--   chunks se borran solos.
--
-- - El soft-delete del apunte NO toca los chunks. La búsqueda filtra
--   por `apuntes.eliminado_en IS NULL` en el JOIN. Cuando se restaura
--   un apunte, sus chunks vuelven a aparecer en los resultados sin
--   re-embeber nada.
-- ============================================================================

create extension if not exists vector;

create table public.apunte_chunks (
  id          uuid        primary key default gen_random_uuid(),
  apunte_id   uuid        not null references public.apuntes(id) on delete cascade,
  orden       int         not null default 0,
  contenido   text        not null,
  -- 1536 dims = `text-embedding-3-small` de OpenAI.
  embedding   vector(1536) not null,
  creado_en   timestamptz not null default now()
);

create index idx_apunte_chunks_apunte
  on public.apunte_chunks (apunte_id, orden);

-- Índice HNSW para búsqueda aproximada por similitud coseno.
-- HNSW es más rápido en queries que ivfflat y no necesita training;
-- para la escala del usuario (decenas a unos cientos de apuntes,
-- bajos miles de chunks como máximo) es la elección correcta.
create index idx_apunte_chunks_embedding
  on public.apunte_chunks
  using hnsw (embedding vector_cosine_ops);

alter table public.apunte_chunks enable row level security;

-- ============================================================================
-- Función de búsqueda semántica
-- ----------------------------------------------------------------------------
-- PostgREST no expone el operador `<=>` directamente en queries
-- arbitrarios. La forma estándar de hacer similarity search vía
-- el REST de Supabase es declarar una función SQL y llamarla con
-- `POST /rpc/buscar_apunte_chunks`.
--
-- Argumentos:
--   query_embedding · vector(1536) ya embebido del lado del cerebro.
--   match_count     · cuántos resultados devolver (top-K).
--
-- Devuelve, por cada match, el id del apunte, su título, el
-- fragmento (contenido del chunk recortado), y la distancia coseno
-- (0 = idéntico, 2 = opuesto). FILTRA los apuntes en la papelera
-- — Matix nunca debe ver lo que el usuario borró.
-- ============================================================================
create or replace function public.buscar_apunte_chunks(
  query_embedding vector(1536),
  match_count     int default 5
)
returns table (
  apunte_id    uuid,
  titulo       text,
  fragmento    text,
  distancia    float4
)
language sql
stable
as $$
  select
    a.id as apunte_id,
    a.titulo,
    -- Recortamos el fragmento para no devolver apuntes enteros por
    -- la red. 600 caracteres suelen mostrar el "por qué del match".
    left(c.contenido, 600) as fragmento,
    (c.embedding <=> query_embedding) as distancia
  from public.apunte_chunks c
  join public.apuntes a on a.id = c.apunte_id
  where a.eliminado_en is null
  order by c.embedding <=> query_embedding
  limit match_count;
$$;
