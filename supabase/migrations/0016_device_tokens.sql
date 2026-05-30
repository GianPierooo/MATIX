-- ============================================================================
-- 0016 · device_tokens · tokens FCM para push (Push Capa 1)
-- ----------------------------------------------------------------------------
-- Guarda los tokens de Firebase Cloud Messaging de los dispositivos del
-- usuario, para poder mandarles push desde el cerebro. Esto reemplaza a las
-- notificaciones locales programadas, que los OEM (Honor/Huawei) matan en
-- segundo plano.
--
-- Capa 1: solo registrar el token y poder mandar un push de prueba. El
-- scheduler y la migración de los recordatorios reales son capas siguientes.
--
-- Es de un solo usuario (Gian Piero): no hay columna de user_id. Si en el
-- futuro hay multiusuario, se agrega.
--
-- Idempotente (if not exists / drop trigger if exists): aplicable a mano.
-- ============================================================================

create table if not exists public.device_tokens (
  id              uuid        primary key default gen_random_uuid(),
  -- El token de FCM del dispositivo. Único: si el mismo dispositivo
  -- re-registra, hacemos upsert por este token.
  token           text        not null unique,
  plataforma      text        not null default 'android',
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create index if not exists idx_device_tokens_token
  on public.device_tokens (token);

drop trigger if exists trg_device_tokens_actualizado on public.device_tokens;
create trigger trg_device_tokens_actualizado
  before update on public.device_tokens
  for each row execute function public.tocar_actualizado();

alter table public.device_tokens enable row level security;
