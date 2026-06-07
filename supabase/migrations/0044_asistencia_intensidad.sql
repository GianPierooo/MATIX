-- ============================================================================
-- 0044 · Confirmación de ASISTENCIA a eventos + INTENSIDAD de los avisos
-- ----------------------------------------------------------------------------
-- Extiende el sistema de rendición de cuentas (notis con botones de acción):
--
-- 1) ASISTENCIA por evento: tras un evento FUERA DE CASA (con `ubicacion`),
--    Matix pregunta "¿Fuiste a X?". La respuesta (asistió / no asistió) se
--    guarda en el propio evento y alimenta el motor de evolución (tasas reales).
--    `asistencia_preguntada_en` dedupea el ping (no re-preguntar el mismo evento).
--
-- 2) INTENSIDAD graduable de los avisos (dial en Ajustes): suave / medio /
--    intenso / máximo. Default 'intenso' (lo que el dueño quiere). El cerebro la
--    incluye en el payload del push y la app la mapea al mecanismo Android
--    (heads-up, persistente, full-screen). Vive en config_nudges (singleton).
--
-- Aditiva e idempotente: no toca datos.
-- ============================================================================

-- Asistencia confirmada por el usuario (NULL = sin confirmar / no aplica).
alter table public.eventos
  add column if not exists asistencia text
    check (asistencia is null or asistencia in ('asistio', 'no_asistio'));

-- Cuándo se preguntó por la asistencia (dedup del ping; NULL = no preguntada).
alter table public.eventos
  add column if not exists asistencia_preguntada_en timestamptz;

-- Intensidad de los avisos de rendición de cuentas / asistencia.
alter table public.config_nudges
  add column if not exists intensidad text not null default 'intenso'
    check (intensidad in ('suave', 'medio', 'intenso', 'maximo'));
