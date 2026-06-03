-- ============================================================================
-- 0030 · árbol de descomposición vivo por proyecto (perfil profundo · Paso 2)
-- ----------------------------------------------------------------------------
-- Sustrato de PLANIFICACIÓN por proyecto activo: un árbol de nodos (fases →
-- componentes → pasos) del que en el Paso 3 saldrán las subtareas diarias.
--
-- CLAVE: este árbol es ESTRUCTURA DE PLANIFICACIÓN, SEPARADA de la lista de
-- Tareas del hub. NO se vuelcan los nodos a `tareas` (eso es el Paso 3, que
-- promoverá solo los próximos pocos). La lista de Tareas se mantiene limpia.
--
-- Cuelga del perfil (0029): se genera desde objetivo + componentes + próximos
-- pasos. Elaboración progresiva: la fase ACTUAL se detalla fino; las lejanas
-- quedan gruesas (granularidad='grueso') y se refinan al acercarse.
--
-- `tarea_id` enlaza un nodo con una tarea del hub SOLO cuando el Paso 3 la
-- promueva; sirve para el "vivo": al completar esa tarea, el nodo se marca
-- hecho. En el Paso 2 queda null (sin promoción), pero el enlace y el hook ya
-- viven acá.
--
-- No destructiva, idempotente.
-- ============================================================================

create table if not exists public.arbol_nodos (
  id              uuid          primary key default gen_random_uuid(),
  proyecto_id     uuid          not null
                    references public.proyectos(id) on delete cascade,
  -- null = nodo raíz (una fase/bloque del proyecto).
  parent_id       uuid          references public.arbol_nodos(id) on delete cascade,
  titulo          text          not null,
  estado          text          not null default 'pendiente'
                    check (estado in ('pendiente', 'en_curso', 'hecho')),
  orden           int           not null default 0,
  -- Etiqueta de fase o bloque (p. ej. "Marco teórico", "Bloque 3").
  fase            text,
  -- Tamaño estimado opcional: chico | medio | grande (texto libre, no forzado).
  tamano          text,
  -- Elaboración progresiva: 'grueso' = placeholder sin desglosar (fase lejana);
  -- 'fino' = ya desglosado en sus pasos (fase actual / cercana).
  granularidad    text          not null default 'grueso'
                    check (granularidad in ('grueso', 'fino')),
  notas           text,
  -- Enlace opcional a una tarea del hub (lo pone el Paso 3 al promover).
  tarea_id        uuid          references public.tareas(id) on delete set null,
  creado_en       timestamptz   not null default now(),
  actualizado_en  timestamptz   not null default now()
);

create index if not exists idx_arbol_nodos_proyecto
  on public.arbol_nodos (proyecto_id, parent_id, orden);

create index if not exists idx_arbol_nodos_tarea
  on public.arbol_nodos (tarea_id) where tarea_id is not null;

drop trigger if exists trg_arbol_nodos_actualizado on public.arbol_nodos;
create trigger trg_arbol_nodos_actualizado
  before update on public.arbol_nodos
  for each row execute function public.tocar_actualizado();

alter table public.arbol_nodos enable row level security;
