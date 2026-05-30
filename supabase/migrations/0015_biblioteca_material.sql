-- ============================================================================
-- 0015 · Biblioteca de material de aprendizaje (Fase 1)
-- ----------------------------------------------------------------------------
-- El "material de aprendizaje" es un store SEPARADO de `apuntes` (el inbox
-- de ideas del usuario). Acá vive el material que los tracks consumen:
-- documentos troceados y embebidos, etiquetados por SKILL (la carpeta,
-- ej. 'calistenia') y BLOQUE (el archivo/etapa, ej. 'bloque_3'). Así un
-- track puede traer "el bloque 3 de calistenia" sin mezclarse con la
-- búsqueda semántica de apuntes.
--
-- Lo prometía el comentario de 0013 (tracks): "Cuando exista la biblioteca
-- (Fase 1), [bloque_actual] enlazará con el material por el tag de bloque".
--
-- Mismo stack RAG que apuntes (0005): pgvector, `text-embedding-3-small`
-- (1536 dims), distancia coseno con índice HNSW.
--
-- Idempotente (if not exists / create or replace): se puede aplicar a mano
-- sobre un proyecto ya existente.
-- ============================================================================

create extension if not exists vector;

create table if not exists public.material_chunks (
  id          uuid         primary key default gen_random_uuid(),
  -- skill = carpeta (ej. 'calistenia'); bloque = archivo/etapa (ej.
  -- 'bloque_3'). Ambos en minúsculas/slug, los pone el ingestor.
  skill       text         not null,
  bloque      text         not null,
  -- nombre del documento original, para citar la fuente.
  fuente      text,
  -- orden del trozo dentro del documento (0, 1, 2…).
  orden       int          not null default 0,
  contenido   text         not null,
  embedding   vector(1536) not null,
  creado_en   timestamptz  not null default now()
);

-- Los tracks filtran por skill y por skill+bloque: índices para ambos.
create index if not exists idx_material_skill
  on public.material_chunks (skill);
create index if not exists idx_material_skill_bloque
  on public.material_chunks (skill, bloque);

-- HNSW para la búsqueda por similitud coseno (igual que apunte_chunks).
create index if not exists idx_material_embedding
  on public.material_chunks
  using hnsw (embedding vector_cosine_ops);

alter table public.material_chunks enable row level security;

-- ============================================================================
-- Búsqueda semántica en la biblioteca, con filtros opcionales por skill y
-- bloque. Mismo patrón que `buscar_apunte_chunks` (RPC vía PostgREST).
--
--   query_embedding · vector(1536) ya embebido en el cerebro.
--   match_count     · top-K.
--   filtro_skill    · si viene, restringe a ese skill.
--   filtro_bloque   · si viene, restringe a ese bloque.
-- ============================================================================
create or replace function public.buscar_material_chunks(
  query_embedding vector(1536),
  match_count     int  default 5,
  filtro_skill    text default null,
  filtro_bloque   text default null
)
returns table (
  skill      text,
  bloque     text,
  fuente     text,
  fragmento  text,
  distancia  float4
)
language sql
stable
as $$
  select
    c.skill,
    c.bloque,
    c.fuente,
    left(c.contenido, 800) as fragmento,
    (c.embedding <=> query_embedding) as distancia
  from public.material_chunks c
  where (filtro_skill is null or c.skill = filtro_skill)
    and (filtro_bloque is null or c.bloque = filtro_bloque)
  order by c.embedding <=> query_embedding
  limit match_count;
$$;
