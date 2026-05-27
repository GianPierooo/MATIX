-- ============================================================================
-- Matix · Capa 2 Paso 5 · Borrado suave (papelera)
-- ----------------------------------------------------------------------------
-- Añade `eliminado_en` a las entidades que la app permite borrar desde la
-- UI o vía Matix: tareas, eventos, apuntes. Borrar deja de destruir; marca
-- la fila con `eliminado_en = now()`. Las vistas normales filtran por
-- `eliminado_en is null`; una vista "Papelera" muestra solo las que tienen
-- valor, con opción de restaurar (setear el campo a null otra vez) o de
-- vaciar permanentemente (DELETE real — solo manual desde la UI, nunca
-- una tool de Matix).
--
-- Proyectos NO se marca como eliminado: su ciclo de vida es
-- activo / aparcado / terminado. Aparcar y terminar ya son reversibles
-- (volver a activo). No tiene sentido añadir un cuarto estado "borrado".
-- Categorías, cursos, sesiones_clase, evaluaciones, cuadernos y
-- subtareas tampoco entran en la papelera: no son "documentos del
-- usuario" que un Matix conversando vaya a borrar por error.
-- ============================================================================

alter table public.tareas
  add column if not exists eliminado_en timestamptz;

alter table public.eventos
  add column if not exists eliminado_en timestamptz;

alter table public.apuntes
  add column if not exists eliminado_en timestamptz;

-- Índices parciales: aceleran las vistas normales ("solo no eliminadas")
-- sin desperdiciar espacio indexando filas que están en la papelera.
create index if not exists idx_tareas_no_eliminadas
  on public.tareas (creada_en desc)
  where eliminado_en is null;

create index if not exists idx_eventos_no_eliminados
  on public.eventos (inicia_en asc)
  where eliminado_en is null;

create index if not exists idx_apuntes_no_eliminados
  on public.apuntes (actualizado_en desc)
  where eliminado_en is null;

-- También: índices para listar la papelera por fecha de borrado.
create index if not exists idx_tareas_papelera
  on public.tareas (eliminado_en desc)
  where eliminado_en is not null;

create index if not exists idx_eventos_papelera
  on public.eventos (eliminado_en desc)
  where eliminado_en is not null;

create index if not exists idx_apuntes_papelera
  on public.apuntes (eliminado_en desc)
  where eliminado_en is not null;
