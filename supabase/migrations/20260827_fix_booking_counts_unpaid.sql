-- Fix get_booking_counts to include unpaid_future bookings in capacity count
-- Drop old text[] overload that was missing unpaid_future
DROP FUNCTION IF EXISTS get_booking_counts(text[]);

CREATE OR REPLACE FUNCTION get_booking_counts(p_dates date[])
RETURNS TABLE(slot_id uuid, class_date date, booking_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    b.slot_id,
    b.class_date,
    COUNT(*) AS booking_count
  FROM bookings b
  WHERE b.class_date = ANY(p_dates)
    AND b.status IN ('booked', 'attended', 'unpaid_future')
  GROUP BY b.slot_id, b.class_date;
$$;
