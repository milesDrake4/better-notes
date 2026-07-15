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
PORT=8080
HOST=0.0.0.0
REQUEST_BODY_LIMIT_BYTES=60000000
```

Then run:

```sh
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

On Render, open the service logs and search for that prefix after testing AI Lens. The log includes route, anonymous install ID, mode, attachment counts, success/failure, latency, and OpenAI token usage. It does not log the student's scanned work, prompt text, PDF contents, or AI response text.

## Supabase usage database

BetterNotes can persist usage events to Supabase Postgres when `DATABASE_URL` is set.

1. Create a Supabase project.
2. Copy the pooled Postgres connection string from Supabase.
3. Add it to Render as `DATABASE_URL`.
4. Redeploy the Render service.

The backend creates the required tables automatically on startup. The schema is also saved in:

```txt
supabase/schema.sql
```

The two tables are:

- `better_notes_users`: anonymous app installs, keyed by install ID.
- `ai_usage_events`: AI route, mode, token usage, latency, success/failure, and context counts.

## Next build steps

- Improve AI Lens selection into a true lasso tool.
- Add PDF import for worksheets and practice tests.
- Move to Flutter or native iPad once the core workflow feels right.
