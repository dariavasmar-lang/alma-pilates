-- ============================================================
-- WHITELIST: только клиенты добавленные администратором
-- Запустить в Supabase SQL Editor
-- ============================================================

-- Меняем link_user_to_client: больше НЕ создаёт новых клиентов.
-- Если номер есть в clients → линкуем и возвращаем профиль.
-- Если номера нет → возвращаем null (доступ запрещён).

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
    -- Клиент найден — линкуем auth user если ещё не слинкован
    if v_client.user_id is null then
      update clients set user_id = p_user_id where id = v_client.id;
      v_client.user_id := p_user_id;
    end if;
    return row_to_json(v_client);
  else
    -- Номер не найден в базе — доступ запрещён, возвращаем null
    return null;
  end if;
end;
$$;
