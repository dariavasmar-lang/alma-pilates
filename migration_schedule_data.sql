-- ============================================================
-- ALMA PILATES — Миграция: доп. занятия, отмены, названия слотов
-- Запустить в Supabase SQL Editor
-- ============================================================

-- Одноразовые доп. занятия (добавленные вручную)
create table if not exists extra_classes (
  id         uuid primary key default uuid_generate_v4(),
  created_at timestamptz default now(),
  studio_id  uuid references studios(id) on delete cascade not null,
  class_date date not null,
  start_time text not null,  -- 'HH:MM'
  name       text default '',
  is_active  boolean default true
);

-- Отмены: слот / весь день / праздник / отпуск
create table if not exists schedule_cancellations (
  id         uuid primary key default uuid_generate_v4(),
  created_at timestamptz default now(),
  studio_id  uuid references studios(id) on delete cascade not null,
  type       text not null check (type in ('slot','all','holiday','vacation')),
  date       date not null,
  end_date   date,
  slot_time  text,   -- 'HH:MM' или null
  reason     text default '',
  name       text default ''
);

-- Пользовательские названия для слотов расписания
create table if not exists slot_names (
  id           uuid primary key default uuid_generate_v4(),
  studio_id    uuid references studios(id) on delete cascade not null,
  day_of_week  int not null check (day_of_week between 0 and 6),
  start_time   text not null,
  name         text not null,
  unique(studio_id, day_of_week, start_time)
);

-- RLS
alter table extra_classes          enable row level security;
alter table schedule_cancellations enable row level security;
alter table slot_names             enable row level security;

-- Админ: полный доступ
create policy "Admin extra_classes"          on extra_classes          for all using (studio_id = my_studio_id());
create policy "Admin cancellations"          on schedule_cancellations for all using (studio_id = my_studio_id());
create policy "Admin slot_names"             on slot_names             for all using (studio_id = my_studio_id());

-- Клиенты: только чтение (чтобы приложение показывало отмены и доп. занятия)
create policy "Client read extra_classes"    on extra_classes          for select using (true);
create policy "Client read cancellations"    on schedule_cancellations for select using (true);
create policy "Client read slot_names"       on slot_names             for select using (true);
