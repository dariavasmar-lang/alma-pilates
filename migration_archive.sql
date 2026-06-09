-- ============================================================
-- CLIENT ARCHIVE
-- Запустить в Supabase SQL Editor
-- ============================================================

alter table clients add column if not exists is_archived boolean default false;
alter table clients add column if not exists archived_at  timestamptz;
alter table clients add column if not exists archive_note text;
