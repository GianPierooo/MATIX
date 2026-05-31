-- ============================================================================
-- 0021 · modos de Matix
-- ----------------------------------------------------------------------------
-- Un "modo" es un bundle que ajusta el tono + conocimiento + prioridades de
-- Matix (p.ej. tesis, estudio, motivación). Los modos viven como archivos
-- `.md` versionados en el repo del cerebro (app/matix/modos/*.md). Acá solo
-- guardamos CUÁL está activo, para que el chat lo inyecte y la app muestre el
-- indicador.
--
-- `config_matix` es una fila única (singleton, como config_nudges/rituales):
--   - `modo_activo`: NULL = modo normal; si no, el NOMBRE del modo (el nombre
--     del archivo .md sin extensión, ej. 'tesis'). No ponemos CHECK: la lista
--     válida la define el repo (los .md), y el código ignora un modo que ya
--     no exista.
--
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

create table if not exists public.config_matix (
  id              uuid        primary key default gen_random_uuid(),
  modo_activo     text,
  actualizado_en  timestamptz not null default now()
);

-- Sembramos la fila única (sin modo: normal).
insert into public.config_matix (modo_activo)
  select null
  where not exists (select 1 from public.config_matix);

drop trigger if exists trg_config_matix_actualizado on public.config_matix;
create trigger trg_config_matix_actualizado
  before update on public.config_matix
  for each row execute function public.tocar_actualizado();

alter table public.config_matix enable row level security;
