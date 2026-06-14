-- ============================================================
-- Migration: whitelist-only login
-- link_user_to_client now returns NULL if phone not found.
-- Only clients pre-added by admin can log in.
-- ============================================================

CREATE OR REPLACE FUNCTION link_user_to_client(
  p_phone     text,
  p_user_id   uuid,
  p_name      text,
  p_lang      text,
  p_studio_id uuid
)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_client clients%rowtype;
BEGIN
  SELECT * INTO v_client
  FROM clients
  WHERE phone = p_phone AND studio_id = p_studio_id
  LIMIT 1;

  IF found THEN
    -- Link user_id if not yet linked
    IF v_client.user_id IS NULL THEN
      UPDATE clients SET user_id = p_user_id WHERE id = v_client.id;
      v_client.user_id := p_user_id;
    END IF;
    RETURN row_to_json(v_client);
  ELSE
    -- Phone not in clients table → access denied (whitelist mode)
    RETURN NULL;
  END IF;
END;
$$;
