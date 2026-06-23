// ─────────────────────────────────────────────────────────────
// Supabase init — auto-selects dev vs prod by hostname
// localhost / 127.0.0.1 → dev project (safe for testing)
// any other domain      → production project (kappacrm)
// ─────────────────────────────────────────────────────────────

const IS_LOCAL = ['localhost', '127.0.0.1', ''].includes(window.location.hostname);

// ── PROD ─────────────────────────────────────────────────────
const PROD_URL = 'https://oaaplxktimcoxgziibzb.supabase.co';
const PROD_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hYXBseGt0aW1jb3hnemlpYnpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MzYyNTQsImV4cCI6MjA5NTExMjI1NH0.AA3t8_Vm5nWPxeKm72PC319P5zv1n48ft3kfvQVW9R0';

// ── DEV ──────────────────────────────────────────────────────
const DEV_URL = 'https://mihcsujffzyryjsbessb.supabase.co';
const DEV_KEY = 'sb_publishable_TW8eSMPfh8_pyVmRnm9kBQ_eNhDkkdx';

const SUPABASE_URL = IS_LOCAL ? DEV_URL : PROD_URL;
const SUPABASE_KEY = IS_LOCAL ? DEV_KEY : PROD_KEY;

let sb = null;
try {
  const urlReady = !SUPABASE_URL.includes('REPLACE_WITH');
  if (urlReady && typeof supabase !== 'undefined') {
    sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
  }
} catch(e) {}
