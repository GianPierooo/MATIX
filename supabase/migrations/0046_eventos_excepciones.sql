-- 0046 — Excepciones de recurrencia para eventos (2.0 · Fase 3 · Calendario).
--
-- Permite "borrar esta sola ocurrencia" / "editar esta sola ocurrencia" de un
-- evento recurrente SIN materializar todas las instancias: la serie sigue
-- viviendo como una REGLA (recurrencia_freq + …), y las fechas excluidas se
-- guardan aquí. El motor de recurrencia (`comandos/recurrencia.ocurre_en`)
-- salta cualquier fecha presente en este arreglo.
--
-- Aditiva y no destructiva (idempotente).

alter table public.eventos
  add column if not exists recurrencia_excepciones date[];

comment on column public.eventos.recurrencia_excepciones is
  'Fechas (date) excluidas de la serie recurrente. Una ocurrencia borrada/'
  'detachada con alcance "solo_esta" agrega su fecha aquí; ocurre_en la salta.';
