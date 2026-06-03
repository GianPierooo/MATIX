-- ============================================================================
-- 0029 · perfil profundo de proyectos (Paso 1: capa de conocimiento)
-- ----------------------------------------------------------------------------
-- Conocimiento ESTRUCTURADO y fino por proyecto, para que más adelante un
-- planificador diario pueda proponer subtareas útiles. ESTE paso es solo la
-- capa de datos + su captura: NADA de generar subtareas ni nudges todavía.
--
-- No se mezcla con otras tiendas:
--   - memoria (0022)            = hechos sueltos del usuario.
--   - memoria_conversacional    = recall de conversaciones.
--   - ESTO                      = perfil de cada proyecto (no semántico).
--
-- Diseño pensado para el futuro motor de planificación: `componente` +
-- `proximo_paso` (con `estado`) son las piezas que ese motor leerá. Pero no se
-- construye el motor aquí.
--
-- 1) Campos escalares de perfil en `proyectos` (el "encabezado").
-- 2) `proyecto_detalles` · ítems que se acumulan CON FECHA (componentes,
--    próximos pasos, blockers, notas, decisiones), cada uno con su estado.
-- 3) `entrevistas_perfil` · estado del bootstrap (qué se preguntó), para
--    poder cortar y retomar sin perder lo avanzado.
--
-- No destructiva, idempotente.
-- ============================================================================

-- 1) Encabezado del perfil en proyectos --------------------------------------
-- `objetivo` es el POR QUÉ / objetivo de fondo (distinto de `linea_meta`, que
-- es la definición de "terminado" que ya existía en 0002).
alter table public.proyectos add column if not exists objetivo               text;
alter table public.proyectos add column if not exists estado_actual          text;
alter table public.proyectos add column if not exists horizonte              text;
alter table public.proyectos add column if not exists fase_actual            text;
alter table public.proyectos add column if not exists perfil_actualizado_en  timestamptz;

-- 2) Detalles acumulables con fecha ------------------------------------------
create table if not exists public.proyecto_detalles (
  id              uuid          primary key default gen_random_uuid(),
  proyecto_id     uuid          not null
                    references public.proyectos(id) on delete cascade,
  -- componente/subobjetivo, próximo paso, blocker, nota o decisión.
  tipo            text          not null
                    check (tipo in ('componente', 'proximo_paso', 'blocker', 'nota', 'decision')),
  contenido       text          not null,
  -- abierto/hecho (componente, proximo_paso), abierto/resuelto (blocker),
  -- archivado (cualquiera). nota/decision se quedan en 'abierto' (no aplica).
  estado          text          not null default 'abierto'
                    check (estado in ('abierto', 'hecho', 'resuelto', 'archivado')),
  creado_en       timestamptz   not null default now(),
  actualizado_en  timestamptz   not null default now()
);

create index if not exists idx_proyecto_detalles_pte
  on public.proyecto_detalles (proyecto_id, tipo, estado);

drop trigger if exists trg_proyecto_detalles_actualizado on public.proyecto_detalles;
create trigger trg_proyecto_detalles_actualizado
  before update on public.proyecto_detalles
  for each row execute function public.tocar_actualizado();

-- 3) Estado de la entrevista de bootstrap ------------------------------------
-- Una fila por proyecto. `preguntados` lista los campos ya preguntados (para
-- no re-preguntar lo opcional vacío, p. ej. blockers cuando no hay).
create table if not exists public.entrevistas_perfil (
  proyecto_id     uuid          primary key
                    references public.proyectos(id) on delete cascade,
  estado          text          not null default 'en_curso'
                    check (estado in ('en_curso', 'pausada', 'completada')),
  preguntados     jsonb         not null default '[]'::jsonb,
  creado_en       timestamptz   not null default now(),
  actualizado_en  timestamptz   not null default now()
);

drop trigger if exists trg_entrevistas_perfil_actualizado on public.entrevistas_perfil;
create trigger trg_entrevistas_perfil_actualizado
  before update on public.entrevistas_perfil
  for each row execute function public.tocar_actualizado();

alter table public.proyecto_detalles   enable row level security;
alter table public.entrevistas_perfil  enable row level security;
