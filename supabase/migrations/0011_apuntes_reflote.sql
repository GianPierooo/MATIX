-- ============================================================================
-- Matix · Capa 7 · Reflote de ideas
-- ----------------------------------------------------------------------------
-- Las ideas que capturas y no tocas se quedan dormidas. El "reflote" las
-- trae de vuelta a Inicio para que no mueran en el olvido. Esta migración
-- agrega lo único que falta para soportarlo:
--
--   archivado_en  Marca de "archivada para el reflote". Cuando se setea, el
--                 apunte deja de reflotarse PARA SIEMPRE. Es distinto del
--                 soft-delete (`eliminado_en`): archivar NO manda el apunte a
--                 la papelera ni lo saca de la lista de Apuntes — solo lo
--                 retira del reflote de Inicio.
--
-- "Última vez tocada/reflotada" NO necesita columna nueva: ya es
-- `actualizado_en`, que el trigger `tocar_actualizado()` bumpea en cada
-- UPDATE. Por eso "retomar" = tocar el apunte (cualquier update lo saca del
-- reflote por otros 14 días, hasta que vuelva a dormirse). "Archivar" =
-- setear `archivado_en` (no vuelve nunca).
-- ============================================================================

alter table public.apuntes
  add column if not exists archivado_en timestamptz;

-- Índice parcial para la consulta de candidatos a reflote: apuntes activos
-- (no borrados, no archivados) ordenados por antigüedad de actualización.
create index if not exists idx_apuntes_reflote
  on public.apuntes (actualizado_en)
  where eliminado_en is null and archivado_en is null;
