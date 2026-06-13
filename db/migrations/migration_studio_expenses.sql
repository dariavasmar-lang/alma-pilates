-- ============================================================
-- STUDIO EXPENSES + CATS PERSISTENCE
-- Запустить в Supabase SQL Editor
-- ============================================================

-- Колонка для хранения категорий расходов студии
alter table studios add column if not exists expense_cats jsonb default '{}';

-- Таблица расходов студии (аренда, зарплата, оборудование и т.д.)
create table if not exists studio_expenses (
  id          uuid primary key default uuid_generate_v4(),
  created_at  timestamptz default now(),
  studio_id   uuid references studios(id) on delete cascade not null,
  cat         text not null default 'other',
  description text not null,
  amount      numeric(10,2) not null,
  date        date not null default current_date,
  recurring   boolean default false,
  freq        text default ''
);

alter table studio_expenses enable row level security;

create policy "Own studio expenses"
  on studio_expenses for all using (studio_id = my_studio_id());
