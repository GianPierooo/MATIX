-- ============================================================================
-- 0026 · chat_operaciones · idempotencia + reconciliación del chat
-- ----------------------------------------------------------------------------
-- Si el usuario sale de la app a mitad de un turno de Matix, la conexión se
-- aborta, pero el cerebro YA está procesando (y escribiendo en Supabase). Para
-- que al volver/reintentar no se pierda el resultado ni se dupliquen escrituras:
--
--   - La app manda una `idempotency_key` por turno y la REUSA si reintenta.
--   - El cerebro guarda acá el estado y el resultado del turno por esa clave.
--   - Un reintento con la MISMA clave: si ya está 'ok', devuelve el resultado
--     guardado SIN re-ejecutar las tools (no duplica gastos/tareas). Si sigue
--     'procesando', responde 409 (reintenta en un momento).
--
-- `resultado` guarda el ChatResponse completo (jsonb) para devolverlo igual.
-- Idempotente: se puede aplicar a mano.
-- ============================================================================

create table if not exists public.chat_operaciones (
  id               uuid          primary key default gen_random_uuid(),
  -- La clave la genera la app; texto para no atarnos al formato uuid.
  idempotency_key  text          not null unique,
  estado           text          not null
                     check (estado in ('procesando', 'ok', 'error')),
  -- El ChatResponse completo cuando estado = 'ok'.
  resultado        jsonb,
  creado_en        timestamptz   not null default now(),
  actualizado_en   timestamptz   not null default now()
);

create index if not exists idx_chat_operaciones_creado
  on public.chat_operaciones (creado_en desc);

drop trigger if exists trg_chat_operaciones_actualizado on public.chat_operaciones;
create trigger trg_chat_operaciones_actualizado
  before update on public.chat_operaciones
  for each row execute function public.tocar_actualizado();

alter table public.chat_operaciones enable row level security;
