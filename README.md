# Alma Pilates Studio

Web application for managing a Pilates studio in Limassol, Cyprus.

## Apps

| File | Description | Users |
|------|-------------|-------|
| `Alma_Pilates_Client.html` | Mobile client app — book classes, pay, view history | Studio clients |
| `Alma_Pilates_Admin.html` | Studio admin panel — clients, schedule, payments, expenses, taxes | Studio owner |
| `Platform_Admin.html` | Platform operator panel — manage multiple studios | Platform team |

## Stack

- **Frontend:** Vanilla HTML/CSS/JS, no build step
- **Backend:** [Supabase](https://supabase.com) — auth (phone OTP), PostgreSQL, RLS policies
- **Hosting:** [Netlify](https://netlify.com) — static deploy from GitHub
- **Payments:** Revolut Business payment links

## Project structure

```
├── Alma_Pilates_Client.html   # Client app
├── Alma_Pilates_Admin.html    # Admin panel
├── Platform_Admin.html        # Platform operator panel
├── index.html                 # Redirect to client app
├── css/
│   ├── client.css
│   ├── admin.css
│   └── platform.css
├── js/
│   ├── i18n.js                # All translations (EL / EN / RU)
│   └── supabase-init.js       # Supabase client init
└── schema_final.sql           # Database schema
```

## Localization

All translations live in `js/i18n.js` — three languages: Greek (`el`), English (`en`), Russian (`ru`).

To add or fix a translation, edit the corresponding key in `js/i18n.js`.

## Local development

No build step required — serve files with any static server:

```bash
python3 -m http.server 8080
```

Then open:
- `http://localhost:8080/Alma_Pilates_Client.html`
- `http://localhost:8080/Alma_Pilates_Admin.html`

## Database

Schema is in `schema_final.sql`. Run it in the Supabase SQL editor to set up tables and RLS policies.

Migrations for incremental changes are in `migration_*.sql` files.

## Contributing

1. `git checkout -b feature/short-description`
2. Make changes and commit
3. `gh pr create` — open a PR
4. Merge via GitHub after review
