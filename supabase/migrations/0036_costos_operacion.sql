-- ============================================================================
-- 0036 · operación: costo de API persistido + umbrales de alerta
-- ----------------------------------------------------------------------------
-- Cierre de deuda operativa. El medidor en memoria (uso.py) se pierde al
-- reiniciar; ahora persistimos el gasto estimado por DÍA (el mes = suma de
-- días) para poder responder «¿cuánto gasté hoy / este mes?» y alertar al
-- cruzar un umbral. Instrumentación ADITIVA: no cambia el comportamiento de
-- ninguna feature.
--
-- No destructiva, idempotente.
-- ============================================================================

-- Gasto estimado por día (USD), con desglose por categoría.
create table if not exists public.costos_api (
  fecha           date          primary key,
  gasto_usd       numeric(12,6) not null default 0,
  -- {chat, vision, whisper, tts, embedding, tavily} → USD acumulado del día.
  por_categoria   jsonb         not null default '{}'::jsonb,
  actualizado_en  timestamptz   not null default now()
);

-- Umbrales de alerta + dedup (singleton).
create table if not exists public.config_costos (
  id                  uuid          primary key default gen_random_uuid(),
  activo              boolean       not null default true,
  umbral_diario_usd   numeric(10,2) not null default 1.00,
  umbral_mensual_usd  numeric(10,2) not null default 15.00,
  -- Para no repetir la alerta: último día / mes ya avisado.
  alerta_diaria_fecha date,
  alerta_mensual_mes  text,          -- 'YYYY-MM'
  actualizado_en      timestamptz   not null default now()
);

-- Siembra el singleton de config si está vacío.
insert into public.config_costos (id)
  select gen_random_uuid()
  where not exists (select 1 from public.config_costos);

alter table public.costos_api    enable row level security;
alter table public.config_costos enable row level security;
