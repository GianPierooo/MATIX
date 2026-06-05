-- ============================================================================
-- Matix · Capa 8 · Rollover de tareas no cumplidas
-- ----------------------------------------------------------------------------
-- Cuando una tarea no se hizo a su hora (su bloque) o al cierre del día (su
-- vencimiento), Matix la reprograma al siguiente hueco libre — proponiéndolo,
-- nunca en silencio. Para el guardrail honesto anti-acumulación necesitamos
-- saber CUÁNTAS veces se ha movido cada tarea: si se arrastra una y otra vez,
-- ya no es de cambiar de día, toca re-escopar o bajar la carga.
--
--   veces_reprogramada  cuántas veces el rollover movió esta tarea. Sube en
--                       cada "acepto"/"otro día"; alimenta el umbral de
--                       sobrecarga del motor (rollover.evaluar_sobrecarga).
-- ============================================================================

alter table public.tareas
  add column if not exists veces_reprogramada smallint not null default 0;
