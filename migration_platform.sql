-- ============================================================
-- PLATFORM CRM — Миграция
-- Запустить в Supabase SQL Editor
-- ============================================================

-- Платформенные администраторы (только Dasha)
create table if not exists platform_admins (
  user_id    uuid references auth.users(id) on delete cascade primary key,
  name       text,
  created_at timestamptz default now()
);

-- Доп. поля студий для платформенного CRM
alter table studios add column if not exists contact_name   text;
alter table studios add column if not exists whatsapp       text;
alter table studios add column if not exists instagram      text;
alter table studios add column if not exists source         text;   -- откуда пришли
alter table studios add column if not exists trial_ends_at  date;
alter table studios add column if not exists next_billing_at date;
alter table studios add column if not exists health         text default 'onboarding'
  check (health in ('onboarding','active','at-risk','churned'));
alter table studios add column if not exists platform_notes text;   -- внутренние заметки

-- Биллинг студий (оплата за платформу)
create table if not exists studio_billing (
  id         uuid primary key default uuid_generate_v4(),
  created_at timestamptz default now(),
  studio_id  uuid references studios(id) on delete cascade not null,
  period     text not null,           -- '2026-06'
  amount     numeric(10,2) not null,
  status     text default 'unpaid'
             check (status in ('trial','paid','unpaid','overdue')),
  paid_at    timestamptz,
  notes      text
);

-- Тикеты саппорта
create table if not exists support_tickets (
  id         uuid primary key default uuid_generate_v4(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  studio_id  uuid references studios(id) on delete cascade not null,
  title      text not null,
  status     text default 'open'
             check (status in ('open','in_progress','closed')),
  priority   text default 'normal'
             check (priority in ('low','normal','high'))
);

-- Сообщения в тикете
create table if not exists support_messages (
  id         uuid primary key default uuid_generate_v4(),
  created_at timestamptz default now(),
  ticket_id  uuid references support_tickets(id) on delete cascade not null,
  sender     text not null check (sender in ('studio','platform')),
  text       text not null
);

-- RLS
alter table platform_admins  enable row level security;
alter table studio_billing   enable row level security;
alter table support_tickets  enable row level security;
alter table support_messages enable row level security;

-- Платформенный админ видит всё
create or replace function is_platform_admin()
returns boolean language sql stable as $$
  select exists (select 1 from platform_admins where user_id = auth.uid())
$$;

create policy "Platform admin all studios"   on studios          for all using (is_platform_admin());
create policy "Platform admin billing"       on studio_billing   for all using (is_platform_admin());
create policy "Platform admin tickets"       on support_tickets  for all using (is_platform_admin());
create policy "Platform admin messages"      on support_messages for all using (is_platform_admin());
create policy "Platform admin self"          on platform_admins  for all using (user_id = auth.uid());

-- Студия видит только свои тикеты и сообщения
create policy "Studio own tickets"   on support_tickets  for all using (studio_id = my_studio_id());
create policy "Studio own messages"  on support_messages for all
  using (ticket_id in (select id from support_tickets where studio_id = my_studio_id()));
