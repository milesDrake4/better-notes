# Mistakes To Avoid

Status: draft for Miles to review.

This file records BetterNotes bugs and lessons so future agent sessions do not repeat the same mistakes.

## PencilKit And Canvas

- Do not reintroduce automatic blank page expansion without a careful zoom/eraser test. It previously caused PencilKit canvas drift and weird zoom movement.
- Be careful changing `PKCanvasView`, `UIScrollView`, `contentView`, `contentSize`, `frame`, `bounds`, or `contentInset`. These can break drawing alignment after pinch zoom.
- After changing canvas layout, test all of these on iPad:
  - draw with Apple Pencil
  - pinch zoom
  - draw after zooming
  - erase after zooming
  - switch from lasso to eraser
  - scroll with finger
- The eraser previously triggered page movement and stutter. Any eraser change needs manual iPad testing.
- Blank notes and imported PDF notes can behave differently. Test both when canvas code changes.

## Blank Pages

- The old automatic page spawning was removed because it likely contributed to the zoom/drawing bug.
- Current safer direction: manual add-page button first, then consider smarter page creation later.
- If automatic page creation comes back, preserve the visible content point and avoid recalculating horizontal inset during active Pencil gestures.

## PDF Import

- Importing a PDF "as is" should place the PDF itself in the note so the user can draw over it.
- Importing as homework context/rubric should make the file available to AI as reference context.
- Do not assume Notability-specific file behavior; students usually import a normal PDF from Canvas.

## AI Lens

- AI scan and chat are separate concepts.
- A new scan should not accidentally append to the wrong previous chat.
- Follow-up messages should belong to the selected AI chat/thread.
- The UI should make it clear whether the user is starting a new scan or adding a scan to an existing chat.
- The first AI response should support follow-ups without requiring a new scan.

## Backend And Render

- App-only SwiftUI changes do not require Render redeploy.
- Backend changes require pushing to GitHub so Render can deploy the new code.
- Render free instances can spin down, causing the first request after inactivity to be slow.
- Backend production URL is `https://better-notes-api.onrender.com`.

## Supabase And Auth

- `DATABASE_URL` is the Postgres connection string used by the Node backend.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` are used for auth.
- Supabase email confirmation can send to spam.
- For early testing, email confirmation may be disabled to reduce friction.
- Do not log or commit user passwords, API keys, database URLs, or auth tokens.

## LaTeX And AI Responses

- AI responses sometimes include literal `\n`; render them as actual line breaks.
- Math rendering can clip on the right side if the rendered label is sized too tightly.
- After changing math rendering, test:
  - inline math
  - display math
  - long equations
  - line breaks
  - AI response bubbles on iPad

## Launch Prep

- Before friend testing, verify:
  - account creation
  - login
  - usage limit
  - AI scan
  - follow-up chat
  - PDF import
  - blank note drawing
  - grid/blank paper setting
  - sign out and sign back in

