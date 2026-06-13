-- ============================================================
-- ALMA PILATES — Финальная схема базы данных
-- Этот файл = единственный источник правды
-- Запускать ТОЛЬКО на чистой базе (drop + recreate)
-- На существующей базе — см. комментарии "ALTER (если уже есть)"
-- ============================================================

-- ─── РАСШИРЕНИЯ ─────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─── STUDIOS ────────────────────────────────────────────────
create table if not exists studios (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  name            text not null,
  subdomain       text unique not null,
  city            text default 'Limassol',
  phone           text,
  email           text,
  plan            text default 'business'
                  check (plan in ('starter','business','multi')),
  is_active       boolean default true,
  price_8         numeric(10,2) default 120,
  price_12        numeric(10,2) default 160,
  price_single    numeric(10,2) default 25,
  capacity        int default 4,
  revolut_api_key text,
  config          jsonb default '{}'
);

-- ─── ADMIN USERS ────────────────────────────────────────────
create table if not exists admin_users (
  user_id   uuid references auth.users(id) on delete cascade primary key,
  studio_id uuid references studios(id) on delete cascade not null,
  role      text default 'admin'
            check (role in ('owner','admin','trainer')),
  created_at timestamptz default now()
);

-- ─── CLIENTS ────────────────────────────────────────────────
create table if not exists clients (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) on delete cascade not null,
  user_id         uuid references auth.users(id),   -- привязка к auth
  full_name       text not null default '',
  phone           text,
  email           text,
  language        text default 'el' check (language in ('ru','el','en')),
  notes           text,
  is_active       boolean default true,
  gdpr_consent    boolean default false,
  gdpr_consent_at timestamptz
);

-- ALTER (если таблица уже есть, но нет user_id):
-- alter table clients add column if not exists user_id uuid references auth.users(id);

-- ─── SUBSCRIPTIONS ──────────────────────────────────────────
create table if not exists subscriptions (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) not null,
  client_id       uuid references clients(id) on delete cascade not null,
  type            text not null check (type in ('8','12','single')),
  total_classes   int not null,
  used_classes    int default 0,
  price           numeric(10,2) not null,
  paid_at         timestamptz,
  starts_at       date not null,
  expires_at      date,
  payment_method  text check (payment_method in ('revolut','cash','bank','card')),
  revolut_payment_id text,
  is_active       boolean default true
);

-- Представление с остатком занятий
create or replace view subscriptions_with_left as
  select *,
    (total_classes - used_classes) as classes_left,
    (expires_at < current_date and is_active) as is_expired
  from subscriptions;

-- ─── SCHEDULE SLOTS ─────────────────────────────────────────
create table if not exists schedule_slots (
  id          uuid primary key default uuid_generate_v4(),
  studio_id   uuid references studios(id) on delete cascade not null,
  day_of_week int not null check (day_of_week between 0 and 5), -- 0=Пн, 5=Сб
  start_time  time not null,
  end_time    time not null,
  capacity    int default 4,
  is_active   boolean default true,
  unique(studio_id, day_of_week, start_time)
);

-- ─── WAITLIST ───────────────────────────────────────────────
create table if not exists waitlist (
  id          uuid primary key default uuid_generate_v4(),
  created_at  timestamptz default now(),
  studio_id   uuid references studios(id) not null,
  client_id   uuid references clients(id) on delete cascade not null,
  slot_id     uuid references schedule_slots(id),
  class_date  date not null,
  unique(client_id, slot_id, class_date)
);

-- ─── BOOKINGS ───────────────────────────────────────────────
create table if not exists bookings (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) not null,
  client_id       uuid references clients(id) on delete cascade not null,
  slot_id         uuid references schedule_slots(id),
  subscription_id uuid references subscriptions(id),
  class_date      date not null,
  status          text default 'booked'
                  check (status in ('booked','attended','missed','cancelled')),
  is_trial        boolean default false,
  notes           text
);

-- ─── PAYMENTS ───────────────────────────────────────────────
create table if not exists payments (
  id                   uuid primary key default uuid_generate_v4(),
  created_at           timestamptz default now(),
  studio_id            uuid references studios(id) not null,
  client_id            uuid references clients(id),
  subscription_id      uuid references subscriptions(id),
  amount               numeric(10,2) not null,
  method               text check (method in ('revolut','cash','bank','card')),
  revolut_payment_id   text,
  revolut_payment_url  text,
  status               text default 'pending'
                       check (status in ('pending','paid','failed','refunded')),
  paid_at              timestamptz,
  notes                text
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table studios            enable row level security;
alter table clients            enable row level security;
alter table subscriptions      enable row level security;
alter table schedule_slots     enable row level security;
alter table waitlist           enable row level security;
alter table bookings           enable row level security;
alter table payments           enable row level security;

-- ─── ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ────────────────────────────────

-- Для admin: получить studio_id текущего пользователя
create or replace function my_studio_id()
returns uuid language sql stable as $$
  select studio_id from admin_users where user_id = auth.uid()
$$;

-- Для клиента: получить client_id текущего пользователя
create or replace function my_client_id()
returns uuid language sql stable security definer as $$
  select id from clients where user_id = auth.uid() limit 1
$$;

-- ─── ПОЛИТИКИ для АДМИНИСТРАТОРОВ ───────────────────────────

drop policy if exists "Own studio only"             on studios;
drop policy if exists "Own studio clients"          on clients;
drop policy if exists "Own studio subscriptions"    on subscriptions;
drop policy if exists "Own studio schedule"         on schedule_slots;
drop policy if exists "Own studio waitlist"         on waitlist;
drop policy if exists "Own studio bookings"         on bookings;
drop policy if exists "Own studio payments"         on payments;

create policy "Own studio only"
  on studios for all using (id = my_studio_id());

create policy "Own studio clients"
  on clients for all using (studio_id = my_studio_id());

create policy "Own studio subscriptions"
  on subscriptions for all using (studio_id = my_studio_id());

create policy "Own studio schedule"
  on schedule_slots for all using (studio_id = my_studio_id());

create policy "Own studio waitlist"
  on waitlist for all using (studio_id = my_studio_id());

create policy "Own studio bookings"
  on bookings for all using (studio_id = my_studio_id());

create policy "Own studio payments"
  on payments for all using (studio_id = my_studio_id());

-- ─── ПОЛИТИКИ для КЛИЕНТОВ (мобильное приложение) ───────────

drop policy if exists "Client can read own record"            on clients;
drop policy if exists "Client can update own record"          on clients;
drop policy if exists "Client can read own subscriptions"     on subscriptions;
drop policy if exists "Client can update own subscriptions"   on subscriptions;
drop policy if exists "Client can read own bookings"          on bookings;
drop policy if exists "Client can insert bookings"            on bookings;
drop policy if exists "Client can update own bookings"        on bookings;
drop policy if exists "Client can read own waitlist"          on waitlist;
drop policy if exists "Client can insert waitlist"            on waitlist;
drop policy if exists "Client can delete own waitlist"        on waitlist;
drop policy if exists "Anyone can read schedule"              on schedule_slots;

-- Клиент видит и обновляет свой профиль
create policy "Client can read own record"
  on clients for select using (user_id = auth.uid());

create policy "Client can update own record"
  on clients for update using (user_id = auth.uid());

-- Клиент видит свои подписки и обновляет used_classes
create policy "Client can read own subscriptions"
  on subscriptions for select using (client_id = my_client_id());

create policy "Client can update own subscriptions"
  on subscriptions for update using (client_id = my_client_id());

-- Клиент управляет своими бронированиями
create policy "Client can read own bookings"
  on bookings for select using (client_id = my_client_id());

create policy "Client can insert bookings"
  on bookings for insert with check (client_id = my_client_id());

create policy "Client can update own bookings"
  on bookings for update using (client_id = my_client_id());

-- Клиент управляет листом ожидания
create policy "Client can read own waitlist"
  on waitlist for select using (client_id = my_client_id());

create policy "Client can insert waitlist"
  on waitlist for insert with check (client_id = my_client_id());

create policy "Client can delete own waitlist"
  on waitlist for delete using (client_id = my_client_id());

-- Расписание видят все авторизованные пользователи
create policy "Anyone can read schedule"
  on schedule_slots for select using (true);

-- ─── ФУНКЦИЯ: привязать клиента при входе ───────────────────
create or replace function link_user_to_client(
  p_phone   text,
  p_user_id uuid,
  p_name    text,
  p_lang    text
)
returns json language plpgsql security definer as $$
declare
  v_client clients%rowtype;
begin
  select * into v_client
  from clients
  where phone = p_phone
    and studio_id = 'a0000000-0000-0000-0000-000000000001'
  limit 1;

  if found then
    if v_client.user_id is null then
      update clients set user_id = p_user_id where id = v_client.id;
      v_client.user_id := p_user_id;
    end if;
    return row_to_json(v_client);
  else
    insert into clients (studio_id, user_id, full_name, phone, language, gdpr_consent, gdpr_consent_at)
    values ('a0000000-0000-0000-0000-000000000001', p_user_id, p_name, p_phone, p_lang, true, now())
    returning * into v_client;
    return row_to_json(v_client);
  end if;
end;
$$;

-- ─── ФУНКЦИЯ: подсчёт занятых мест ──────────────────────────
create or replace function get_booking_counts(p_dates date[])
returns table(slot_id uuid, booking_count bigint)
language sql stable as $$
  select slot_id, count(*) as booking_count
  from bookings
  where class_date = any(p_dates)
    and status in ('booked','attended')
  group by slot_id
$$;

-- ============================================================
-- СТАРТОВЫЕ ДАННЫЕ (запускать только один раз на новой базе!)
-- ============================================================

-- Студия Alma Pilates
insert into studios (id, name, subdomain, city, phone, email, plan)
values (
  'a0000000-0000-0000-0000-000000000001',
  'Alma Pilates Studio', 'alma', 'Limassol, Cyprus',
  '96850466', 'info@almapilatesstudio.com', 'business'
) on conflict (id) do nothing;

-- Расписание (0=Пн, 5=Сб)
insert into schedule_slots (studio_id, day_of_week, start_time, end_time) values
  ('a0000000-0000-0000-0000-000000000001', 0, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 1, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 4, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 5, '09:30', '10:30'),
  ('a0000000-0000-0000-0000-000000000001', 5, '10:30', '11:30')
on conflict (studio_id, day_of_week, start_time) do nothing;
