# BetterNotes Agent Guide

Status: draft for Miles to review.

This file gives Codex and other coding agents the short version of how to work on BetterNotes without repeating old mistakes.

## Project Shape

- BetterNotes is a native iPad app built with SwiftUI and PencilKit.
- The iPad app lives in `ios/BetterNotes`.
- The share extension lives in `ios/BetterNotesShare`.
- The Node backend lives at the repo root in `server.js`.
- Supabase schema lives in `supabase/schema.sql`.
- Render hosts the production backend at `https://better-notes-api.onrender.com`.

## Core Product Direction

- BetterNotes is for students first.
- The main product promise is AI feedback inside the note-taking workflow.
- The app should feel like a focused school tool, not a broad productivity app.
- Keep AI Lens clear and central, but avoid making the UI feel loud or gimmicky.
- Native iPad Pencil experience matters more than web parity.

## Development Loop

For small visual changes:

1. Inspect the relevant SwiftUI/PencilKit file.
2. Make the smallest reasonable edit.
3. Run an Xcode build.
4. Explain what changed and whether the app needs reinstalling.

For larger features:

1. Explore the relevant app, backend, database, and deployment code.
2. Write or update a short plan in `docs/plans`.
3. Let Miles review the product decisions before implementation.
4. Implement in small pieces.
5. Verify with build, backend checks, and manual iPad test notes.
6. Commit with a specific message.

## Verification Commands

Native iOS build:

```sh
xcodebuild -project ios/BetterNotes.xcodeproj -scheme BetterNotes -configuration Debug -destination 'generic/platform=iOS' build
```

Backend local server:

```sh
npm start
```

Backend health:

```sh
npm run health
npm run ready
```

Production health:

```sh
curl -sS https://better-notes-api.onrender.com/api/health
curl -sS https://better-notes-api.onrender.com/api/ready
```

## Deployment Notes

- Swift/iPad-only changes do not require a Render deploy.
- Backend changes require a GitHub push and Render redeploy.
- Environment variables belong in Render or local `.env`, never in source control.
- Do not expose `OPENAI_API_KEY`, `DATABASE_URL`, or Supabase secrets in app code.

## Commit Style

Use small commits with plain messages:

```txt
Add visual paper style picker
Fix AI follow-up chat routing
Track scan usage by signed-in user
Document PencilKit zoom regression
```

Avoid vague messages like:

```txt
updates
stuff
fixes
```

## When To Slow Down

Use a written plan before changing:

- PencilKit canvas sizing, zooming, or gesture behavior.
- AI scan/chat architecture.
- Auth, usage limits, or subscriptions.
- Supabase schema or production backend behavior.
- PDF import/share extension workflows.
- TestFlight/App Store setup.

