-- ============================================================================
-- Matix · Pings de rendición de cuentas (push directo con botones de acción)
-- ----------------------------------------------------------------------------
-- Cuando una tarea queda sin completar, el cerebro empuja un push directo del
-- sistema con tres botones ("Sí, lo hice" / "Aplázala mañana" / "Aplázala más
-- tarde"). Esta tabla sirve para el DEDUP por tarea + ESCALADA con tope:
--
--   nivel 1 = aviso suave (la primera vez al cierre del día / al pasar el plazo)
--   nivel 2 = recordatorio firme (al día siguiente si sigue sin cerrar)
--   nivel 3 = aviso final (último; tras esto se silencia esta tarea)
--
-- La tarea no se vuelve a pingar dentro del mismo nivel (dedup por nivel) y
-- jamás supera el nivel 3 (tope dura para no convertirse en spam infinito).
-- Cuando el usuario actúa con un botón (hecho / mañana / más tarde), el
-- registro se MARCA como `resuelta_en` para no volver a pingar la misma.
--
-- Solo aditiva (no destructiva).
-- ============================================================================

create table if not exists public.pings_rendicion_cuentas (
    id           uuid primary key default gen_random_uuid(),
    tarea_id     uuid not null references public.tareas(id) on delete cascade,
    -- Nivel actual: 1=suave, 2=firme, 3=final.
    nivel        smallint not null check (nivel between 1 and 3),
    enviado_en   timestamptz not null default now(),
    -- Resuelta: la tarea ya se atendió (botón Hecho / Mañana / Más tarde).
    -- Cuando se setea, no se vuelve a pingar esta tarea (silencio dura).
    resuelta_en  timestamptz,
    accion       text check (accion is null or accion in
                             ('hecho', 'manana', 'mas_tarde'))
);

-- Lookup más común: "¿cuál fue el último ping de esta tarea?" + "¿está resuelto?"
create index if not exists idx_pings_rc_tarea
    on public.pings_rendicion_cuentas(tarea_id, enviado_en desc);
-- Para barrer todas las pendientes del día (no resueltas).
create index if not exists idx_pings_rc_no_resueltas
    on public.pings_rendicion_cuentas(resuelta_en)
    where resuelta_en is null;
