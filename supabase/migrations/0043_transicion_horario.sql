-- ============================================================================
-- 0043 · Buffer de TRANSICIÓN tras compromisos fuera de casa (Capa 1 · planner)
-- ----------------------------------------------------------------------------
-- Un compromiso fijo puede ser FUERA DE CASA (una clase de uni, o un evento con
-- `ubicacion`). Tras él hay que volver/reacomodarse: el planificador reserva un
-- buffer de TRANSICIÓN donde NO coloca trabajo de casa.
--
-- Modelo (confirmado con el dueño): un default GLOBAL editable en config_horario
-- + un OVERRIDE opcional por evento (p. ej. uni 1h, gym 30min). Las clases usan
-- el default global. La dirección es SOLO DESPUÉS del compromiso (el buffer_min
-- corto ya pad-ea ambos lados; esto es el colchón grande post-evento).
--
-- Aditiva e idempotente: no toca datos, solo agrega columnas con default sensato.
-- ============================================================================

-- Default global del buffer de transición (minutos). 0 = sin transición.
alter table public.config_horario
  add column if not exists transicion_min smallint not null default 60
    check (transicion_min between 0 and 240);

-- Override por evento (NULL = usa el default global). 0 = sin transición para
-- ese evento puntual.
alter table public.eventos
  add column if not exists transicion_min smallint
    check (transicion_min is null or transicion_min between 0 and 240);
