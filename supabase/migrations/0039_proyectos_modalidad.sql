-- ============================================================================
-- Matix · Proyectos · capacidad estimada y modalidad de trabajo
-- ----------------------------------------------------------------------------
-- Los proyectos hoy no llevan capacidad explícita (cuántas horas/semana se les
-- dedica) ni modalidad (¿lleva bloque fijo? ¿se intercala con otros en huecos
-- profundos?). El planificador asume implícitamente "continuo intercalado":
-- las tareas del proyecto pelean por huecos profundos en `_items_a_colocar` y
-- `colocar` las pone en el pico. Esta migración lo hace EXPLÍCITO para que:
--
--   - El usuario (o Matix) pueda decir "Matix 1.0 son ~15 h/semana intercaladas".
--   - El planificador pueda diferenciar en el futuro (cuando aparezca
--     `slot_fijo`) sin romper proyectos viejos: NULL o "continuo_intercalado"
--     mantiene el comportamiento actual.
--   - Quede una nota interna libre para suposiciones del usuario o Matix que
--     no son canónicas todavía ("estimación pendiente de confirmar").
--
-- Solo añade columnas NULLABLES (no destructiva).
-- ============================================================================

alter table public.proyectos
  add column if not exists horas_semana_estimadas smallint
    check (horas_semana_estimadas is null or horas_semana_estimadas between 0 and 168),
  add column if not exists modalidad text
    check (modalidad is null or modalidad in (
      'continuo_intercalado',  -- default semántico: pelea por huecos profundos
      'slot_fijo',             -- reserva una franja fija (no implementado aún)
      'esporadico'             -- entra solo cuando hay tiempo, sin presión
    )),
  add column if not exists nota_interna text;

-- Índice ligero por modalidad: cuando el planificador la mire para decidir si
-- crear un slot fijo o no, evita scan completo.
create index if not exists idx_proyectos_modalidad
  on public.proyectos(modalidad)
  where modalidad is not null;
