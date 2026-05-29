-- ============================================================================
-- Matix · Capa 4 Paso 2 · Calendar bidireccional (hub ↔ Google)
-- ----------------------------------------------------------------------------
-- El Paso 1 traía Google → hub. Acá cerramos el ciclo hub → Google.
--
-- Cambios:
--
-- 1. `eventos.google_updated_at` — el `updated` ISO que Google reporta para
--    el evento. Es el reloj canónico del lado Google. Lo usamos para
--    last-write-wins (ver `docs/Plan_Capa4.md` · Conflictos):
--    - Pull aplica el cambio solo si `google_updated > hub.actualizado_en + 2s`.
--    - Push lo refresca tras el ack para que el siguiente pull no confunda
--      nuestro propio push con una edición remota.
--
-- 2. Ajuste de UNIQUE. El Paso 1 tenía:
--      UNIQUE (origen, external_id) WHERE external_id IS NOT NULL
--    Eso impedía que un evento `origen='manual'` con `external_id` (porque
--    lo pusheamos a Google) coexista con un futuro pull del mismo evento
--    que vendría como `origen='google'`. Con el push bidireccional, un
--    evento manual pusheado tiene que dedupar contra cualquier futuro
--    pull SIN importar el origen. Por eso pasamos a:
--      UNIQUE (external_account, external_id) WHERE external_id IS NOT NULL
--    Esto deduplica por cuenta + ID Google, atravesando los orígenes.
-- ============================================================================

-- Reloj canónico de Google para cada evento sincronizado. NULL para los
-- que aún no llegaron a Google (manuales sin push exitoso, o nunca había
-- conexión cuando se crearon — los recoge el sweep de backfill al sync).
alter table public.eventos
  add column if not exists google_updated_at timestamptz;

-- Reemplazamos el UNIQUE viejo (origen, external_id) por el nuevo
-- (external_account, external_id). El nuevo cubre el caso bidireccional
-- sin permitir duplicados.
drop index if exists uq_eventos_origen_external;

create unique index if not exists uq_eventos_external_account_id
  on public.eventos (external_account, external_id)
  where external_id is not null;
