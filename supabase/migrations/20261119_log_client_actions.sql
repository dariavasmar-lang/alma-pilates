-- Log bookings and cancellations made by clients in the app, so the admin
-- activity log shows who did what and when (admin actions already log themselves).
CREATE OR REPLACE FUNCTION public.log_client_action(
  p_studio_id uuid, p_action text, p_client_id uuid, p_booking_id uuid,
  p_class_date date, p_start time, p_status text, p_prev_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_name text; v_note text;
BEGIN
  SELECT full_name INTO v_name FROM clients WHERE id = p_client_id;
  v_note := CASE
    WHEN p_action = 'client_booked' AND p_status = 'unpaid_future' THEN 'booked in app (unpaid)'
    WHEN p_action = 'client_booked' THEN 'booked in app'
    WHEN p_status = 'missed' THEN 'late cancel in app (<4h, credit used)'
    ELSE 'cancelled in app' END;
  INSERT INTO admin_activity_log (studio_id, action_type, description, entity_type, entity_id, snapshot)
  VALUES (p_studio_id, p_action,
          coalesce(v_name, '?') || ' · ' || to_char(p_class_date, 'YYYY-MM-DD') || ' ' || coalesce(to_char(p_start, 'HH24:MI'), '') || ' · ' || v_note,
          'booking', p_booking_id,
          jsonb_build_object('booking_id', p_booking_id, 'client_uuid', p_client_id, 'client_name', v_name,
                             'class_date', p_class_date, 'status', p_status, 'prev_status', p_prev_status, 'source', 'client_app'));
EXCEPTION WHEN others THEN
  -- logging must never block a booking or a cancellation
  RAISE WARNING 'log_client_action failed: %', SQLERRM;
END;
$function$;
REVOKE ALL ON FUNCTION public.log_client_action(uuid, text, uuid, uuid, date, time, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.book_class(p_client_id uuid, p_slot_id uuid, p_studio_id uuid, p_class_date date, p_subscription_id uuid, p_status text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_capacity int; v_start time; v_slot_studio uuid; v_count int; v_bk_id uuid;
  v_is_admin boolean; v_now timestamp; v_class_at timestamp; v_sub subscriptions%rowtype;
BEGIN
  SELECT capacity, start_time, studio_id INTO v_capacity, v_start, v_slot_studio FROM schedule_slots WHERE id = p_slot_id;
  IF NOT FOUND THEN RETURN json_build_object('error', 'slot_not_found'); END IF;
  v_is_admin := my_studio_id() IS NOT NULL AND my_studio_id() = v_slot_studio;
  IF NOT v_is_admin THEN
    IF p_client_id IS DISTINCT FROM my_client_id() THEN RETURN json_build_object('error', 'not_allowed'); END IF;
    IF p_studio_id IS DISTINCT FROM v_slot_studio THEN RETURN json_build_object('error', 'not_allowed'); END IF;
    IF p_status NOT IN ('booked', 'unpaid_future') THEN RETURN json_build_object('error', 'not_allowed'); END IF;
    v_now := now() AT TIME ZONE 'Europe/Nicosia';
    v_class_at := p_class_date + v_start;
    IF v_class_at <= v_now THEN RETURN json_build_object('error', 'class_past'); END IF;
    IF p_class_date = v_now::date AND v_start >= time '15:00' AND v_now::time >= time '15:00' THEN
      RETURN json_build_object('error', 'cutoff');
    END IF;
    IF EXISTS (SELECT 1 FROM bookings WHERE client_id = p_client_id AND slot_id = p_slot_id AND class_date = p_class_date
               AND status IN ('booked', 'attended', 'unpaid_future')) THEN
      RETURN json_build_object('error', 'already_booked');
    END IF;
    IF p_status = 'booked' THEN
      SELECT * INTO v_sub FROM subscriptions WHERE id = p_subscription_id AND client_id = p_client_id;
      IF NOT FOUND OR NOT coalesce(v_sub.is_active, false) THEN RETURN json_build_object('error', 'no_subscription'); END IF;
      IF (v_sub.starts_at IS NOT NULL AND p_class_date < v_sub.starts_at) OR (v_sub.expires_at IS NOT NULL AND p_class_date > v_sub.expires_at) THEN
        RETURN json_build_object('error', 'outside_subscription');
      END IF;
      IF coalesce(v_sub.used_classes, 0) >= v_sub.total_classes THEN RETURN json_build_object('error', 'no_classes_left'); END IF;
    ELSIF p_subscription_id IS NOT NULL THEN
      RETURN json_build_object('error', 'not_allowed');
    END IF;
  END IF;
  WITH locked AS (
    SELECT id FROM bookings
    WHERE slot_id = p_slot_id AND class_date = p_class_date
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
  IF p_subscription_id IS NOT NULL AND p_status = 'booked' THEN
    UPDATE subscriptions SET used_classes = used_classes + 1 WHERE id = p_subscription_id;
  END IF;
  IF NOT v_is_admin THEN
    PERFORM log_client_action(p_studio_id, 'client_booked', p_client_id, v_bk_id, p_class_date, v_start, p_status, NULL);
  END IF;
  RETURN json_build_object('success', true, 'booking_id', v_bk_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_bk bookings%rowtype; v_start time; v_is_admin boolean; v_now timestamp; v_class_at timestamp;
  v_new text; v_sub subscriptions%rowtype; v_used int;
BEGIN
  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RETURN json_build_object('error', 'not_found'); END IF;
  v_is_admin := my_studio_id() IS NOT NULL AND my_studio_id() = v_bk.studio_id;
  IF NOT v_is_admin AND v_bk.client_id IS DISTINCT FROM my_client_id() THEN RETURN json_build_object('error', 'not_found'); END IF;
  IF v_bk.status = 'attended' THEN RETURN json_build_object('error', 'attended'); END IF;
  IF v_bk.status NOT IN ('booked', 'unpaid_future') THEN RETURN json_build_object('error', 'not_found'); END IF;
  SELECT start_time INTO v_start FROM schedule_slots WHERE id = v_bk.slot_id;
  v_now := now() AT TIME ZONE 'Europe/Nicosia';
  v_class_at := v_bk.class_date + coalesce(v_start, time '00:00');
  IF NOT v_is_admin THEN
    IF v_bk.class_date < v_now::date THEN RETURN json_build_object('error', 'class_past'); END IF;
    IF v_bk.class_date = v_now::date AND v_start >= time '15:00' AND v_now::time >= time '15:00' THEN
      RETURN json_build_object('error', 'cutoff');
    END IF;
  END IF;
  IF v_bk.status = 'unpaid_future' OR v_bk.class_date < v_now::date THEN v_new := 'cancelled';
  ELSIF v_class_at - v_now < interval '4 hours' THEN v_new := 'missed';
  ELSE v_new := 'cancelled';
  END IF;
  UPDATE bookings SET status = v_new WHERE id = v_bk.id;
  -- recount used_classes exactly as the app did before
  IF v_bk.subscription_id IS NOT NULL THEN
    SELECT * INTO v_sub FROM subscriptions WHERE id = v_bk.subscription_id;
    IF FOUND THEN
      SELECT count(*) INTO v_used FROM bookings
       WHERE client_id = v_bk.client_id AND subscription_id = v_sub.id AND status IN ('booked', 'attended', 'missed')
         AND (v_sub.starts_at IS NULL OR class_date >= v_sub.starts_at)
         AND (v_sub.expires_at IS NULL OR class_date <= v_sub.expires_at);
      UPDATE subscriptions SET used_classes = v_used WHERE id = v_sub.id;
    END IF;
  END IF;
  IF NOT v_is_admin THEN
    PERFORM log_client_action(v_bk.studio_id, 'client_cancelled', v_bk.client_id, v_bk.id, v_bk.class_date, v_start, v_new, v_bk.status);
  END IF;
  RETURN json_build_object('success', true, 'status', v_new, 'slot_id', v_bk.slot_id, 'class_date', v_bk.class_date);
END;
$function$
;
