-- ============================================================
-- ALMA PILATES PLATFORM — Database schema
-- Single source of truth. Run on a clean database only.
-- For existing databases — use db/migrations/*.sql
-- ============================================================

-- ─── EXTENSIONS ─────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── STUDIOS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS studios (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at      timestamptz DEFAULT now(),
  name            text NOT NULL,
  slug            text UNIQUE NOT NULL,       -- URL identifier: alma-pilates
  subdomain       text UNIQUE,               -- legacy, kept for compatibility
  city            text DEFAULT 'Limassol',
  phone           text,
  email           text,
  logo_url        text,                      -- studio logo
  plan            text DEFAULT 'business'
                  CHECK (plan IN ('starter','business','multi')),
  is_active       boolean DEFAULT true,
  price_8         numeric(10,2) DEFAULT 120,
  price_12        numeric(10,2) DEFAULT 160,
  price_single    numeric(10,2) DEFAULT 25,
  capacity        int DEFAULT 4,
  revolut_api_key text,
  config          jsonb DEFAULT '{}'
);

-- ─── PLATFORM ADMINS ────────────────────────────────────────
-- Platform-level operators who can manage all studios
CREATE TABLE IF NOT EXISTS platform_admins (
  user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email      text,
  created_at timestamptz DEFAULT now()
);

-- ─── ADMIN USERS ────────────────────────────────────────────
-- Studio-level admins — each belongs to one studio
CREATE TABLE IF NOT EXISTS admin_users (
  user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  studio_id  uuid REFERENCES studios(id) ON DELETE CASCADE NOT NULL,
  role       text DEFAULT 'admin'
             CHECK (role IN ('owner','admin','trainer')),
  created_at timestamptz DEFAULT now()
);

-- ─── CLIENTS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clients (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at      timestamptz DEFAULT now(),
  studio_id       uuid REFERENCES studios(id) ON DELETE CASCADE NOT NULL,
  user_id         uuid REFERENCES auth.users(id),
  full_name       text NOT NULL DEFAULT '',
  phone           text,
  email           text,
  language        text DEFAULT 'el' CHECK (language IN ('ru','el','en')),
  notes           text,
  is_active       boolean DEFAULT true,
  gdpr_consent    boolean DEFAULT false,
  gdpr_consent_at timestamptz
);

-- ─── SUBSCRIPTIONS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at      timestamptz DEFAULT now(),
  studio_id       uuid REFERENCES studios(id) NOT NULL,
  client_id       uuid REFERENCES clients(id) ON DELETE CASCADE NOT NULL,
  type            text NOT NULL CHECK (type IN ('8','12','single')),
  total_classes   int NOT NULL,
  used_classes    int DEFAULT 0,
  price           numeric(10,2) NOT NULL,
  paid_at         timestamptz,
  starts_at       date NOT NULL,
  expires_at      date,
  payment_method  text CHECK (payment_method IN ('revolut','cash','bank','card')),
  revolut_payment_id text,
  is_active       boolean DEFAULT true
);

CREATE OR REPLACE VIEW subscriptions_with_left AS
  SELECT *,
    (total_classes - used_classes) AS classes_left,
    (expires_at < current_date AND is_active) AS is_expired
  FROM subscriptions;

-- ─── SCHEDULE SLOTS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS schedule_slots (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  studio_id   uuid REFERENCES studios(id) ON DELETE CASCADE NOT NULL,
  day_of_week int NOT NULL CHECK (day_of_week BETWEEN 0 AND 5), -- 0=Mon, 5=Sat
  start_time  time NOT NULL,
  end_time    time NOT NULL,
  capacity    int DEFAULT 4,
  is_active   boolean DEFAULT true,
  UNIQUE(studio_id, day_of_week, start_time)
);

-- ─── WAITLIST ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS waitlist (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at  timestamptz DEFAULT now(),
  studio_id   uuid REFERENCES studios(id) NOT NULL,
  client_id   uuid REFERENCES clients(id) ON DELETE CASCADE NOT NULL,
  slot_id     uuid REFERENCES schedule_slots(id),
  class_date  date NOT NULL,
  UNIQUE(client_id, slot_id, class_date)
);

-- ─── BOOKINGS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at      timestamptz DEFAULT now(),
  studio_id       uuid REFERENCES studios(id) NOT NULL,
  client_id       uuid REFERENCES clients(id) ON DELETE CASCADE NOT NULL,
  slot_id         uuid REFERENCES schedule_slots(id),
  subscription_id uuid REFERENCES subscriptions(id),
  class_date      date NOT NULL,
  status          text DEFAULT 'booked'
                  CHECK (status IN ('booked','attended','missed','cancelled')),
  is_trial        boolean DEFAULT false,
  notes           text
);

-- ─── PAYMENTS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
  id                   uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at           timestamptz DEFAULT now(),
  studio_id            uuid REFERENCES studios(id) NOT NULL,
  client_id            uuid REFERENCES clients(id),
  subscription_id      uuid REFERENCES subscriptions(id),
  amount               numeric(10,2) NOT NULL,
  method               text CHECK (method IN ('revolut','cash','bank','card')),
  revolut_payment_id   text,
  revolut_payment_url  text,
  status               text DEFAULT 'pending'
                       CHECK (status IN ('pending','paid','failed','refunded')),
  paid_at              timestamptz,
  notes                text
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE studios         ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users     ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients         ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_slots  ENABLE ROW LEVEL SECURITY;
ALTER TABLE waitlist        ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments        ENABLE ROW LEVEL SECURITY;

-- ─── HELPER FUNCTIONS ───────────────────────────────────────

-- Get studio_id for the logged-in admin
CREATE OR REPLACE FUNCTION my_studio_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT studio_id FROM admin_users WHERE user_id = auth.uid()
$$;

-- Get client_id for the logged-in client
CREATE OR REPLACE FUNCTION my_client_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM clients WHERE user_id = auth.uid() LIMIT 1
$$;

-- Resolve studio slug → studio row (called by client app on load)
CREATE OR REPLACE FUNCTION get_studio_by_slug(p_slug text)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT row_to_json(s)
  FROM studios s
  WHERE s.slug = p_slug AND s.is_active = true
  LIMIT 1;
$$;

-- Link client on OTP login (whitelist mode: only pre-added clients can log in)
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

-- Count booked seats per slot for given dates
CREATE OR REPLACE FUNCTION get_booking_counts(p_dates date[])
RETURNS TABLE(slot_id uuid, booking_count bigint)
LANGUAGE sql STABLE AS $$
  SELECT slot_id, count(*) AS booking_count
  FROM bookings
  WHERE class_date = ANY(p_dates)
    AND status IN ('booked','attended')
  GROUP BY slot_id
$$;

-- ─── RLS POLICIES: PLATFORM ADMINS ──────────────────────────

-- Platform admins see only their own row
DROP POLICY IF EXISTS "Platform admin can read own row" ON platform_admins;
CREATE POLICY "Platform admin can read own row"
  ON platform_admins FOR SELECT USING (user_id = auth.uid());

-- ─── RLS POLICIES: ADMIN USERS ──────────────────────────────

-- Studio admins can read their own row (needed for login check)
DROP POLICY IF EXISTS "Admin can read own row" ON admin_users;
CREATE POLICY "Admin can read own row"
  ON admin_users FOR SELECT USING (user_id = auth.uid());

-- Platform admins have full access to all studios
DROP POLICY IF EXISTS "Platform admin full access to studios" ON studios;
CREATE POLICY "Platform admin full access to studios"
  ON studios FOR ALL
  USING (EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid()));

-- ─── RLS POLICIES: STUDIO ADMINS ────────────────────────────

DROP POLICY IF EXISTS "Own studio only"          ON studios;
DROP POLICY IF EXISTS "Own studio clients"        ON clients;
DROP POLICY IF EXISTS "Own studio subscriptions"  ON subscriptions;
DROP POLICY IF EXISTS "Own studio schedule"       ON schedule_slots;
DROP POLICY IF EXISTS "Own studio waitlist"       ON waitlist;
DROP POLICY IF EXISTS "Own studio bookings"       ON bookings;
DROP POLICY IF EXISTS "Own studio payments"       ON payments;

CREATE POLICY "Own studio only"
  ON studios FOR ALL USING (id = my_studio_id());

CREATE POLICY "Own studio clients"
  ON clients FOR ALL USING (studio_id = my_studio_id());

CREATE POLICY "Own studio subscriptions"
  ON subscriptions FOR ALL USING (studio_id = my_studio_id());

CREATE POLICY "Own studio schedule"
  ON schedule_slots FOR ALL USING (studio_id = my_studio_id());

CREATE POLICY "Own studio waitlist"
  ON waitlist FOR ALL USING (studio_id = my_studio_id());

CREATE POLICY "Own studio bookings"
  ON bookings FOR ALL USING (studio_id = my_studio_id());

CREATE POLICY "Own studio payments"
  ON payments FOR ALL USING (studio_id = my_studio_id());

-- ─── RLS POLICIES: CLIENTS (mobile app) ─────────────────────

DROP POLICY IF EXISTS "Client can read own record"          ON clients;
DROP POLICY IF EXISTS "Client can update own record"        ON clients;
DROP POLICY IF EXISTS "Client can insert self"              ON clients;
DROP POLICY IF EXISTS "Client can read own subscriptions"   ON subscriptions;
DROP POLICY IF EXISTS "Client can update own subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Client can read own bookings"        ON bookings;
DROP POLICY IF EXISTS "Client can insert bookings"          ON bookings;
DROP POLICY IF EXISTS "Client can update own bookings"      ON bookings;
DROP POLICY IF EXISTS "Client can read own waitlist"        ON waitlist;
DROP POLICY IF EXISTS "Client can insert waitlist"          ON waitlist;
DROP POLICY IF EXISTS "Client can delete own waitlist"      ON waitlist;
DROP POLICY IF EXISTS "Anyone can read schedule"            ON schedule_slots;

CREATE POLICY "Client can read own record"
  ON clients FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Client can update own record"
  ON clients FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Client can read own subscriptions"
  ON subscriptions FOR SELECT USING (client_id = my_client_id());

CREATE POLICY "Client can update own subscriptions"
  ON subscriptions FOR UPDATE USING (client_id = my_client_id());

CREATE POLICY "Client can read own bookings"
  ON bookings FOR SELECT USING (client_id = my_client_id());

CREATE POLICY "Client can insert bookings"
  ON bookings FOR INSERT WITH CHECK (client_id = my_client_id());

CREATE POLICY "Client can update own bookings"
  ON bookings FOR UPDATE USING (client_id = my_client_id());

CREATE POLICY "Client can read own waitlist"
  ON waitlist FOR SELECT USING (client_id = my_client_id());

CREATE POLICY "Client can insert waitlist"
  ON waitlist FOR INSERT WITH CHECK (client_id = my_client_id());

CREATE POLICY "Client can delete own waitlist"
  ON waitlist FOR DELETE USING (client_id = my_client_id());

-- Anyone authenticated can read schedule (needed for client app)
CREATE POLICY "Anyone can read schedule"
  ON schedule_slots FOR SELECT USING (true);

-- ============================================================
-- SEED DATA (run once on fresh database)
-- ============================================================

INSERT INTO studios (id, name, slug, subdomain, city, phone, email, plan)
VALUES (
  'a0000000-0000-0000-0000-000000000001',
  'Alma Pilates Studio', 'alma-pilates', 'alma', 'Limassol, Cyprus',
  '96850466', 'info@almapilatesstudio.com', 'business'
) ON CONFLICT (id) DO NOTHING;

-- Schedule slots (0=Mon, 5=Sat)
INSERT INTO schedule_slots (studio_id, day_of_week, start_time, end_time) VALUES
  ('a0000000-0000-0000-0000-000000000001', 0, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 0, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 1, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 1, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 1, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 2, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 3, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 3, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '07:00', '08:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '08:00', '09:00'),
  ('a0000000-0000-0000-0000-000000000001', 4, '09:15', '10:15'),
  ('a0000000-0000-0000-0000-000000000001', 4, '16:30', '17:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '17:30', '18:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '18:30', '19:30'),
  ('a0000000-0000-0000-0000-000000000001', 4, '19:30', '20:30'),
  ('a0000000-0000-0000-0000-000000000001', 5, '09:30', '10:30'),
  ('a0000000-0000-0000-0000-000000000001', 5, '10:30', '11:30')
ON CONFLICT (studio_id, day_of_week, start_time) DO NOTHING;
