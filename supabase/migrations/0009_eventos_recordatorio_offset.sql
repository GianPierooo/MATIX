-- ============================================================================
-- Matix · Calendario Paso 2 · Recordatorio por evento (offset antes del inicio)
-- ----------------------------------------------------------------------------
-- El recordatorio de un evento se modela como un offset en minutos antes
-- del inicio (NULL = sin recordatorio; 0 = a la hora; 10 / 60 / 1440 = los
-- presets de la app). Es la fuente de verdad para mostrar "10 minutos antes"
-- en el detalle y para que la app reprograme la notificación local cuando
-- cambia la hora del evento.
--
-- `recordar_en` (instante absoluto, ya existente) se mantiene como espejo
-- derivado = inicia_en − offset, para no romper a ningún lector previo. La
-- app es quien lo calcula al guardar.
-- ============================================================================

alter table public.eventos
  add column if not exists recordatorio_offset_min integer;
