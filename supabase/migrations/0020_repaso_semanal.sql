-- ============================================================================
-- 0020 · repaso semanal por push (4º ritual)
-- ----------------------------------------------------------------------------
-- Suma el "repaso semanal" como un tercer ritual del scheduler, además del
-- briefing matutino y el cierre del día. A diferencia de esos (diarios), el
-- repaso es SEMANAL: corre un día de la semana a una hora (por defecto
-- domingo 20:00, hora de Lima), editable. El dedup se hace por número de
-- semana ISO (en `rituales_enviados.fecha` se guarda el LUNES de esa semana),
-- así no se duplica dentro de la misma semana.
--
-- Cambios:
--  - `config_rituales.ritual` ahora admite 'repaso'.
--  - `config_rituales.dia_semana` (ISO 1=lun … 7=dom): NULL para los rituales
--    diarios (briefing/cierre), poblado para los semanales.
--  - `rituales_enviados.ritual` también admite 'repaso'.
--  - semilla: repaso ON, domingo (7) 20:00.
--
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

-- Reemplaza el CHECK de `ritual` en config_rituales para incluir 'repaso'.
-- Borramos cualquier check existente sobre la columna `ritual` (su nombre
-- puede variar) y ponemos el nuevo con nombre estable.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.config_rituales'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%ritual%'
  loop
    execute format('alter table public.config_rituales drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.config_rituales
  add constraint config_rituales_ritual_check
  check (ritual in ('briefing', 'cierre', 'repaso'));

-- Día de la semana (ISO 1..7) para rituales SEMANALES. NULL = diario.
alter table public.config_rituales
  add column if not exists dia_semana smallint
  check (dia_semana is null or dia_semana between 1 and 7);

-- Mismo reemplazo del CHECK en rituales_enviados.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.rituales_enviados'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%ritual%'
  loop
    execute format('alter table public.rituales_enviados drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.rituales_enviados
  add constraint rituales_enviados_ritual_check
  check (ritual in ('briefing', 'cierre', 'repaso'));

-- Semilla: repaso semanal, domingo 20:00, activo (proactividad por defecto).
insert into public.config_rituales (ritual, activo, hora, minuto, dia_semana) values
  ('repaso', true, 20, 0, 7)
on conflict (ritual) do nothing;
