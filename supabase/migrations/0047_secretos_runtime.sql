-- Secretos de runtime que el cerebro lee como fallback de las variables de
-- entorno (caso de uso: credenciales de integraciones — Spotify — cuando no
-- hay acceso al dashboard de Railway para setear env vars).
--
-- SEGURIDAD: RLS habilitado SIN políticas → ni anon ni authenticated pueden
-- leer/escribir por PostgREST; solo el service role (que bypassa RLS) accede.
-- El cerebro usa el service role. Los VALORES nunca van al repo ni a los logs.

create table if not exists secretos_runtime (
  clave text primary key,
  valor text not null,
  actualizado_en timestamptz not null default now()
);

alter table secretos_runtime enable row level security;

comment on table secretos_runtime is
  'Credenciales de integraciones (fallback de env vars). Solo service role: RLS sin políticas.';
