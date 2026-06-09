-- ============================================================
-- PLATFORM EXPENSES — Миграция
-- Запустить в Supabase SQL Editor
-- ============================================================

create table if not exists platform_expenses (
  id          uuid primary key default uuid_generate_v4(),
  created_at  timestamptz default now(),
  date        date not null default current_date,
  amount      numeric(10,2) not null,
  category    text not null default 'other'
              check (category in ('hosting','domain','tools','design','marketing','tax','salary','other')),
  description text not null,
  notes       text,
  recurring   boolean default false,
  period      text   -- '2026-06' если привязан к месяцу
);

alter table platform_expenses enable row level security;

create policy "Platform admin expenses"
  on platform_expenses for all using (is_platform_admin());
