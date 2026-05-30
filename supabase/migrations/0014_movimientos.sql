-- ============================================================================
-- 0014 · movimientos · finanzas (la base)
-- ============================================================================
-- Registra ingresos y gastos para ver el balance del mes (Finanzas-1).
-- Solo el modelo base: el escaneo de recibos (Finanzas-2) y el dashboard
-- con gráficos (Finanzas-3) vienen después.
--
-- Escrita idempotente (if not exists / drop trigger if exists) para poder
-- aplicarla a mano sobre un proyecto ya existente sin romper.

create table if not exists public.movimientos (
  id              uuid          primary key default gen_random_uuid(),
  -- 'ingreso' suma al balance; 'gasto' resta. El signo lo da el tipo,
  -- por eso el monto siempre es positivo.
  tipo            text          not null check (tipo in ('ingreso', 'gasto')),
  monto           numeric(12,2) not null check (monto > 0),
  categoria       text          not null default 'General',
  fecha           date          not null default current_date,
  nota            text          not null default '',
  creado_en       timestamptz   not null default now(),
  actualizado_en  timestamptz   not null default now()
);

-- El corte de Finanzas es por mes y se ordena por fecha: índice por fecha.
create index if not exists idx_movimientos_fecha on public.movimientos (fecha desc);
create index if not exists idx_movimientos_tipo  on public.movimientos (tipo);

-- Mantiene actualizado_en al día en cada UPDATE (misma función que el
-- resto de tablas, definida en 0001_initial_schema.sql).
drop trigger if exists trg_movimientos_actualizado on public.movimientos;
create trigger trg_movimientos_actualizado
  before update on public.movimientos
  for each row execute function public.tocar_actualizado();

-- El acceso es vía el service_role del cerebro (omite RLS); activamos RLS
-- por consistencia con el resto del esquema, sin políticas públicas.
alter table public.movimientos enable row level security;
