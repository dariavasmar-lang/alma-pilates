-- ============================================================
-- ALMA PILATES CRM — Multi-tenant Schema with RLS
-- Version 2.0 — Production ready
-- ============================================================

create extension if not exists "uuid-ossp";

-- ─── STUDIOS (one row per client studio) ────────────────────
create table studios (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  name            text not null,
  subdomain       text unique not null,        -- alma, crossfit-lim
  city            text default 'Limassol',
  phone           text,
  email           text,
  plan            text default 'business'
                  check (plan in ('starter','business','multi')),
  is_active       boolean default true,
  -- Pricing config
  price_8         numeric(10,2) default 120,
  price_12        numeric(10,2) default 160,
  price_single    numeric(10,2) default 25,
  capacity        int default 4,
  -- Revolut
  revolut_api_key text,
  -- UI config (colours, logo)
  config          jsonb default '{}'
);

-- ─── ADMIN USERS ────────────────────────────────────────────
-- Links Supabase Auth users to studios
create table admin_users (
  user_id         uuid references auth.users(id) on delete cascade primary key,
  studio_id       uuid references studios(id) on delete cascade not null,
  role            text default 'admin'
                  check (role in ('owner','admin','trainer')),
  created_at      timestamptz default now()
);

-- ─── CLIENTS ────────────────────────────────────────────────
create table clients (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) on delete cascade not null,
  full_name       text not null,
  phone           text,
  email           text,
  language        text default 'el' check (language in ('ru','el','en')),
  notes           text,
  is_active       boolean default true,
  gdpr_consent    boolean default false,
  gdpr_consent_at timestamptz
);

-- ─── SUBSCRIPTIONS ──────────────────────────────────────────
create table subscriptions (
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
  expires_at      date,                        -- start + 30 days
  payment_method  text check (payment_method in ('revolut','cash','bank','card')),
  revolut_payment_id text,
  is_active       boolean default true
);

-- Classes remaining (computed view)
create or replace view subscriptions_with_left as
  select *,
    (total_classes - used_classes) as classes_left,
    (expires_at < current_date and is_active) as is_expired
  from subscriptions;

-- ─── SCHEDULE SLOTS ─────────────────────────────────────────
create table schedule_slots (
  id              uuid primary key default uuid_generate_v4(),
  studio_id       uuid references studios(id) on delete cascade not null,
  day_of_week     int not null check (day_of_week between 0 and 6),
  start_time      time not null,
  end_time        time not null,
  capacity        int default 4,
  is_active       boolean default true,
  unique(studio_id, day_of_week, start_time)
);

-- ─── CANCELLATIONS ──────────────────────────────────────────
create table cancellations (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) on delete cascade not null,
  cancelled_date  date not null,
  end_date        date,                        -- for vacation ranges
  slot_time       time,                        -- null = entire day
  type            text default 'all'
                  check (type in ('all','slot','holiday','vacation')),
  reason          text,
  name            text
);

-- ─── BOOKINGS ───────────────────────────────────────────────
create table bookings (
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
create table payments (
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

-- ─── EXPENSE CATEGORIES ─────────────────────────────────────
create table expense_categories (
  id          uuid primary key default uuid_generate_v4(),
  studio_id   uuid references studios(id) on delete cascade not null,
  name        text not null,
  icon        text,
  color       text,
  sort_order  int default 0
);

-- ─── EXPENSES ───────────────────────────────────────────────
create table expenses (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz default now(),
  studio_id       uuid references studios(id) on delete cascade not null,
  category_id     uuid references expense_categories(id),
  description     text not null,
  amount          numeric(10,2) not null,
  expense_date    date not null,
  is_recurring    boolean default false,
  recurrence      text check (recurrence in ('monthly','weekly')),
  payment_method  text,
  notes           text
);

-- ─── AUDIT LOG ──────────────────────────────────────────────
-- Every important action is logged — who, when, what
create table audit_log (
  id          uuid primary key default uuid_generate_v4(),
  created_at  timestamptz default now(),
  studio_id   uuid references studios(id),
  user_id     uuid references auth.users(id),
  action      text not null,     -- 'client.created', 'payment.added' etc
  entity_type text,              -- 'client', 'payment', 'subscription'
  entity_id   uuid,
  old_data    jsonb,
  new_data    jsonb
);

-- ============================================================
-- ROW LEVEL SECURITY — The most important part
-- ============================================================

-- Enable RLS on every sensitive table
alter table studios            enable row level security;
alter table clients            enable row level security;
alter table subscriptions      enable row level security;
alter table schedule_slots     enable row level security;
alter table cancellations      enable row level security;
alter table bookings           enable row level security;
alter table payments           enable row level security;
alter table expense_categories enable row level security;
alter table expenses           enable row level security;
alter table audit_log          enable row level security;

-- Helper function: get current user's studio_id
create or replace function my_studio_id()
returns uuid
language sql stable
as $$
  select studio_id from admin_users where user_id = auth.uid()
$$;

-- ─── POLICIES ───────────────────────────────────────────────
-- Pattern: each table only returns rows matching current user's studio

-- Studios: can only see your own studio
create policy "Own studio only"
  on studios for all
  using (id = my_studio_id());

-- Clients: only your studio's clients
create policy "Own studio clients"
  on clients for all
  using (studio_id = my_studio_id());

-- Subscriptions: only your studio's subscriptions
create policy "Own studio subscriptions"
  on subscriptions for all
  using (studio_id = my_studio_id());

-- Schedule: only your studio's schedule
create policy "Own studio schedule"
  on schedule_slots for all
  using (studio_id = my_studio_id());

-- Cancellations: only your studio's
create policy "Own studio cancellations"
  on cancellations for all
  using (studio_id = my_studio_id());

-- Bookings: only your studio's bookings
create policy "Own studio bookings"
  on bookings for all
  using (studio_id = my_studio_id());

-- Payments: only your studio's payments
create policy "Own studio payments"
  on payments for all
  using (studio_id = my_studio_id());

-- Expense categories: only your studio's
create policy "Own studio expense categories"
  on expense_categories for all
  using (studio_id = my_studio_id());

-- Expenses: only your studio's expenses
create policy "Own studio expenses"
  on expenses for all
  using (studio_id = my_studio_id());

-- Audit log: read own studio's log
create policy "Own studio audit log"
  on audit_log for select
  using (studio_id = my_studio_id());

-- ============================================================
-- SEED DATA for Alma Pilates Studio
-- ============================================================

-- Insert Alma Pilates studio
insert into studios (id, name, subdomain, city, phone, email, plan)
values (
  'a0000000-0000-0000-0000-000000000001',
  'Alma Pilates Studio',
  'alma',
  'Limassol, Cyprus',
  '96850466',
  'info@almapilatesstudio.com',
  'business'
);

-- Default schedule (from Instagram @almastudiopilates)
insert into schedule_slots (studio_id, day_of_week, start_time, end_time) values
  -- Monday
  ('a0000000-0000-0000-0000-000000000001', 0, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '19:30', '20:30'),
  -- Tuesday
  ('a0000000-0000-0000-0000-000000000001', 1, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 1, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '19:30', '20:30'),
  -- Wednesday
  ('a0000000-0000-0000-0000-000000000001', 2, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '19:30', '20:30'),
  -- Thursday
  ('a0000000-0000-0000-0000-000000000001', 3, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '19:30', '20:30'),
  -- Friday
  ('a0000000-0000-0000-0000-000000000001', 4, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 4, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '19:30', '20:30'),
  -- Saturday
  ('a0000000-0000-0000-0000-000000000001', 5, '09:30', '10:30'),
  ('a0000000-0000-0000-0000-000000000001', 5, '10:30', '11:30');

-- Default expense categories for Alma
insert into expense_categories (studio_id, name, icon, color, sort_order) values
  ('a0000000-0000-0000-0000-000000000001', 'Rent / Ενοίκιο',        '🏢', '#E24B4A', 1),
  ('a0000000-0000-0000-0000-000000000001', 'Salary / Μισθός',       '👤', '#EF9F27', 2),
  ('a0000000-0000-0000-0000-000000000001', 'Equipment / Εξοπλισμός','🏋️', '#378ADD', 3),
  ('a0000000-0000-0000-0000-000000000001', 'Utilities / Κοινόχρηστα','💡', '#1D9E75', 4),
  ('a0000000-0000-0000-0000-000000000001', 'Marketing / Μάρκετινγκ','📣', '#7B6EF6', 5),
  ('a0000000-0000-0000-0000-000000000001', 'Other / Άλλα',          '📦', '#8E8E93', 6);
