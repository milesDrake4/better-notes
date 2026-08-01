# Better Notes Backend Security Checklist

## Code-side protections

- AI scan, feedback, follow-up, account usage, and account profile routes require a valid Supabase Auth user.
- Supabase access tokens are refreshed before AI requests when possible.
- iOS stores Supabase session data in Keychain instead of plain UserDefaults.
- OpenAI and Supabase Auth requests use timeouts.
- Large request bodies are rejected before the server keeps reading them.
- AI attachments and chat history are type-checked and capped before being sent to OpenAI.
- AI usage logs do not include email addresses, scanned work, PDFs, prompts, or AI response text.
- Public static serving is allowlisted instead of exposing every file in the project folder.
- Waitlist signups are rate-limited and return an error if the database is unavailable.
- The backend checks that Supabase tables exist on startup instead of creating production tables automatically.

## Supabase requirements

- Run `supabase/schema.sql` in the Supabase SQL editor after schema changes.
- Keep RLS enabled on `better_notes_users`, `waitlist_signups`, and `ai_usage_events`.
- Keep direct `anon` and `authenticated` table access revoked because the app goes through the Node backend.
- For stricter launch hardening, run `supabase/setup_backend_role.sql` with a real random password, rerun `supabase/schema.sql`, and update Render's `DATABASE_URL` to use that lower-privilege role.
- Do not put the Supabase service role key or database password in the iPad app.
- Do not use user-editable metadata for authorization decisions.

## Render requirements

- Set `OPENAI_API_KEY`, `DATABASE_URL`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` as secret environment variables.
- Set `FREE_SCAN_LIMIT` to the current beta limit.
- Confirm `/api/ready` returns `status: "ready"` after each deploy.
- Search Render logs for `[BetterNotesUsage]` after testing an AI scan.

## Before TestFlight

- Run `npm install` with internet access and commit `package-lock.json`.
- Test signup, login, logout, token refresh after waiting, AI scan limit, waitlist signup, and PDF context scan.
- Verify Supabase Table Editor shows usage rows after AI scans and waitlist rows after landing-page signups.
