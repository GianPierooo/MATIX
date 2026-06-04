-- ============================================================================
-- 0032 · intake analítico por parámetros (perfil profundo · intake profundo)
-- ----------------------------------------------------------------------------
-- El intake de creación pasa de genérico a ANALÍTICO y POR PARÁMETROS: detecta
-- el TIPO de proyecto (negocio/marca, aprender skill, construir, físico…) y
-- llena el esquema de parámetros de ese tipo antes de planear.
--
-- - `proyectos.tipo`: el tipo detectado (para elegir el esquema). Texto libre
--   con un set conocido; null = sin clasificar todavía.
-- - `proyectos.parametros` (jsonb): el esquema lleno {clave: valor}, incluido
--   el PORQUÉ/motivación y los CRITERIOS DE ÉXITO. Extensible sin migrar.
--
-- Reusa objetivo/horizonte/estado_actual/fase_actual (0029) y el árbol (0030).
-- No destructiva, idempotente.
-- ============================================================================

alter table public.proyectos add column if not exists tipo        text;
alter table public.proyectos add column if not exists parametros  jsonb not null default '{}'::jsonb;
