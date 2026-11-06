-- ════════════════════════════════════════════════════════════════════════════
-- Nails Atelier · base de datos en Supabase (PostgreSQL)
-- Pegar completo en Supabase → SQL Editor → Run. Se puede ejecutar más de una vez.
--
-- Seguridad:
--  · Las clientas (sin cuenta) solo pueden: ver servicios, profesionales y horarios ocupados
--    (sin nombres ni celulares), reservar, y consultar/cambiar/cancelar SU cita con código + celular.
--  · El salón (usuarios de la tabla admins) ve y gestiona todo, iniciando sesión.
--  · Dos citas de la misma profesional nunca se cruzan: lo impide una restricción de la base.
-- ════════════════════════════════════════════════════════════════════════════
create extension if not exists btree_gist;

create table if not exists settings (id text primary key default 'main', data jsonb not null default '{}');
create table if not exists services (
  id text primary key, name text not null, category text, duration int not null check (duration between 10 and 600),
  price numeric(10,2) not null default 0, buffer_before int not null default 0, buffer_after int not null default 0,
  color text, description text, active boolean not null default true, sort int not null default 0, demo boolean not null default false);
create table if not exists staff (
  id text primary key, name text not null, services text[] not null default '{}', schedule jsonb not null default '{}',
  active boolean not null default true, demo boolean not null default false);
create table if not exists timeoff (
  id text primary key, staff_id text not null references staff(id) on delete cascade, date date not null,
  start_min int not null, end_min int not null check (end_min > start_min), reason text);
create table if not exists bookings (
  id text primary key, code text not null unique, service_id text, service_name text not null, staff_id text not null references staff(id),
  staff_name text, date date not null, start_min int not null, end_min int not null, block_start int not null, block_end int not null,
  price numeric(10,2) not null default 0, client_name text not null, client_phone text not null check (client_phone ~ '^9\d{8}$'),
  client_email text, client_note text, status text not null default 'confirmada' check (status in ('confirmada','completada','cancelada','ausente')),
  source text not null default 'publico', cancel_reason text, history jsonb not null default '[]', demo boolean not null default false,
  created_at timestamptz not null default now(),
  -- Antisolape en la base: dos citas activas de la misma profesional no pueden cruzarse (incluye preparación y limpieza).
  constraint sin_cruces exclude using gist (staff_id with =, date with =, int4range(block_start, block_end) with &&) where (status <> 'cancelada'));
create index if not exists bookings_phone on bookings(client_phone);
create table if not exists admins (user_id uuid primary key references auth.users(id) on delete cascade);

create or replace function is_admin() returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from admins where user_id = auth.uid()) $$;

-- ───────── reglas de acceso (RLS) ─────────
alter table settings enable row level security;
alter table services enable row level security;
alter table staff enable row level security;
alter table timeoff enable row level security;
alter table bookings enable row level security;
alter table admins enable row level security;
drop policy if exists p_settings_read on settings;   create policy p_settings_read on settings for select using (true);
drop policy if exists p_settings_admin on settings;  create policy p_settings_admin on settings for all using (is_admin()) with check (is_admin());
drop policy if exists p_services_read on services;   create policy p_services_read on services for select using (active or is_admin());
drop policy if exists p_services_admin on services;  create policy p_services_admin on services for all using (is_admin()) with check (is_admin());
drop policy if exists p_staff_read on staff;         create policy p_staff_read on staff for select using (active or is_admin());
drop policy if exists p_staff_admin on staff;        create policy p_staff_admin on staff for all using (is_admin()) with check (is_admin());
drop policy if exists p_timeoff_admin on timeoff;    create policy p_timeoff_admin on timeoff for all using (is_admin()) with check (is_admin());
drop policy if exists p_bookings_admin on bookings;  create policy p_bookings_admin on bookings for all using (is_admin()) with check (is_admin());
drop policy if exists p_admins_self on admins;       create policy p_admins_self on admins for select using (user_id = auth.uid());
-- (sin políticas para el público en bookings ni timeoff: las clientas solo usan las funciones de abajo)

-- ───────── funciones públicas (validan todo en el servidor) ─────────
create or replace function lima_now() returns timestamp language sql stable as $$ select now() at time zone 'America/Lima' $$;

-- Horarios ocupados, sin datos personales.
create or replace function busy_blocks(p_from date, p_to date)
returns table(staff_id text, date date, block_start int, block_end int) language sql stable security definer set search_path = public as $$
  select b.staff_id, b.date, b.block_start, b.block_end from bookings b where b.status <> 'cancelada' and b.date between p_from and p_to
  union all
  select t.staff_id, t.date, t.start_min, t.end_min from timeoff t where t.date between p_from and p_to
$$;

-- ¿El bloque cae dentro del horario de la profesional ese día de la semana?
create or replace function in_schedule(p_staff text, p_date date, p_s int, p_e int) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff s, jsonb_array_elements(coalesce(s.schedule -> extract(dow from p_date)::int::text, '[]')) w
                 where s.id = p_staff and (w->>0)::int <= p_s and (w->>1)::int >= p_e)
$$;

create or replace function new_code() returns text language sql volatile as $$
  select 'C-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)) $$;

create or replace function book(p_service text, p_staff text, p_date date, p_start int, p_name text, p_phone text, p_email text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare sv services; cfg jsonb; st text; s0 int; e0 int; dur int; ln timestamp := lima_now(); b bookings; phone text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
        min_notice int; max_days int; cand text;
begin
  if length(phone) = 11 and left(phone, 2) = '51' then phone := substr(phone, 3); end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Escribe tu nombre.'; end if;
  if phone !~ '^9\d{8}$' then raise exception 'El celular debe tener 9 dígitos y empezar con 9.'; end if;
  if p_email is not null and p_email <> '' and p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'El correo no es válido.'; end if;
  select * into sv from services where id = p_service and active; if not found then raise exception 'Elige un servicio.'; end if;
  select data into cfg from settings where id = 'main'; cfg := coalesce(cfg, '{}');
  min_notice := coalesce((cfg->>'minNotice')::int, 120); max_days := coalesce((cfg->>'maxDays')::int, 30);
  dur := sv.duration; s0 := p_start - sv.buffer_before; e0 := p_start + dur + sv.buffer_after;
  if (p_date + make_interval(mins => p_start)) < ln + make_interval(mins => min_notice) then raise exception 'Ese horario ya no está disponible. Elige otro.'; end if;
  if p_date > (ln::date + max_days) then raise exception 'Todavía no se puede reservar para esa fecha.'; end if;
  -- límite anti-abuso: máximo 3 citas futuras activas por celular
  if not is_admin() and (select count(*) from bookings where client_phone = phone and status = 'confirmada' and date >= ln::date) >= 3 then
    raise exception 'Ya tienes 3 citas próximas. Para más, comunícate con el salón.'; end if;
  -- profesional: la elegida o, si es "cualquiera", la libre con menos citas ese día
  for cand in select s.id from staff s where s.active and p_service = any(s.services) and (p_staff is null or p_staff = '' or p_staff = 'any' or s.id = p_staff)
              order by (select count(*) from bookings x where x.staff_id = s.id and x.date = p_date and x.status <> 'cancelada'), s.name loop
    if in_schedule(cand, p_date, p_start, p_start + dur)
       and not exists (select 1 from bookings x where x.staff_id = cand and x.date = p_date and x.status <> 'cancelada' and int4range(x.block_start, x.block_end) && int4range(s0, e0))
       and not exists (select 1 from timeoff t where t.staff_id = cand and t.date = p_date and int4range(t.start_min, t.end_min) && int4range(s0, e0)) then
      st := cand; exit; end if;
  end loop;
  if st is null then raise exception 'Ese horario ya no está disponible. Elige otro.'; end if;
  begin
    insert into bookings (id, code, service_id, service_name, staff_id, staff_name, date, start_min, end_min, block_start, block_end, price, client_name, client_phone, client_email, client_note, source, history)
    values ('b' || replace(gen_random_uuid()::text, '-', ''), new_code(), sv.id, sv.name, st, (select name from staff where id = st), p_date, p_start, p_start + dur, s0, e0, sv.price,
            trim(p_name), phone, nullif(trim(coalesce(p_email, '')), ''), left(nullif(trim(coalesce(p_note, '')), ''), 300), case when is_admin() then 'panel' else 'publico' end,
            jsonb_build_array(jsonb_build_object('at', now(), 'what', 'Reservada', 'by', case when is_admin() then 'Salón' else 'Clienta' end)))
    returning * into b;
  exception when exclusion_violation then raise exception 'Ese horario se acaba de ocupar. Elige otro.';
  end;
  return jsonb_build_object('id', b.id, 'code', b.code, 'serviceName', b.service_name, 'staffName', b.staff_name, 'date', b.date, 'start', b.start_min, 'end', b.end_min, 'price', b.price, 'staffId', b.staff_id);
end $$;

-- La clienta consulta su cita con código + celular (no puede ver otras).
create or replace function my_booking(p_code text, p_phone text) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', id, 'code', code, 'serviceId', service_id, 'serviceName', service_name, 'staffId', staff_id, 'staffName', staff_name, 'date', date, 'start', start_min, 'end', end_min, 'price', price, 'status', status, 'blockStart', block_start, 'blockEnd', block_end)
  from bookings where code = upper(trim(p_code)) and client_phone = right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9) limit 1
$$;

create or replace function cancel_my_booking(p_code text, p_phone text) returns void language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  select * into b from bookings where code = upper(trim(p_code)) and client_phone = right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9) for update;
  if not found then raise exception 'No encontramos esa cita.'; end if;
  if b.status <> 'confirmada' then raise exception 'Esta cita ya no se puede cancelar.'; end if;
  if (b.date + make_interval(mins => b.start_min)) - lima_now() < interval '3 hours' then raise exception 'Faltan menos de 3 horas: comunícate con el salón.'; end if;
  update bookings set status = 'cancelada', cancel_reason = 'Cancelada por la clienta', history = history || jsonb_build_object('at', now(), 'what', 'Cancelada', 'by', 'Clienta') where id = b.id;
end $$;

-- Reprogramar: la clienta (código + celular) o el salón. Mueve la misma cita; la restricción impide cruces.
create or replace function reschedule_booking(p_code text, p_phone text, p_date date, p_start int) returns jsonb language plpgsql security definer set search_path = public as $$
declare b bookings; sv services; s0 int; e0 int; cfg jsonb;
begin
  select * into b from bookings where code = upper(trim(p_code)) and client_phone = right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 9) for update;
  if not found then raise exception 'No encontramos esa cita.'; end if;
  if b.status <> 'confirmada' then raise exception 'Esta cita ya no se puede cambiar.'; end if;
  if not is_admin() and (b.date + make_interval(mins => b.start_min)) - lima_now() < interval '3 hours' then raise exception 'Faltan menos de 3 horas: comunícate con el salón.'; end if;
  select * into sv from services where id = b.service_id; if not found then raise exception 'El servicio ya no existe.'; end if;
  select coalesce(data, '{}') into cfg from settings where id = 'main';
  if (p_date + make_interval(mins => p_start)) < lima_now() + make_interval(mins => coalesce((cfg->>'minNotice')::int, 120)) and not is_admin() then raise exception 'Ese horario ya no está disponible.'; end if;
  s0 := p_start - sv.buffer_before; e0 := p_start + sv.duration + sv.buffer_after;
  if not in_schedule(b.staff_id, p_date, p_start, p_start + sv.duration) then raise exception 'Ese horario está fuera del horario de atención.'; end if;
  if exists (select 1 from timeoff t where t.staff_id = b.staff_id and t.date = p_date and int4range(t.start_min, t.end_min) && int4range(s0, e0)) then raise exception 'Ese horario no está disponible.'; end if;
  begin
    update bookings set date = p_date, start_min = p_start, end_min = p_start + sv.duration, block_start = s0, block_end = e0,
      history = history || jsonb_build_object('at', now(), 'what', 'Reprogramada', 'by', case when is_admin() then 'Salón' else 'Clienta' end) where id = b.id;
  exception when exclusion_violation then raise exception 'Ese horario ya está ocupado. Elige otro.';
  end;
  return my_booking(b.code, b.client_phone);
end $$;

grant execute on function busy_blocks(date, date), book(text, text, date, int, text, text, text, text), my_booking(text, text), cancel_my_booking(text, text), reschedule_booking(text, text, date, int) to anon, authenticated;

insert into settings (id, data) values ('main', '{"name":"Nails Atelier"}') on conflict (id) do nothing;

-- Cuentas del salón por correo: al crearse un usuario con uno de estos correos, recibe acceso al panel.
create table if not exists admin_emails (email text primary key);
alter table admin_emails enable row level security;
insert into admin_emails (email) values ('mymtelecomunicacionessixseven@gmail.com'), ('m-infantes@hotmail.com') on conflict do nothing;
create or replace function auto_admin() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from admin_emails where lower(email) = lower(new.email)) then
    insert into admins (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;
revoke execute on function auto_admin() from anon, authenticated, public;
drop trigger if exists on_auth_user_auto_admin on auth.users;
create trigger on_auth_user_auto_admin after insert on auth.users for each row execute function auto_admin();
insert into admins (user_id) select id from auth.users where lower(email) in (select lower(email) from admin_emails) on conflict do nothing;
