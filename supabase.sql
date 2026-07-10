-- =========================
-- SOS La Victoria — Script SQL idempotente
-- Puede ejecutarse múltiples veces sin errores
-- =========================

-- Extensión necesaria para UUID
create extension if not exists "pgcrypto";

-- =========================
-- Tipos ENUM (con verificación previa)
-- =========================
do $$ begin
  if not exists (select 1 from pg_type where typname = 'estado_persona') then
    create type estado_persona as enum ('en_vivienda', 'evacuado', 'en_refugio');
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_type where typname = 'prioridad_necesidad') then
    create type prioridad_necesidad as enum ('alta', 'media', 'baja');
  end if;
end $$;

-- =========================
-- Tablas
-- =========================
create table if not exists refugios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  direccion text,
  latitud double precision,
  longitud double precision,
  capacidad integer not null default 0,
  ocupacion integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists personas (
  id uuid primary key default gen_random_uuid(),
  cedula text unique not null,
  sin_cedula boolean not null default false,
  nombres text not null,
  apellidos text not null,
  telefono text,
  sector text,
  direccion text,
  acompanantes integer not null default 0,
  estado estado_persona not null default 'en_vivienda',
  refugio_id uuid references refugios(id) on delete set null,
  nivel_afectacion text,
  observaciones text,
  created_at timestamptz not null default now()
);

-- Migración: agregar columna si no existe
do $$ begin
  alter table personas add column if not exists nivel_afectacion text;
end $$;

create table if not exists necesidades (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  prioridad prioridad_necesidad not null default 'media',
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists noticias (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  contenido text not null,
  created_at timestamptz not null default now()
);

create table if not exists solicitudes_sos (
  id uuid primary key default gen_random_uuid(),
  nombre text,
  ubicacion text,
  cantidad_personas integer,
  descripcion text,
  canal text check (canal in ('llamada','whatsapp','ubicacion')),
  atendido boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists configuracion (
  id integer primary key default 1,
  contador_visible boolean not null default true,
  whatsapp text,
  telefono text,
  nombre_refugio_principal text,
  refugio_principal_id uuid references refugios(id),
  constraint solo_una_fila check (id = 1)
);

-- =========================
-- Índices
-- =========================
create index if not exists idx_personas_cedula on personas(cedula);
create index if not exists idx_personas_estado on personas(estado);
create index if not exists idx_personas_refugio on personas(refugio_id);

-- =========================
-- Trigger: actualizar ocupación del refugio
-- =========================
create or replace function actualizar_ocupacion_refugio()
returns trigger as $$
begin
  if (TG_OP = 'UPDATE' and OLD.refugio_id is distinct from NEW.refugio_id) then
    if OLD.refugio_id is not null then
      update refugios set ocupacion = (
        select coalesce(sum(1 + acompanantes), 0) from personas
        where refugio_id = OLD.refugio_id and estado = 'en_refugio'
      ) where id = OLD.refugio_id;
    end if;
  end if;

  if NEW.refugio_id is not null then
    update refugios set ocupacion = (
      select coalesce(sum(1 + acompanantes), 0) from personas
      where refugio_id = NEW.refugio_id and estado = 'en_refugio'
    ) where id = NEW.refugio_id;
  end if;

  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_actualizar_ocupacion on personas;
create trigger trg_actualizar_ocupacion
after insert or update on personas
for each row execute function actualizar_ocupacion_refugio();

-- ========================
-- ROW LEVEL SECURITY (RLS)
-- ========================

alter table personas enable row level security;
alter table refugios enable row level security;
alter table necesidades enable row level security;
alter table noticias enable row level security;
alter table solicitudes_sos enable row level security;
alter table configuracion enable row level security;

-- Eliminar políticas existentes antes de recrearlas
do $$ declare
  pol record;
begin
  for pol in select policyname from pg_policies where tablename = 'personas' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on personas', pol.policyname);
  end loop;
  for pol in select policyname from pg_policies where tablename = 'refugios' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on refugios', pol.policyname);
  end loop;
  for pol in select policyname from pg_policies where tablename = 'necesidades' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on necesidades', pol.policyname);
  end loop;
  for pol in select policyname from pg_policies where tablename = 'noticias' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on noticias', pol.policyname);
  end loop;
  for pol in select policyname from pg_policies where tablename = 'solicitudes_sos' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on solicitudes_sos', pol.policyname);
  end loop;
  for pol in select policyname from pg_policies where tablename = 'configuracion' and schemaname = 'public'
  loop
    execute format('drop policy if exists %I on configuracion', pol.policyname);
  end loop;
end $$;

-- personas: público inserta, no select directo
create policy "publico_puede_insertar_personas"
on personas for insert
to anon
with check (true);

create policy "admin_acceso_total_personas"
on personas for all
to authenticated
using (true)
with check (true);

-- refugios, necesidades, noticias, configuracion: lectura pública, escritura admin
create policy "publico_lee_refugios" on refugios for select to anon using (true);
create policy "admin_escribe_refugios" on refugios for all to authenticated using (true) with check (true);

create policy "publico_lee_necesidades" on necesidades for select to anon using (true);
create policy "admin_escribe_necesidades" on necesidades for all to authenticated using (true) with check (true);

create policy "publico_lee_noticias" on noticias for select to anon using (true);
create policy "admin_escribe_noticias" on noticias for all to authenticated using (true) with check (true);

create policy "publico_lee_configuracion" on configuracion for select to anon using (true);
create policy "admin_escribe_configuracion" on configuracion for all to authenticated using (true) with check (true);

-- solicitudes_sos: público inserta, admin lee
create policy "publico_inserta_sos" on solicitudes_sos for insert to anon with check (true);
create policy "admin_lee_sos" on solicitudes_sos for all to authenticated using (true) with check (true);

-- ========================
-- FUNCIONES RPC PÚBLICAS
-- ========================

create or replace function buscar_persona(termino text)
returns table (
  nombres text,
  apellidos text,
  cedula text,
  estado estado_persona,
  refugio_nombre text,
  created_at timestamptz
)
language sql
security definer
as $$
  select p.nombres, p.apellidos, p.cedula, p.estado, r.nombre, p.created_at
  from personas p
  left join refugios r on r.id = p.refugio_id
  where p.cedula = termino
     or p.nombres ilike '%' || termino || '%'
     or p.apellidos ilike '%' || termino || '%'
  limit 20;
$$;

grant execute on function buscar_persona(text) to anon;

create or replace function existe_cedula(c text)
returns table (nombres text, apellidos text, estado estado_persona, created_at timestamptz)
language sql
security definer
as $$
  select nombres, apellidos, estado, created_at from personas where cedula = c limit 1;
$$;

grant execute on function existe_cedula(text) to anon;

create or replace function contador_personas()
returns integer
language sql
security definer
as $$
  select count(*)::integer from personas;
$$;

grant execute on function contador_personas() to anon;

-- ========================
-- DATOS SEMILLA (idempotentes)
-- ========================

insert into refugios (nombre, direccion, latitud, longitud, capacidad)
values ('Refugio Principal La Victoria', 'Calle Principal, La Victoria, Páez, Apure', 7.030329946303474, -71.43544897193883, 200)
on conflict (id) do nothing;

insert into necesidades (nombre, prioridad)
values
  ('Agua potable', 'alta'),
  ('Alimentos no perecederos', 'alta'),
  ('Medicamentos', 'alta'),
  ('Colchonetas', 'media'),
  ('Ropa', 'media'),
  ('Artículos de higiene personal', 'alta'),
  ('Pañales', 'media')
on conflict (id) do nothing;

insert into noticias (titulo, contenido)
values ('Centro de acopio habilitado en La Victoria', 'Se informa a la comunidad que el centro de acopio ubicado en la sede de Protección Civil está recibiendo donaciones de alimentos, agua, y artículos de primera necesidad. Horario: 8am - 4pm.')
on conflict (id) do nothing;

-- Insertar o actualizar configuracion
insert into configuracion (id, contador_visible) values (1, true)
on conflict (id) do nothing;

-- Vincular refugio principal (solo si no está ya configurado)
update configuracion
set
  nombre_refugio_principal = coalesce(nombre_refugio_principal, 'Refugio Principal La Victoria'),
  refugio_principal_id = coalesce(refugio_principal_id, (select id from refugios order by created_at limit 1)),
  whatsapp = coalesce(whatsapp, '+573002441066'),
  telefono = coalesce(telefono, '+573002441066')
where id = 1;
   