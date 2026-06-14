const SUPABASE_URL = 'https://oaaplxktimcoxgziibzb.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hYXBseGt0aW1jb3hnemlpYnpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MzYyNTQsImV4cCI6MjA5NTExMjI1NH0.AA3t8_Vm5nWPxeKm72PC319P5zv1n48ft3kfvQVW9R0';

const IS_LOCAL = ['localhost', '127.0.0.1', ''].includes(window.location.hostname);

let sb = null;
try {
  if (!IS_LOCAL && typeof supabase !== 'undefined') {
    sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: 'alma-client-auth'
      }
    });
  }
} catch(e) {}
