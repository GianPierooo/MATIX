-- ============================================================================
-- 0023 · modelo de chat seleccionado
-- ----------------------------------------------------------------------------
-- La app elige el modelo del LLM de chat (de un catálogo curado en el cerebro,
-- `app/matix/modelos_llm.py`). La selección se guarda acá; el env
-- `MATIX_LLM_MODEL` queda como default/fallback. El proveedor se infiere del
-- id del modelo (claude-* → anthropic; gpt-*/o* → openai).
--
-- Vive en `config_matix` (el singleton de config de Matix, junto a
-- `modo_activo`). `null` = usar el fallback de env.
--
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

alter table public.config_matix
  add column if not exists modelo_chat text;
