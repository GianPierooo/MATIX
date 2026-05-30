-- ============================================================================
-- 0018 · rituales diarios por push (Push Capa 3a)
-- ----------------------------------------------------------------------------
-- Los dos rituales (briefing matutino, cierre del día) los dispara ahora el
-- scheduler del cerebro por FCM, no la app con alarmas locales (que los OEM
-- matan). Esta config es la fuente de verdad: hora + on/off de cada ritual.
--
-- `config_rituales`: una fila por ritual. Sembrada activada por defecto
--   (briefing 08:00, cierre 22:00). La app la lee/edita; el scheduler la usa.
-- `rituales_enviados`: dedupe por (ritual, fecha) para no mandar dos veces el
--   mismo ritual el mismo día.
--
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

create table if not exists public.config_rituales (
  id              uuid        primary key default gen_random_uuid(),
  ritual          text        not null unique check (ritual in ('briefing', 'cierre')),
  activo          boolean     not null default true,
  hora            smallint    not null check (hora between 0 and 23),
  minuto          smallint    not null default 0 check (minuto between 0 and 59),
  actualizado_en  timestamptz not null default now()
);

-- Defaults: ambos ON. briefing 08:00, cierre 22:00 (America/Lima).
insert into public.config_rituales (ritual, activo, hora, minuto) values
  ('briefing', true, 8, 0),
  ('cierre',   true, 22, 0)
on conflict (ritual) do nothing;

drop trigger if exists trg_config_rituales_actualizado on public.config_rituales;
create trigger trg_config_rituales_actualizado
  before update on public.config_rituales
  for each row execute function public.tocar_actualizado();

create table if not exists public.rituales_enviados (
  id          uuid        primary key default gen_random_uuid(),
  ritual      text        not null check (ritual in ('briefing', 'cierre')),
  fecha       date        not null,
  enviado_en  timestamptz not null default now(),
  unique (ritual, fecha)
);

create index if not exists idx_rituales_enviados_fecha
  on public.rituales_enviados (fecha);

alter table public.config_rituales enable row level security;
alter table public.rituales_enviados enable row level security;
