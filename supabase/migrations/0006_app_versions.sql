-- ============================================================================
-- Matix · Infra · Auto-actualización in-app
-- ----------------------------------------------------------------------------
-- Reemplaza Firebase App Distribution por un canal propio:
--   1. CI sube el APK release a un bucket público de Supabase Storage.
--   2. CI inserta una fila en `app_versions` con la URL pública,
--      el build_number (= GITHUB_RUN_NUMBER, monótono) y las notas.
--   3. El cerebro expone `GET /api/v1/version` que lee la fila más
--      reciente; la app la consulta al iniciar y se autoactualiza.
--
-- Comparación de versiones: por `build_number` (int), no por
-- version string. El string es para mostrarle al usuario en el
-- diálogo, no para decidir si hay update.
-- ============================================================================

create table public.app_versions (
  id            uuid        primary key default gen_random_uuid(),
  version       text        not null,             -- "1.0.0" del pubspec
  build_number  int         not null,             -- monótono; viene de GITHUB_RUN_NUMBER
  apk_url       text        not null,             -- URL pública en Supabase Storage
  notas         text        not null default '',  -- release notes (mensaje del commit)
  sha           text,                              -- commit sha que generó este APK
  creado_en     timestamptz not null default now()
);

-- Búsqueda típica: "última versión publicada" → necesitamos ORDER BY
-- build_number DESC LIMIT 1.
create index idx_app_versions_build_number
  on public.app_versions (build_number desc);

alter table public.app_versions enable row level security;

-- ============================================================================
-- Bucket público `apks` para el binario.
-- ----------------------------------------------------------------------------
-- Lo creamos vía la API de storage: insertar en `storage.buckets`.
-- `public = true` significa que cualquiera con la URL puede bajar el
-- archivo (no se requiere auth). Eso es lo que queremos para que la
-- app instale sin pasar credenciales al descargar.
--
-- Los APKs no son secretos: contienen una `MATIX_API_KEY` embebida
-- (la misma de --dart-define) que la app ya usa públicamente para
-- hablar con el cerebro; protegida por rate limit. Hospedar los APKs
-- en URL pública es estándar para apps Android distribuidas fuera
-- del Play Store (Firebase App Distribution, GitHub Releases, etc.
-- todos lo hacen así).
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('apks', 'apks', true, 104857600)  -- 100 MB cap por archivo
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit;

-- Política RLS: cualquiera puede LEER del bucket. Solo el service
-- role (CI) puede ESCRIBIR. (service_role omite RLS por definición,
-- así que no hace falta política de INSERT explícita.)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'apks_public_read'
  ) then
    create policy apks_public_read on storage.objects
      for select
      using (bucket_id = 'apks');
  end if;
end $$;
