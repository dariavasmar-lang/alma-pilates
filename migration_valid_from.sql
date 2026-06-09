-- ============================================================
-- ALMA PILATES — Миграция: valid_from для слотов расписания
-- Запустить в Supabase SQL Editor
-- ============================================================

-- Добавляем дату начала действия слота
alter table schedule_slots
  add column if not exists valid_from date default '2020-01-01';

-- Существующие слоты: считаем что они действуют с самого начала
update schedule_slots
  set valid_from = '2020-01-01'
  where valid_from is null;
