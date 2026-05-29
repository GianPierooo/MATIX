-- ============================================================================
-- Matix · Calendario Paso 3 · Eventos recurrentes (regla de recurrencia)
-- ----------------------------------------------------------------------------
-- La recurrencia de un evento se guarda como REGLA en la misma fila; no se
-- materializan ocurrencias. La app expande las ocurrencias dentro del rango
-- visible (mes/día) y programa los recordatorios de una ventana móvil.
--
--   recurrencia_freq        NULL = sin recurrencia (evento único).
--                           'diaria' | 'semanal' | 'mensual'.
--                           "cada día de semana" se modela como 'semanal'
--                           con recurrencia_dias_semana = {1,2,3,4,5}.
--   recurrencia_dias_semana días ISO (1=lunes … 7=domingo). Solo aplica a
--                           'semanal'. NULL/{} = el día de inicio de la serie.
--   recurrencia_fin_tipo    'nunca' | 'hasta' | 'conteo'. NULL = 'nunca'.
--   recurrencia_hasta       fecha límite inclusiva (solo si fin = 'hasta').
--   recurrencia_conteo      nº de ocurrencias (solo si fin = 'conteo').
-- ============================================================================

alter table public.eventos
  add column if not exists recurrencia_freq        text,
  add column if not exists recurrencia_dias_semana smallint[],
  add column if not exists recurrencia_fin_tipo    text,
  add column if not exists recurrencia_hasta        date,
  add column if not exists recurrencia_conteo       integer;
