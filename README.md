# Better Notes

Better Notes is an early prototype for an AI-first note-taking app for students.

This first version is intentionally lightweight:

- Start on a home page with class folders.
- Create new class folders.
- Open a class folder to see notes.
- Create or open notes from inside a class folder.
- Draw or write on a full-page blank note.
- Switch between pen and eraser.
- Use AI Lens to select part of the page or scan the full note.
- Choose Check, Hint, or Grade feedback mode.
- Save folders, notes, titles, and drawings in local storage.
- Send AI Lens scans to an OpenAI vision model through a local backend.

## Run it

For the full prototype, including real AI Lens feedback, create a `.env` file:

```txt
OPENAI_API_KEY=your_api_key_here
OPENAI_MODEL=gpt-5-mini
DATABASE_URL=postgresql://postgres.your_project:your_password@aws-0-us-east-1.pooler.supabase.com:6543/postgres
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key_here
FREE_SCAN_LIMIT=3
PORT=8080
HOST=0.0.0.0
REQUEST_BODY_LIMIT_BYTES=60000000
OPENAI_TIMEOUT_MS=80000
SUPABASE_AUTH_TIMEOUT_MS=15000
WAITLIST_RATE_LIMIT_MAX=8
AI_RATE_LIMIT_MAX=30
AI_RATE_LIMIT_WINDOW_MS=3600000
AUTH_RATE_LIMIT_MAX=20
AUTH_RATE_LIMIT_WINDOW_MS=900000
```

Then run:

```sh
npm install
npm start
```

Then visit:

```txt
http://localhost:8080
```

On an iPad connected to the same Wi-Fi, BetterNotes uses:

```txt
http://Miless-MacBook-Air-3006.local:8080
```

Keep the terminal running while testing AI Lens. The API key stays in `.env` on the Mac and is never included in the iPad app.

You can still open `index.html` directly for the non-AI parts of the prototype, but AI Lens needs the local server so your API key stays out of browser code.

## Backend checks

While the backend is running, you can check whether the server is alive:

```sh
npm run health
```

You can also check whether it is ready to handle real AI requests:

```sh
npm run ready
```

`/api/health` should work even without an OpenAI key. `/api/ready` returns a setup error until `OPENAI_API_KEY` is configured, which is useful for deployment later.

## Usage logs

AI routes write structured usage logs to stdout with the prefix:

```txt
[BetterNotesUsage]
```

On Render, open the service logs and search for that prefix after testing AI Lens. The log includes route, app install ID, authenticated user ID, mode, attachment counts, success/failure, latency, and OpenAI token usage. It does not log the user's email, scanned work, prompt text, PDF contents, or AI response text.

## Supabase usage database

BetterNotes persists account profile, waitlist, and AI usage events to Supabase Postgres when `DATABASE_URL` is set.

1. Create a Supabase project.
2. In Supabase SQL editor, run `supabase/schema.sql`.
3. Copy the pooled Postgres connection string from Supabase.
4. Add it to Render as `DATABASE_URL`.
5. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` to Render for auth.
6. Redeploy the Render service.

The backend no longer creates or changes tables automatically on startup. It checks that the schema exists and `/api/ready` returns `not_ready` if the database is missing. The current schema is saved in:

```txt
supabase/schema.sql
```

The matching migration file is saved in:

```txt
supabase/migrations/20260731000000_backend_security_hardening.sql
```

The core tables are:

- `better_notes_users`: signed-in BetterNotes users, linked to Supabase Auth.
- `waitlist_signups`: public landing-page demo signups.
- `ai_usage_events`: AI route, mode, token usage, latency, success/failure, and context counts.

RLS is enabled on all three tables. Direct `anon` and `authenticated` table access is revoked because the app talks to this database through the Node backend, not directly from the iPad.

For a stricter launch setup, run `supabase/setup_backend_role.sql` after replacing the placeholder password. Then rerun `supabase/schema.sql` and update Render's `DATABASE_URL` to use that lower-privilege database role instead of the default `postgres` owner connection.

Before a production push, run `npm install` once from this folder with internet access and commit the generated `package-lock.json`. That pins the backend dependency tree for Render deploys.

## Free scan limit

The backend enforces a beta free-scan limit using the signed-in Supabase user account.

```txt
FREE_SCAN_LIMIT=3
```

A successful user-facing scan is counted when `/api/ai-feedback` succeeds. Once an account reaches the limit, `/api/ai-transcribe` and `/api/ai-feedback` block before calling OpenAI so extra scans do not spend API credits. Follow-up chat messages do not currently count as new free scans.

The backend also rate-limits AI and auth requests so one account or IP cannot rapidly burn API credits or hammer Supabase Auth during the beta.

## Next build steps

- Improve AI Lens selection into a true lasso tool.
- Add PDF import for worksheets and practice tests.
- Move to Flutter or native iPad once the core workflow feels right.
