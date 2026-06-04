-- ============================================================================
-- 0034 · skills/hábitos como proyectos aparte (flag es_skill)
-- ----------------------------------------------------------------------------
-- Inglés, Guitarra, Trading, Portugués… son SKILLS/HÁBITOS: se practican en
-- ratos libres y NO compiten con los 3 proyectos de trabajo (OneXotic, Matix,
-- Shadow Games) ni reciben la misma insistencia. Para distinguirlos sin romper
-- nada, agregamos un flag:
--
--   - `es_skill = false` (default) → proyecto de trabajo normal. Cuentan para
--     el tope de 3 activos.
--   - `es_skill = true`            → skill/hábito. NO consume slot del tope de
--     3; tiene su propio tope BLANDO (2 activas: se avisa, no se bloquea) y una
--     dosificación LIGERA en el motor de nudges (nudges suaves y opcionales,
--     celebra victorias pequeñas, sin la insistencia de una tarea comprometida).
--
-- La regla del tope (contar solo es_skill=false) vive en el cerebro, igual que
-- el tope de 3 (ver 0002). Acá solo está el dato.
--
-- No destructiva, idempotente: solo agrega columna (con default) e índice.
-- ============================================================================

alter table public.proyectos
  add column if not exists es_skill boolean not null default false;

-- Índice para los conteos filtrados (tope de 3 = solo es_skill=false; tope
-- blando de skills = solo es_skill=true) y para listar skills aparte.
create index if not exists idx_proyectos_es_skill on public.proyectos (es_skill);
