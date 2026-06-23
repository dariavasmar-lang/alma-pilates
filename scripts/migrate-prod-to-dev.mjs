// ─────────────────────────────────────────────────────────────
// migrate-prod-to-dev.mjs
// Copies data from prod Supabase → dev Supabase
// Run: node scripts/migrate-prod-to-dev.mjs
// Requires: .env file in project root with PROD_SERVICE_KEY and DEV_SERVICE_KEY
// ─────────────────────────────────────────────────────────────

import { createClient } from './node_modules/@supabase/supabase-js/dist/index.mjs';
import { config } from './node_modules/dotenv/lib/main.js';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(__dirname, '../.env') });

const PROD_KEY = process.env.PROD_SERVICE_KEY;
const DEV_KEY  = process.env.DEV_SERVICE_KEY;

if (!PROD_KEY || !DEV_KEY) {
  console.error('Missing PROD_SERVICE_KEY or DEV_SERVICE_KEY in .env');
  process.exit(1);
}

const PROD = createClient('https://oaaplxktimcoxgziibzb.supabase.co', PROD_KEY);
const DEV  = createClient('https://mihcsujffzyryjsbessb.supabase.co', DEV_KEY);

const STUDIO_ID = 'a0000000-0000-0000-0000-000000000001';

// Columns that exist in dev schema (known safe set)
const ALLOWED = {
  schedule_slots: ['id','studio_id','day_of_week','start_time','end_time','capacity','is_active'],
  clients:        ['id','created_at','studio_id','full_name','phone','email','language','notes','is_active','gdpr_consent','gdpr_consent_at','is_trial'],
  subscriptions:  ['id','created_at','studio_id','client_id','type','total_classes','used_classes','price','paid_at','starts_at','expires_at','payment_method','revolut_payment_id','is_active'],
  bookings:       ['id','created_at','studio_id','client_id','slot_id','subscription_id','class_date','status','is_trial','notes'],
  payments:       ['id','created_at','studio_id','client_id','subscription_id','amount','method','revolut_payment_id','revolut_payment_url','status','paid_at','notes'],
};

function strip(rows, table) {
  const cols = ALLOWED[table];
  return rows.map(row => {
    const clean = {};
    for (const col of cols) if (col in row) clean[col] = row[col];
    return clean;
  });
}

async function clearDev(table) {
  const { error } = await DEV.from(table).delete().eq('studio_id', STUDIO_ID);
  if (error) console.error(`  clear ${table} error:`, error.message);
}

async function migrate(table, transform) {
  process.stdout.write(`→ ${table}... `);

  const { data, error } = await PROD.from(table).select('*').eq('studio_id', STUDIO_ID);
  if (error) { console.error('READ ERROR:', error.message); return; }
  if (!data?.length) { console.log('empty, skip'); return; }

  let rows = strip(data, table);
  if (transform) rows = rows.map(transform);

  // Upsert in batches of 500
  const BATCH = 500;
  for (let i = 0; i < rows.length; i += BATCH) {
    const { error: e } = await DEV.from(table).upsert(rows.slice(i, i + BATCH), { onConflict: 'id' });
    if (e) { console.error('WRITE ERROR:', e.message); return; }
  }
  console.log(`✓ ${rows.length} rows`);
}

console.log('Starting migration prod → dev\n');

// Clear existing dev data (reverse FK order)
process.stdout.write('Clearing dev data... ');
await clearDev('payments');
await clearDev('bookings');
await clearDev('subscriptions');
await clearDev('clients');
await clearDev('schedule_slots');
console.log('done\n');

// Migrate (FK order: slots → clients → subs → bookings)
await migrate('schedule_slots');
// Null out user_id — prod auth users don't exist in dev
await migrate('clients', row => ({ ...row, user_id: null }));
await migrate('subscriptions');
await migrate('bookings');
await migrate('payments');

console.log('\nDone! Refresh localhost:8888/alma-pilates/admin to see the data.');
