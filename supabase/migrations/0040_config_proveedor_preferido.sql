-- ============================================================================
-- Matix · Config · proveedor de IA preferido (resiliencia multi-proveedor)
-- ----------------------------------------------------------------------------
-- Añade a config_matix una preferencia transversal de proveedor de IA:
--   'openai' | 'anthropic' | 'auto' (default).
-- El cerebro intenta PRIMERO el proveedor preferido (chat, visión, JSON) y, si
-- cae (incluido crédito agotado), hace failover al otro. 'auto' usa el modelo
-- seleccionado tal cual y cae al otro.
--
-- Solo añade una columna NULLABLE (no destructiva).
-- ============================================================================

alter table public.config_matix
  add column if not exists proveedor_preferido text
    check (proveedor_preferido is null
           or proveedor_preferido in ('openai', 'anthropic', 'auto'));
