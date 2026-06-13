-- ============================================================
-- MIGRATION: Multi-studio support
-- Run on existing Supabase DB (safe, uses IF NOT EXISTS / IF EXISTS)
-- ============================================================

-- ─── 1. ADD slug AND logo_url TO studios ────────────────────
-- slug replaces subdomain as the URL-friendly studio identifier
ALTER TABLE studios ADD COLUMN IF NOT EXISTS slug     TEXT UNIQUE;
ALTER TABLE studios ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- Set slug for existing Alma Pilates studio
UPDATE studios
SET slug = 'alma-pilates'
WHERE id = 'a0000000-0000-0000-0000-000000000001'
  AND slug IS NULL;

-- ─── 2. CREATE platform_admins TABLE ────────────────────────
-- Separate table for platform-level operators (manage all studios)
CREATE TABLE IF NOT EXISTS platform_admins (
  user_id    uuid references auth.users(id) on delete cascade primary key,
  email      text,
  created_at timestamptz default now()
);

ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;

-- Platform admins can only see their own row
DROP POLICY IF EXISTS "Platform admin can read own row" ON platform_admins;
CREATE POLICY "Platform admin can read own row"
  ON platform_admins FOR SELECT USING (user_id = auth.uid());

-- ─── 3. UPDATE RLS ON studios ───────────────────────────────
-- Platform admins get full access to all studios
DROP POLICY IF EXISTS "Platform admin full access to studios" ON studios;
CREATE POLICY "Platform admin full access to studios"
  ON studios FOR ALL
  USING (EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid()));

-- ─── 4. FUNCTION: get studio by slug (for client app) ───────
-- Called on client app load to resolve slug → studio config
CREATE OR REPLACE FUNCTION get_studio_by_slug(p_slug text)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT row_to_json(s)
  FROM studios s
  WHERE s.slug = p_slug AND s.is_active = true
  LIMIT 1;
$$;

-- ─── 5. UPDATE link_user_to_client ──────────────────────────
-- Accept studio_id as parameter (no more hardcoded ID)
-- No whitelist check — any client can register
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
  -- Try to find existing client by phone in this studio
  SELECT * INTO v_client
  FROM clients
  WHERE phone = p_phone AND studio_id = p_studio_id
  LIMIT 1;

  IF found THEN
    -- Link auth user if not yet linked
    IF v_client.user_id IS NULL THEN
      UPDATE clients SET user_id = p_user_id WHERE id = v_client.id;
      v_client.user_id := p_user_id;
    END IF;
    RETURN row_to_json(v_client);
  ELSE
    -- New client — create record
    INSERT INTO clients (studio_id, user_id, full_name, phone, language, gdpr_consent, gdpr_consent_at)
    VALUES (p_studio_id, p_user_id, p_name, p_phone, p_lang, true, now())
    RETURNING * INTO v_client;
    RETURN row_to_json(v_client);
  END IF;
END;
$$;

-- ─── 6. FUNCTION: get studio_id for admin user ──────────────
-- Used by admin app after login
CREATE OR REPLACE FUNCTION my_studio_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT studio_id FROM admin_users WHERE user_id = auth.uid()
$$;
