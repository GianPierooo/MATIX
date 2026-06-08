-- ============================================================================
-- Matix · Notis proactivas · lead time pre-actividad
-- ----------------------------------------------------------------------------
-- Las notis programadas pre-actividad ("en 15 min: práctica de guitarra")
-- corren con un lead_min default de 15. Esta columna deja que la app/Matix la
-- ajusten (10-30 min típico) sin code change. Si la columna falta o es NULL,
-- el armador cae a 15.
--
-- Aditiva (NULLABLE), no destructiva.
-- ============================================================================

alter table public.config_nudges
  add column if not exists pre_actividad_min smallint
    check (pre_actividad_min is null or pre_actividad_min between 0 and 120);
