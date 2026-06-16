// ─────────────────────────────────────────────────────────────
// Supabase credentials
// ─────────────────────────────────────────────────────────────

const PROD_URL = 'https://oaaplxktimcoxgziibzb.supabase.co';
const PROD_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hYXBseGt0aW1jb3hnemlpYnpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MzYyNTQsImV4cCI6MjA5NTExMjI1NH0.AA3t8_Vm5nWPxeKm72PC319P5zv1n48ft3kfvQVW9R0';

const DEV_URL  = 'https://kfdqplcxxaakhtctnyul.supabase.co';
const DEV_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtmZHFwbGN4eGFha2h0Y3RueXVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2MzU4NDgsImV4cCI6MjA5NzIxMTg0OH0.HY6xUMZsOxPGN4ICrmVJSfI2YEBE0Qrg58IrWNXPmYU';

// ─────────────────────────────────────────────────────────────
// Environment detection
//   localhost / 127.0.0.1        → DEV Supabase
//   deploy-preview-*.netlify.app → DEV Supabase
//   всё остальное                → PROD Supabase
// ─────────────────────────────────────────────────────────────

const IS_LOCAL   = ['localhost', '127.0.0.1', ''].includes(window.location.hostname);
const IS_PREVIEW = window.location.hostname.includes('deploy-preview');
const USE_DEV    = IS_LOCAL || IS_PREVIEW;

const SUPABASE_URL = USE_DEV ? DEV_URL  : PROD_URL;
const SUPABASE_KEY = USE_DEV ? DEV_KEY  : PROD_KEY;

// ─────────────────────────────────────────────────────────────
// Create Supabase client
// Теперь работает локально — подключается к DEV проекту
// ─────────────────────────────────────────────────────────────

let sb = null;
try {
  if (typeof supabase !== 'undefined') {
    sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
    if (USE_DEV) console.log('[supabase] DEV →', SUPABASE_URL);
  }
} catch(e) { console.error('[supabase] init error:', e); }
