# sos-la-victoria

# SOS La Victoria — Documento Maestro de Construcción

### Guía paso a paso para que una IA (o desarrollador) implemente la aplicación completa

**Versión:** 1.0
**Fecha:** Julio 2026
**Objetivo de este documento:** ser la única fuente de verdad. Contiene arquitectura, esquema de base de datos, políticas de seguridad, estructura de carpetas, y una secuencia de fases ejecutables de principio a fin, sin ambigüedad.

---

## 0. Cómo usar este documento (instrucciones para la IA ejecutora)

1. Ejecuta las fases **en orden**. No saltes de la Fase 2 a la Fase 4 sin completar la 3.
2. Cada fase tiene: **objetivo**, **entregables**, **pasos concretos** y **criterio de "hecho"**.
3. Al terminar cada fase, verifica el criterio de "hecho" antes de continuar.
4. No inventes campos, tablas o rutas que no estén aquí. Si falta algo, agrégalo a este documento primero, no lo improvises en el código.
5. Prioriza siempre: **funciona en móvil → es rápido → es simple**, en ese orden, sobre cualquier mejora estética.

---

## 1. Resumen del producto

Aplicación web (PWA) para registrar y consultar personas afectadas por el desbordamiento del río Arauca en La Victoria, parroquia Urdaneta, municipio Páez, estado Apure, Venezuela.

**Usuarios:**

- **Público general / voluntarios**: registran personas, consultan registros, ven refugios/necesidades/noticias, usan el botón SOS. No requieren cuenta.
- **Administrador**: gestiona personas, refugios, necesidades y noticias desde un panel protegido con login.

**No-objetivos de la v1 (explícitamente fuera de alcance):**

- Registro de grupos familiares vinculados.
- Fotos de zonas afectadas.
- Exportación a Excel/CSV desde la UI (el backup automatizado es distinto, ver Fase 8).
- Historial de cambios por registro.
- Mapa de viviendas afectadas.

---

## 2. Arquitectura y stack

| Capa         | Tecnología                                           | Notas                                                           |
| ------------ | ---------------------------------------------------- | --------------------------------------------------------------- |
| Frontend     | Astro + TypeScript + TailwindCSS                     | Server-rendered donde se pueda, islas de interactividad mínimas |
| Mapa         | Leaflet + OpenStreetMap                              | Sin API keys de pago                                            |
| Backend / DB | Supabase (Postgres + Auth + Realtime)                | Free tier                                                       |
| Hosting      | Vercel (Hobby)                                       | Astro adapter para Vercel                                       |
| PWA          | `@vite-pwa/astro` o manifest + service worker manual | Instalable, cache de assets estáticos                           |

**Restricciones de infraestructura (free tier) que el código DEBE respetar:**

- No usar Supabase Realtime en páginas públicas de alto tráfico (inicio, refugios). Usar `fetch` con polling cada 30–60s en su lugar.
- Realtime solo permitido en `/admin/*`.
- Toda tabla con búsquedas frecuentes debe tener índice (ver Fase 3).
- No hacer `select *` en el cliente para tablas con datos sensibles; seleccionar columnas explícitas.

---

## 3. Modelo de datos (SQL completo)

Ejecutar en el SQL editor de Supabase, en este orden.

```sql
-- Extensión necesaria para UUID
create extension if not exists "pgcrypto";

-- =========================
-- Tabla: refugios
-- =========================
create table refugios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  direccion text,
  latitud double precision,
  longitud double precision,
  capacidad integer not null default 0,
  ocupacion integer not null default 0,
  created_at timestamptz not null default now()
);

-- =========================
-- Tabla: personas
-- =========================
create type estado_persona as enum ('en_vivienda', 'evacuado', 'en_refugio');

create table personas (
  id uuid primary key default gen_random_uuid(),
  cedula text unique not null,
  sin_cedula boolean not null default false, -- true si se registró sin cédula válida
  nombres text not null,
  apellidos text not null,
  telefono text,
  sector text,
  direccion text,
  acompanantes integer not null default 0,
  estado estado_persona not null default 'en_vivienda',
  refugio_id uuid references refugios(id) on delete set null,
  observaciones text,
  created_at timestamptz not null default now()
);

create index idx_personas_cedula on personas(cedula);
create index idx_personas_estado on personas(estado);
create index idx_personas_refugio on personas(refugio_id);

-- =========================
-- Tabla: necesidades
-- =========================
create type prioridad_necesidad as enum ('alta', 'media', 'baja');

create table necesidades (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  prioridad prioridad_necesidad not null default 'media',
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- =========================
-- Tabla: noticias
-- =========================
create table noticias (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  contenido text not null,
  created_at timestamptz not null default now()
);

-- =========================
-- Tabla: solicitudes_sos
-- =========================
create table solicitudes_sos (
  id uuid primary key default gen_random_uuid(),
  nombre text,
  ubicacion text,
  cantidad_personas integer,
  descripcion text,
  canal text check (canal in ('llamada','whatsapp','ubicacion')),
  atendido boolean not null default false,
  created_at timestamptz not null default now()
);

-- =========================
-- Tabla: configuracion (fila única)
-- =========================
create table configuracion (
  id integer primary key default 1,
  contador_visible boolean not null default true,
  whatsapp text,
  telefono text,
  nombre_refugio_principal text,
  refugio_principal_id uuid references refugios(id),
  constraint solo_una_fila check (id = 1)
);

insert into configuracion (id, contador_visible) values (1, true);
```

**Trigger para mantener sincronizada la ocupación del refugio:**

```sql
create or replace function actualizar_ocupacion_refugio()
returns trigger as $$
begin
  -- Recalcular ocupación del refugio afectado (anterior y nuevo, si cambió)
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

create trigger trg_actualizar_ocupacion
after insert or update on personas
for each row execute function actualizar_ocupacion_refugio();
```

**Criterio de "hecho" Fase 3:** las 6 tablas existen, el enum se aplica, los índices están creados, el trigger de ocupación funciona (probar insertando una persona con `estado='en_refugio'` y un `refugio_id` válido, y verificar que `refugios.ocupacion` se actualiza).

---

## 4. Seguridad: Row Level Security (RLS) — OBLIGATORIO

Sin esto, cualquier persona con las claves públicas del cliente puede leer o borrar toda la tabla `personas`. Esto es no negociable dado que se manejan cédulas y ubicaciones de personas vulnerables.

```sql
-- Activar RLS en todas las tablas
alter table personas enable row level security;
alter table refugios enable row level security;
alter table necesidades enable row level security;
alter table noticias enable row level security;
alter table solicitudes_sos enable row level security;
alter table configuracion enable row level security;

-- personas: el público puede INSERTAR (registrarse) y solo puede
-- consultar mediante una función controlada (ver Fase 5), no select directo.
create policy "publico_puede_insertar_personas"
on personas for insert
to anon
with check (true);

-- El público NO puede hacer select directo a personas (se hace vía RPC segura).
-- Los admins autenticados sí pueden hacer todo.
create policy "admin_acceso_total_personas"
on personas for all
to authenticated
using (true)
with check (true);

-- refugios, necesidades, noticias, configuracion: lectura pública, escritura solo admin
create policy "publico_lee_refugios" on refugios for select to anon using (true);
create policy "admin_escribe_refugios" on refugios for all to authenticated using (true) with check (true);

create policy "publico_lee_necesidades" on necesidades for select to anon using (true);
create policy "admin_escribe_necesidades" on necesidades for all to authenticated using (true) with check (true);

create policy "publico_lee_noticias" on noticias for select to anon using (true);
create policy "admin_escribe_noticias" on noticias for all to authenticated using (true) with check (true);

create policy "publico_lee_configuracion" on configuracion for select to anon using (true);
create policy "admin_escribe_configuracion" on configuracion for all to authenticated using (true) with check (true);

-- solicitudes_sos: el público puede insertar, solo admin puede leer/listar
create policy "publico_inserta_sos" on solicitudes_sos for insert to anon with check (true);
create policy "admin_lee_sos" on solicitudes_sos for all to authenticated using (true) with check (true);
```

**Función RPC para consulta segura de personas (evita exponer la tabla completa):**

```sql
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
```

**Criterio de "hecho" Fase 4:** con la clave `anon`, un `select * from personas` debe fallar o devolver vacío; `buscar_persona('18456321')` debe funcionar; con un usuario autenticado (admin), todo el CRUD funciona.

---

## 5. Estructura de carpetas del proyecto

```
sos-la-victoria/
├── src/
│   ├── components/
│   │   ├── Header.astro
│   │   ├── SOSButton.astro
│   │   ├── ContadorPersonas.astro       (polling, no realtime)
│   │   ├── TarjetaRefugio.astro
│   │   ├── MapaLeaflet.astro
│   │   ├── ListaNecesidades.astro
│   │   ├── ListaNoticias.astro
│   │   └── admin/
│   │       ├── DashboardCard.astro
│   │       ├── TablaPersonas.tsx        (isla interactiva)
│   │       └── FormRefugio.tsx
│   ├── layouts/
│   │   ├── LayoutPublico.astro
│   │   └── LayoutAdmin.astro
│   ├── pages/
│   │   ├── index.astro                  # Pantalla principal
│   │   ├── registrar.astro              # Registrar persona
│   │   ├── consultar.astro              # Consultar persona
│   │   ├── refugios.astro
│   │   ├── noticias.astro
│   │   ├── emergencias.astro            # Números de emergencia
│   │   ├── acerca-de.astro
│   │   ├── admin/
│   │   │   ├── login.astro
│   │   │   ├── index.astro              # Dashboard
│   │   │   ├── personas.astro
│   │   │   ├── refugios.astro
│   │   │   ├── necesidades.astro
│   │   │   ├── noticias.astro
│   │   │   └── configuracion.astro
│   │   └── api/
│   │       ├── contador.ts              # GET conteo (usado por polling)
│   │       └── sos.ts                   # POST registrar solicitud SOS
│   ├── lib/
│   │   ├── supabaseClient.ts            # cliente anon (browser)
│   │   ├── supabaseAdmin.ts             # cliente con service_role (solo server)
│   │   └── validaciones.ts
│   └── styles/
│       └── global.css
├── public/
│   ├── manifest.json
│   ├── icons/
│   └── sw.js
├── astro.config.mjs
├── tailwind.config.mjs
├── .env.example
└── package.json
```

**Criterio de "hecho" Fase 5:** el proyecto Astro corre localmente con `npm run dev`, la estructura de carpetas existe (vacía o con stubs), Tailwind está configurado.

---

## 6. Variables de entorno

`.env.example`:

```
PUBLIC_SUPABASE_URL=
PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=   # NUNCA exponer al cliente, solo uso server-side en Vercel
```

Reglas:

- `PUBLIC_SUPABASE_ANON_KEY` es la única clave usada en componentes de cliente/páginas públicas.
- `SUPABASE_SERVICE_ROLE_KEY` solo se usa en funciones server-side de Astro (endpoints `/api/*` si se necesitan operaciones privilegiadas) o en el cron de backup. Jamás en código que llegue al navegador.

---

## 7. Fases de implementación

### Fase 1 — Setup del proyecto

1. `npm create astro@latest sos-la-victoria` (plantilla mínima, TypeScript strict).
2. Agregar integración de Tailwind: `npx astro add tailwind`.
3. Agregar adapter de Vercel: `npx astro add vercel`.
4. Instalar `@supabase/supabase-js`.
5. Crear `src/lib/supabaseClient.ts` con el cliente `anon`.
6. Configurar `.env` local con las credenciales del proyecto Supabase creado en el dashboard.

**Hecho cuando:** `npm run dev` levanta una página en blanco sin errores y el cliente de Supabase se importa sin fallar.

---

### Fase 2 — Base de datos

1. Crear proyecto en Supabase (free tier).
2. Ejecutar todo el SQL de la Sección 3 (tablas + trigger).
3. Ejecutar todo el SQL de la Sección 4 (RLS + funciones RPC).
4. Insertar datos semilla de prueba: 1 refugio, 2–3 necesidades, 1 noticia.

**Hecho cuando:** puedes hacer `select * from refugios` desde el SQL editor y ver la fila sembrada; las políticas RLS están activas (`select relrowsecurity from pg_class where relname='personas'` devuelve `true`).

---

### Fase 3 — Layout y navegación pública

1. `LayoutPublico.astro`: incluye `Header.astro` (☰ menú, logo centrado, botón 🚨 SOS) y `SOSButton.astro` (modal/sheet con Llamar / WhatsApp / Compartir ubicación).
2. Menú lateral (☰) con los 7 links de la Sección "Menú" original.
3. Botón SOS: al pulsar, abre `wa.me/<numero>?text=<mensaje precargado>` y también hace `POST /api/sos` para registrar la solicitud en `solicitudes_sos`.

**Hecho cuando:** la navegación entre las páginas stub funciona, el botón SOS abre WhatsApp con el mensaje precargado y crea una fila en `solicitudes_sos`.

---

**Refugio**
7.030327, -71.435489
La Victoria, Apure, Venezuela
Casa de la Cultura
**Proteccion civil la victoria**
La Victoria, Apure, Venezuela
7.030880, -71.436042
### Fase 4 — Pantalla principal (`index.astro`)

Construir en este orden exacto (de arriba hacia abajo):

1. Logo + "SOS LA VICTORIA".
2. `ContadorPersonas.astro`: hace `fetch('/api/contador')` al cargar y luego cada 45 segundos (`setInterval`); el endpoint llama a la función RPC `contador_personas()`.
3. Botón "Registrar Persona" → link a `/registrar`.
4. Botón "Consultar Persona" → link a `/consultar`.
5. `TarjetaRefugio.astro`: trae el refugio marcado como principal en `configuracion.refugio_principal_id` vía `select` público a `refugios` (permitido por RLS).
6. `MapaLeaflet.astro`: un solo marcador con la lat/lng del refugio principal; al hacer click abre `https://www.google.com/maps?q=<lat>,<lng>`.
7. `ListaNecesidades.astro`: lee `necesidades where activo = true` ordenadas por prioridad, con emoji según prioridad (🔴 alta, 🟡 media, 🟢 baja).
8. `ListaNoticias.astro`: últimas 5 de `noticias` ordenadas por `created_at desc`.
9. Footer con enlaces institucionales y "Última actualización: {fecha del registro más reciente en personas}".

**Hecho cuando:** la pantalla principal carga en menos de 2s en simulación 3G (Lighthouse), todos los bloques muestran datos reales de Supabase.

---

### Fase 5 — Registrar persona (`registrar.astro`)

1. Formulario con los campos de la Sección "Registro" del documento original (cédula y nombres/apellidos/estado obligatorios).
2. Checkbox "No tiene cédula a mano" → si se marca, `sin_cedula = true` y se genera un identificador temporal (`SINCED-<timestamp>`) en el campo `cedula` para no romper el `UNIQUE`; se marca visualmente para revisión del admin.
3. Al perder foco el campo cédula (`onBlur`), llamar a `existe_cedula(cedula)`:
   - Si devuelve fila → mostrar aviso "Esta persona ya fue registrada" con nombre/estado/fecha, deshabilitar envío.
   - Si no devuelve nada → permitir continuar.
4. Al enviar: `insert` en `personas` usando el cliente `anon` (permitido por policy `publico_puede_insertar_personas`).
5. **Resiliencia offline:** antes de enviar, guardar el payload en `localStorage` bajo una cola `registros_pendientes`. Si el `insert` tiene éxito, remover de la cola. Si falla (sin conexión), dejarlo en cola y reintentar automáticamente cuando vuelva `navigator.onLine`.
6. Mostrar confirmación clara tras el registro exitoso ("Persona registrada correctamente") y limpiar el formulario.

**Hecho cuando:** registrar una cédula nueva funciona, registrar una cédula repetida se bloquea con el aviso correcto, y desconectando la red durante el envío el registro queda en cola y se sincroniza al reconectar.

---

### Fase 6 — Consultar persona (`consultar.astro`)

1. Input de búsqueda + tabs/select: Cédula / Nombre / Apellido (o un solo campo que busque en los tres, más simple).
2. Llamar a `buscar_persona(termino)` vía RPC.
3. Mostrar tarjetas de resultado con: nombre completo, cédula, estado, refugio (si aplica), fecha.
4. Estado vacío claro: "No se encontraron registros con ese criterio."

**Hecho cuando:** buscar por cédula exacta, por nombre parcial y por apellido parcial devuelven resultados correctos y el estado vacío se ve bien.

---

### Fase 7 — Refugios, Noticias, Emergencias, Acerca de

1. `/refugios`: listado de todos los refugios (`select` público), cada tarjeta con nombre, ocupación/capacidad, botón "Ver mapa".
2. `/noticias`: listado completo paginado (20 por página) de `noticias`.
3. `/emergencias`: números fijos (Protección Civil, Bomberos, Alcaldía) — pueden venir hardcodeados o de `configuracion` si se agregan campos.
4. `/acerca-de`: texto estático explicando el propósito del proyecto.

**Hecho cuando:** las 4 páginas renderizan datos reales o contenido estático según corresponda.

---

### Fase 8 — Panel de administrador

1. `/admin/login.astro`: form de correo/contraseña usando `supabase.auth.signInWithPassword`.
2. Middleware/guard: todas las rutas bajo `/admin/*` (excepto `/admin/login`) deben verificar sesión activa (cookie de Supabase Auth) en el server de Astro; si no hay sesión, redirigir a `/admin/login`.
3. `/admin/index.astro` (Dashboard): 4 tarjetas con conteos (`personas`, `refugios`, `noticias`, `solicitudes_sos` sin atender) — aquí sí se puede usar Realtime porque el tráfico admin es bajo.
4. `/admin/personas.astro`: tabla con búsqueda, editar estado/refugio, eliminar (con confirmación).
5. `/admin/refugios.astro`: CRUD completo (nombre, dirección, lat/lng, capacidad; ocupación es de solo lectura porque la calcula el trigger).
6. `/admin/necesidades.astro`: CRUD + cambio de prioridad.
7. `/admin/noticias.astro`: CRUD.
8. `/admin/configuracion.astro`: editar WhatsApp, teléfono, refugio principal, visibilidad del contador.

**Hecho cuando:** un admin puede loguearse, ver el dashboard con datos en vivo, y hacer CRUD completo en las 4 secciones; un usuario no autenticado no puede acceder a ninguna ruta `/admin/*` salvo login.

---

### Fase 9 — PWA

1. `public/manifest.json`: nombre, íconos (192px y 512px), `display: standalone`, tema de color azul.
2. Service worker básico: cachear shell de la app y assets estáticos (network-first para datos, cache-first para estáticos).
3. Verificar instalabilidad con Lighthouse (PWA score).

**Hecho cuando:** Lighthouse marca la app como instalable y funciona (shell) sin conexión tras la primera visita.

---

### Fase 10 — Backup automatizado (crítico, no opcional)

1. Crear un Vercel Cron Job (`vercel.json` → `crons`) que corra diario, ej. `0 6 * * *`.
2. Endpoint `/api/backup.ts` (protegido, solo invocable por el cron o con un secreto): usa `SUPABASE_SERVICE_ROLE_KEY` para exportar `personas`, `refugios`, `noticias` a JSON.
3. Subir el JSON a un repositorio privado de GitHub (vía API de GitHub) o a un bucket de almacenamiento gratuito.

**Hecho cuando:** ejecutar manualmente el endpoint de backup produce un archivo con los datos actuales y se almacena fuera de Supabase.

---

### Fase 11 — Despliegue

1. Conectar el repositorio a Vercel.
2. Configurar las 3 variables de entorno en el dashboard de Vercel (Production + Preview).
3. Confirmar el adapter `@astrojs/vercel` en `astro.config.mjs`.
4. Deploy y verificar: pantalla principal, registro, consulta y login admin funcionando en producción.
5. Configurar dominio (propio o `*.vercel.app`).

**Hecho cuando:** la URL de producción funciona de punta a punta, incluyendo el cron de backup activo.

---

### Fase 12 — QA final antes de publicar

Checklist obligatorio:

- [ ] Registrar la misma cédula dos veces → bloqueado correctamente.
- [ ] Registrar sin conexión → queda en cola y sincroniza al reconectar.
- [ ] `select * from personas` con clave `anon` → vacío o error (RLS activo).
- [ ] Botón SOS → abre WhatsApp Y guarda en `solicitudes_sos`.
- [ ] Contador principal usa polling, no Realtime (verificar en Network tab que no hay WebSocket abierto en `/`).
- [ ] Admin no autenticado no puede entrar a `/admin/personas`.
- [ ] Lighthouse: PWA instalable, carga < 2s en 3G simulado.
- [ ] Backup manual ejecutado y verificado al menos una vez.
- [ ] Ocupación de refugio se actualiza sola al cambiar el estado de una persona a "en_refugio".

---

## 8. Consideraciones de privacidad (aplican durante todo el desarrollo)

- Los datos de `personas` (cédula, dirección, teléfono) son sensibles. Nunca loguear estos campos en `console.log` en producción.
- El acceso de admin debe limitarse a las personas estrictamente necesarias (Protección Civil / coordinación), no repartir credenciales ampliamente.
- Definir de antemano (fuera de este documento técnico, a nivel organizativo) cuánto tiempo se conservarán los datos tras finalizar la emergencia y quién es responsable de eliminarlos.

---

## 9. Roadmap post-MVP (no implementar ahora)

- Registro de grupos familiares vinculados.
- Fotografías de zonas afectadas.
- Múltiples refugios con estadísticas comparativas.
- Exportación CSV/Excel desde la UI de admin.
- Filtros avanzados por sector/estado en `/admin/personas`.
- Historial de cambios (audit log) por registro.
- Mapa de viviendas afectadas (no solo refugios).
- Sincronización offline completa (más allá de la cola de registro de la Fase 5).

---

**Fin del documento maestro.** Cualquier decisión de implementación no cubierta aquí debe resolverse priorizando: móvil → rápido → simple → seguro, en ese orden, y debe añadirse a este documento antes de codificarse.
