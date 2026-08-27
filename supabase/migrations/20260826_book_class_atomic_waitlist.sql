-- Atomic booking with capacity check
CREATE OR REPLACE FUNCTION book_class(
  p_client_id      uuid,
  p_slot_id        uuid,
  p_studio_id      uuid,
  p_class_date     date,
  p_subscription_id uuid,
  p_status         text
)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $func$
DECLARE
  v_capacity int;
  v_count    int;
  v_bk_id    uuid;
  v_used     int;
BEGIN
  SELECT capacity INTO v_capacity FROM schedule_slots WHERE id = p_slot_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'slot_not_found');
  END IF;

  -- Lock rows then count (FOR UPDATE cannot be used with aggregate functions)
  WITH locked AS (
    SELECT id FROM bookings
    WHERE slot_id = p_slot_id
      AND class_date = p_class_date
      AND status IN ('booked', 'attended', 'unpaid_future')
    FOR UPDATE
  )
  SELECT COUNT(*) INTO v_count FROM locked;

  IF v_count >= v_capacity THEN
    RETURN json_build_object('error', 'class_full', 'capacity', v_capacity, 'count', v_count);
  END IF;

  INSERT INTO bookings (client_id, slot_id, studio_id, subscription_id, class_date, status)
  VALUES (p_client_id, p_slot_id, p_studio_id, p_subscription_id, p_class_date, p_status)
  RETURNING id INTO v_bk_id;

  -- Increment used_classes atomically if real booking (not unpaid_future)
  IF p_subscription_id IS NOT NULL AND p_status = 'booked' THEN
    UPDATE subscriptions
    SET used_classes = used_classes + 1
    WHERE id = p_subscription_id;
  END IF;

  RETURN json_build_object('success', true, 'booking_id', v_bk_id);
END;
$func$;

-- Get first person on waitlist for a slot/date with their phone
CREATE OR REPLACE FUNCTION get_next_waitlist_person(
  p_slot_id    uuid,
  p_class_date date
)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $func$
DECLARE
  v_result json;
BEGIN
  SELECT json_build_object(
    'waitlist_id', w.id,
    'client_id',   c.id,
    'full_name',   c.full_name,
    'phone',       c.phone,
    'lang',        COALESCE(c.language, 'el')
  ) INTO v_result
  FROM waitlist w
  JOIN clients c ON c.id = w.client_id
  WHERE w.slot_id    = p_slot_id
    AND w.class_date = p_class_date
  ORDER BY w.created_at ASC
  LIMIT 1;

  RETURN v_result;
END;
$func$;
