const SUPABASE_URL = 'https://oaaplxktimcoxgziibzb.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hYXBseGt0aW1jb3hnemlpYnpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MzYyNTQsImV4cCI6MjA5NTExMjI1NH0.AA3t8_Vm5nWPxeKm72PC319P5zv1n48ft3kfvQVW9R0';

let sb = null;
try {
  if (typeof supabase !== 'undefined') {
    sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  }
} catch(e) {}
