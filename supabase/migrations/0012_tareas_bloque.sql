-- ============================================================================
-- Matix · Capa 7 · Urgencia-3 · Planificar el día
-- ----------------------------------------------------------------------------
-- Cuando le pides a Matix "planifica mi día", te propone bloques de tiempo
-- para tus tareas y, al aceptar, cada tarea queda con SU bloque (inicio/fin).
-- Ese bloque es un "plazo propio" que alimenta los contadores y nudges de
-- Urgencia-1/2.
--
--   bloque_inicio  cuándo empezar la tarea hoy.
--   bloque_fin     cuándo debería estar hecha (la urgencia usa este como
--                  plazo efectivo cuando está seteado, sin pisar `vence_en`,
--                  que sigue siendo el plazo real de entrega si lo hubiera).
-- ============================================================================

alter table public.tareas
  add column if not exists bloque_inicio timestamptz,
  add column if not exists bloque_fin    timestamptz;
