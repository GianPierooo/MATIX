-- ============================================================================
-- 0033 · motor de evolución de proyectos (seguimiento + celebración de hitos)
-- ----------------------------------------------------------------------------
-- Matix mejora cada proyecto con el tiempo: revisión holística, generación
-- progresiva, check-in semanal, detección de estancamiento y celebración de
-- hitos. Casi todo reusa lo existente (árbol, %, scheduler, FCM, perfil).
--
-- Lo único que necesita estado nuevo: marcar cuándo se CELEBRÓ un hito (una
-- fase raíz completada) para no felicitar dos veces. El resto de dedups van
-- en `planificacion_enviados` (tipo libre por proyecto).
--
-- No destructiva, idempotente.
-- ============================================================================

alter table public.arbol_nodos add column if not exists celebrado_en timestamptz;
