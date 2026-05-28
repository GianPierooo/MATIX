-- ============================================================================
-- Matix · Capa 4 Paso 1 · OAuth Google + lectura de Calendar
-- ----------------------------------------------------------------------------
-- Trae datos de servicios externos al hub. La decisión arquitectónica
-- (ver `docs/Plan_Capa4.md`) es **sincronizar a Supabase como fuente
-- única de verdad**, marcando los items con `origen='google'` y un
-- `external_id` para evitar duplicados en re-sync.
--
-- Esta migración:
-- 1. Crea `oauth_google` para guardar los tokens OAuth del usuario.
-- 2. Extiende `eventos` con `origen` + `external_id` para distinguir
--    los manuales de los sincronizados.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 12. oauth_google · tokens OAuth de cuentas Google conectadas
-- ----------------------------------------------------------------------------
-- Una fila por cuenta Google del usuario (single-user → típicamente 1).
-- El cerebro lee `refresh_token` para renovar `access_token` cuando expira;
-- `scopes` registra qué permisos se aceptaron (para saber qué APIs podemos
-- llamar sin re-autorizar).
--
-- Tokens en plaintext: ver `docs/Plan_Capa4.md` para la justificación
-- (single-user privado, RLS activa, service_role only).
-- ----------------------------------------------------------------------------
create table public.oauth_google (
  email           text        primary key,
  access_token    text        not null,
  refresh_token   text        not null,
  token_expiry    timestamptz not null,
  scopes          text[]      not null default '{}',
  conectado_en    timestamptz not null default now(),
  ultimo_sync_en  timestamptz
);

alter table public.oauth_google enable row level security;
-- Sin políticas → solo service_role pasa. La app NO debe leer estos
-- tokens directamente; toda interacción es via el cerebro.

-- ----------------------------------------------------------------------------
-- Extender `eventos` con origen y external_id
-- ----------------------------------------------------------------------------
-- `origen`: distingue manuales (default) de sincronizados.
-- `external_id`: id estable del evento en el sistema externo.
-- UNIQUE parcial: evita duplicar al re-sync, pero permite múltiples
-- manuales sin id externo (todos NULL).
-- ----------------------------------------------------------------------------
alter table public.eventos
  add column if not exists origen text not null default 'manual'
    check (origen in ('manual', 'google'));

alter table public.eventos
  add column if not exists external_id text;

alter table public.eventos
  add column if not exists external_account text;

create unique index if not exists uq_eventos_origen_external
  on public.eventos (origen, external_id)
  where external_id is not null;

-- Búsqueda rápida "todos los eventos de Google de tal cuenta", útil
-- al re-sync para detectar los que ya no están en Google y mandar a
-- la papelera.
create index if not exists idx_eventos_origen_account
  on public.eventos (origen, external_account)
  where origen = 'google';
