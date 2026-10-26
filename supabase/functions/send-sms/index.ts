import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

async function sendTwilio(phone: string, message: string) {
  const accountSid = Deno.env.get('TWILIO_ACCOUNT_SID')!
  const authToken  = Deno.env.get('TWILIO_AUTH_TOKEN')!
  const msgSid     = Deno.env.get('TWILIO_MESSAGING_SERVICE_SID')!
  const twilioRes = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
    {
      method: 'POST',
      headers: {
        Authorization: 'Basic ' + btoa(`${accountSid}:${authToken}`),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: phone, MessagingServiceSid: msgSid, Body: message }),
    }
  )
  const result = await twilioRes.json()
  if (!twilioRes.ok) {
    console.error('Twilio error:', result)
    return json({ error: result.message || 'Twilio error' }, 500)
  }
  return json({ success: true, sid: result.sid })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const body = await req.json()

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    // Waitlist notice: any logged-in user may trigger it, but the server picks the recipient and writes the text
    if (body.type === 'waitlist') {
      const { slot_id, class_date } = body
      if (!slot_id || !class_date) return json({ error: 'Missing slot_id or class_date' }, 400)
      const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
      const { data: slot } = await admin.from('schedule_slots').select('start_time,capacity').eq('id', slot_id).single()
      if (!slot) return json({ error: 'slot_not_found' }, 400)
      const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Europe/Nicosia' })
      if (class_date < today) return json({ skipped: 'past' })
      const { count } = await admin.from('bookings').select('id', { count: 'exact', head: true })
        .eq('slot_id', slot_id).eq('class_date', class_date).in('status', ['booked', 'attended', 'unpaid_future'])
      if ((count ?? 0) >= slot.capacity) return json({ skipped: 'full' })
      const { data: person } = await admin.rpc('get_next_waitlist_person', { p_slot_id: slot_id, p_class_date: class_date })
      if (!person?.phone) return json({ skipped: 'no_waitlist' })
      const name = String(person.full_name || '').split(' ')[0]
      const slotTime = String(slot.start_time).slice(0, 5)
      const dateObj = new Date(class_date + 'T12:00:00')
      const dateLabel = dateObj.toLocaleDateString('el-GR', { weekday: 'long', day: 'numeric', month: 'long' })
      const dateLabelEn = dateObj.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })
      const msg = `${name}, μία θέση έχει ελευθερωθεί για το μάθημα ${dateLabel} στις ${slotTime} και μπορείς να κλείσεις το μάθημά σου από την εφαρμογή! 💜\n\nA spot has opened for the ${dateLabelEn} ${slotTime} class. Book your spot in the app! 💜`
      return await sendTwilio(person.phone, msg)
    }

    // Any other text: studio admins only, for their own studio
    const { phone, message, studio_id } = body
    if (!phone || !message || !studio_id) return json({ error: 'Missing phone, message or studio_id' }, 400)
    const { data: adminRow } = await supabase.from('admin_users').select('studio_id').eq('user_id', user.id).maybeSingle()
    if (!adminRow || adminRow.studio_id !== studio_id) return json({ error: 'Forbidden' }, 403)
    return await sendTwilio(phone, message)

  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
