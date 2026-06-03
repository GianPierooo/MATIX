-- ============================================================================
-- 0028 · memoria conversacional · recall semántico sobre el historial de chat
-- ----------------------------------------------------------------------------
-- Hasta ahora las conversaciones con Matix NO se persistían (vivían en RAM en
-- la app y se perdían al cerrar). Esta migración agrega:
--
--   1. `conversaciones`        · agrupa mensajes en una "sesión". El cerebro
--      abre una nueva tras un lapso de inactividad (single-user: la sesión se
--      maneja por tiempo, sin que la app mande un id).
--   2. `mensajes_chat`         · los mensajes reales (rol + contenido + fecha).
--      Fuente de verdad del historial; permite re-chunkear/backfill.
--   3. `memoria_conversacional`· TIENDA VECTORIAL SEPARADA (no es la memoria
--      personal de 0022 ni la biblioteca de material de 0015). Guarda chunks
--      del historial (un intercambio o ventana) con su embedding y su fecha,
--      para buscar semánticamente "qué hablamos la otra vez".
--
-- Modelo de embeddings: el MISMO que el resto del RAG, `text-embedding-3-small`
-- (1536 dims), para que query y chunk vivan en el mismo espacio.
--
-- No destructiva, idempotente (todo `if not exists`).
-- ============================================================================

create extension if not exists vector;

-- 1) Conversaciones (sesiones por inactividad) ------------------------------
create table if not exists public.conversaciones (
  id                 uuid          primary key default gen_random_uuid(),
  iniciada_en        timestamptz   not null default now(),
  ultimo_mensaje_en  timestamptz   not null default now()
);

create index if not exists idx_conversaciones_ultimo
  on public.conversaciones (ultimo_mensaje_en desc);

-- 2) Mensajes reales del chat (fuente de verdad) ----------------------------
create table if not exists public.mensajes_chat (
  id               uuid          primary key default gen_random_uuid(),
  conversacion_id  uuid          not null
                     references public.conversaciones(id) on delete cascade,
  rol              text          not null check (rol in ('user', 'assistant')),
  contenido        text          not null,
  creado_en        timestamptz   not null default now()
);

create index if not exists idx_mensajes_chat_conv
  on public.mensajes_chat (conversacion_id, creado_en);

-- 3) Tienda vectorial del historial (SEPARADA de memoria/biblioteca) --------
create table if not exists public.memoria_conversacional (
  id               uuid          primary key default gen_random_uuid(),
  conversacion_id  uuid          not null
                     references public.conversaciones(id) on delete cascade,
  -- El chunk: uno o varios mensajes consecutivos, ya formateados.
  contenido        text          not null,
  -- Fecha del chunk (cuándo se habló), para decir "el [fecha]…".
  fecha            timestamptz   not null,
  n_mensajes       int           not null default 0,
  -- 1536 dims = text-embedding-3-small. Nullable/best-effort: si el embed
  -- falla, el chunk igual queda guardado; solo no aparece en la búsqueda.
  embedding        vector(1536),
  creado_en        timestamptz   not null default now()
);

create index if not exists idx_memconv_conv
  on public.memoria_conversacional (conversacion_id);

-- HNSW parcial (solo filas con embedding) para similitud coseno.
create index if not exists idx_memconv_embedding
  on public.memoria_conversacional using hnsw (embedding vector_cosine_ops)
  where embedding is not null;

alter table public.conversaciones          enable row level security;
alter table public.mensajes_chat           enable row level security;
alter table public.memoria_conversacional  enable row level security;

-- ============================================================================
-- Búsqueda semántica del historial (RAG)
-- ----------------------------------------------------------------------------
-- Igual patrón que `buscar_apunte_chunks` / `buscar_memoria`: el cerebro embebe
-- la consulta y llama por RPC. EXCLUYE la conversación actual (ya está en el
-- contexto del chat) cuando se pasa `excluir_conversacion`.
-- ============================================================================
create or replace function public.buscar_memoria_conversacional(
  query_embedding       vector(1536),
  excluir_conversacion  uuid default null,
  match_count           int  default 5
)
returns table (
  id         uuid,
  contenido  text,
  fecha      timestamptz,
  distancia  float4
)
language sql
stable
as $$
  select
    m.id,
    m.contenido,
    m.fecha,
    (m.embedding <=> query_embedding) as distancia
  from public.memoria_conversacional m
  where m.embedding is not null
    and (excluir_conversacion is null
         or m.conversacion_id is distinct from excluir_conversacion)
  order by m.embedding <=> query_embedding
  limit match_count;
$$;
