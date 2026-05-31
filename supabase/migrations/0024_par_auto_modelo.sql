-- Modo "Automático" del selector de modelo.
--
-- El par barato/fuerte que usa el enrutador por reglas cuando el modelo
-- seleccionado es "auto". Viven en el singleton config_matix junto a
-- modo_activo y modelo_chat. Si quedan en null, el cerebro usa sus defaults
-- (barato = gpt-4o-mini, fuerte = claude-sonnet-4-6).
--
-- La SELECCIÓN "auto" se guarda en la columna existente modelo_chat con el
-- valor literal 'auto' (no necesita columna nueva).

alter table public.config_matix
  add column if not exists modelo_barato text;

alter table public.config_matix
  add column if not exists modelo_fuerte text;
