CREATE OR REPLACE FUNCTION link_user_to_client(
  p_phone     text,
  p_user_id   uuid,
  p_name      text,
  p_lang      text,
  p_studio_id uuid
)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $func$
DECLARE
  v_client clients%rowtype;
  v_norm   text;
BEGIN
  v_norm := regexp_replace(
              regexp_replace(p_phone, '[^0-9]', '', 'g'),
              '^357', '');

  SELECT * INTO v_client
  FROM clients
  WHERE regexp_replace(
          regexp_replace(phone, '[^0-9]', '', 'g'),
          '^357', '') = v_norm
    AND studio_id = p_studio_id
  LIMIT 1;

  IF found THEN
    IF v_client.user_id IS NULL THEN
      UPDATE clients SET user_id = p_user_id WHERE id = v_client.id;
      v_client.user_id := p_user_id;
    END IF;
    RETURN row_to_json(v_client);
  ELSE
    RETURN NULL;
  END IF;
END;
$func$;
