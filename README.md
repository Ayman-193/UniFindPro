# UniFind Pro — Campus Lost & Found

A redesigned, mobile-friendly campus lost-and-found site built from the original UniFind HTML/CSS/JS prototype. Uses **Supabase Auth, PostgreSQL, Row Level Security, and Storage** with **GitHub Pages** hosting. No Laravel, PHP, or paid server required for initial deployment.

## Features

- Responsive, modern public report board with search, type/category/status filters, pagination, and summary statistics.
- Email/password sign-up and login, email confirmation support, password reset email.
- Signed-in users can post lost/found reports and upload one optional photo (JPEG/PNG/WebP, 5 MB limit).
- Only report owners or admins can resolve or delete reports; only owners/admins see claim evidence.
- Signed-in users can send one private claim per report, and report owners/admins can approve/reject requests.
- Database RLS and SQL triggers protect permissions and ownership. HTML output is escaped to reduce XSS risk.

## Setup (follow in order)

1. Create a project at https://supabase.com/dashboard and save its database password somewhere private.
2. Open **SQL Editor** > **New query**. Paste the entire `database.sql` file and click **Run**. Check for errors.
3. Open **Project Settings > API** (some dashboards use **Connect** or **API Keys**). Copy **Project URL** and the **publishable** (`sb_publishable_...`) or legacy **anon** key. NEVER use a `service_role` / `sb_secret_...` key in this project.
4. Open `config.js` and replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_PUBLISHABLE_KEY` with those two values. Save. These client keys are public by design; database security relies on RLS.
5. Under **Authentication > Providers > Email**, enable email/password login. Prefer **Confirm email** ON for public deployment. Configure an SMTP provider for reliable public email delivery; Supabase's default mail service is limited.
6. Under **Authentication > URL Configuration**, set **Site URL** to `https://YOUR-USERNAME.github.io/UniFind/` and add this same URL to **Redirect URLs**. If using a custom domain, configure that exact URL instead. For password reset, Supabase will send a recovery link; this starter currently sends the email but does **not** implement a new-password screen, so add that flow before advertising password recovery as complete.
7. To test locally, use VS Code **Live Server** or run `python -m http.server 5500` inside the folder, then visit `http://localhost:5500`. ES modules won't work reliably via `file://`. Add `http://localhost:5500/` to Supabase Redirect URLs if testing email redirects locally.
8. Create a GitHub repository (or use your existing UniFind repository). Upload `index.html`, `style.css`, `script.js`, `config.js` and optionally `README.md` to the repository **root**. Do **not** upload `database.sql` if you prefer to keep the schema private (the SQL itself has no secrets).
9. In the GitHub repository, go to **Settings > Pages > Build and deployment**, select **Deploy from a branch**, branch **main**, folder **/(root)**, then **Save**. Wait for Pages deployment. The website will usually be `https://YOUR-USERNAME.github.io/REPOSITORY-NAME/`.
10. Revisit Supabase Authentication URL Configuration and set the **exact deployed Pages URL** (including trailing slash) as Site URL / allowed Redirect URL.
11. Test sign-up, email confirmation, sign-in, posting a report with and without an image, viewing it in a second browser, claiming as another account, owner reviewing claims, resolving, and deleting.

### Promote an admin (optional)

First create a user account through the website. In the Supabase SQL Editor, execute (replace email):

```sql
update public.profiles
set role='admin'
where id=(select id from auth.users where email='admin@example.com');
```

**Never** add a UI button that changes the `role` field. The SQL script does not grant profile updates to normal users.

## File guide

- `index.html` — UI, dialogs, accessibility labels
- `style.css` — responsive visual design
- `script.js` — Supabase authentication, report/claim workflows
- `config.js` — public project URL and public key (must fill in)
- `database.sql` — tables, constraints, indexes, RLS policies, storage policies

## Important production limitations / next steps

This is a deployable **starter**, not a security-audited production system. Before inviting an entire university, review and test policies, add moderation/report abuse controls, rate limiting / CAPTCHA for signups, an email provider, image content moderation, a complete password recovery screen, and a privacy policy and data retention process. Claims have no in-app notifications; owners must open their own reports and select **Claims**. There is no real-time refresh; reload to see new reports. Public photos are intentionally accessible to everyone. Report deletion currently removes the database row but does **not** automatically delete its Storage image; implement secure server-side cleanup or a scheduled cleanup job to avoid orphaned files. Deleting a user account is not exposed in the UI. Supabase free-tier quotas, email limits and project pausing may apply.

### Privacy and safe handover

Do not post ID card numbers, addresses, phone numbers, passwords, serial numbers, or private identifying photos. Claim descriptions are private to the claimant, report owner, and admin, but can still contain personal data. Meet in a safe campus location and confirm ownership without publicly disclosing verification details.
