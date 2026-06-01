-- ============================================================================
-- 0025 · movimientos.lote_id · rastreo de lote para revertir seguro
-- ----------------------------------------------------------------------------
-- Cada movimiento que crea Matix (uno suelto o un lote desde una imagen) lleva
-- un `lote_id`. Así «revertir» / «corrige» borra SOLO los del último lote que
-- Matix registró, nunca movimientos buenos no relacionados ni los que creaste
-- a mano (esos quedan con lote_id NULL).
--
-- Idempotente: se puede aplicar a mano sobre un proyecto existente.
-- ============================================================================

alter table public.movimientos
  add column if not exists lote_id uuid;

-- Para encontrar rápido el último lote (los movimientos con lote_id, por fecha
-- de creación) y borrar un lote completo por su id.
create index if not exists idx_movimientos_lote
  on public.movimientos (lote_id);
