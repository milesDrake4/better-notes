# BetterNotes Launch Roadmap

Status: draft for Miles to review.

This roadmap is for getting BetterNotes from prototype to a small friend-testable iPad app.

## Goal

Let a few real students install BetterNotes, create accounts, import or create schoolwork notes, use AI Lens, and give useful feedback without needing Miles' laptop or local server.

## Current Foundation

- Native iPad app using SwiftUI and PencilKit.
- Render-hosted Node backend.
- OpenAI API calls routed through backend, not directly from app.
- Supabase configured for auth and usage logging.
- Free scan limit enforced by backend.
- AI Lens supports scan modes: hint, check work, and grade/rubric.
- AI chats can have follow-up messages.
- App supports blank notes and PDF-backed notes.

## Phase 1: Friend Testing Readiness

Focus: make the app safe enough and clear enough for a few trusted testers.

- Confirm account creation and login work without confusing confirmation flow.
- Add a small account/usage screen that shows the signed-in email and scan usage.
- Make the current scan limit visible to the user.
- Confirm AI Lens uses the Render backend URL.
- Confirm Supabase stores usage events with signed-in user IDs.
- Push current code to GitHub.
- Create a simple tester instructions doc.
- Install through Xcode for local testing, then move toward TestFlight.

## Phase 2: TestFlight Setup

Focus: distribute to friends without plugging their iPads into the Mac.

- Confirm Apple Developer account status.
- Create App Store Connect app record.
- Set bundle identifier, signing, icons, and app metadata.
- Archive the app from Xcode.
- Upload build to App Store Connect.
- Add internal/external testers.
- Prepare a short beta description and feedback instructions.

## Phase 3: Data And Sync

Focus: make user data more reliable across installs/devices.

- Decide what must sync first:
  - folders
  - notes metadata
  - drawings
  - text boxes
  - images
  - imported PDFs
  - AI chat history
- Design Supabase tables or storage buckets for notes and files.
- Keep local-first editing so drawing still feels fast.
- Add background sync with conflict rules.
- Add export or backup path before relying heavily on cloud storage.

## Phase 4: Usage Limits And Payment

Focus: protect API costs and test willingness to pay.

- Keep free scan limit server-side.
- Add a paid entitlement model.
- Decide pricing experiment, likely monthly student subscription.
- Use Apple In-App Purchases for App Store compliance.
- Add backend verification of purchase receipts.
- Show clear upgrade UI only when needed.

## Phase 5: Reliability And QA

Focus: reduce the chance friends hit obvious breakage.

- Create a manual iPad QA checklist.
- Add backend tests for auth, usage limits, and AI request blocking.
- Add basic Swift tests for auth/session parsing where practical.
- Test on iPad portrait and landscape.
- Test slow network and Render cold start behavior.
- Track bugs in GitHub issues.

## Phase 6: Product Feedback

Focus: learn what students actually need.

- Ask testers:
  - Did AI Lens save time?
  - Was importing homework easy?
  - Did the AI feedback feel trustworthy?
  - Did drawing/zooming feel natural?
  - What made them want to go back to Notability?
- Review Supabase usage patterns.
- Watch for abandoned onboarding or failed scans.
- Prioritize fixes based on repeated tester pain.

## Immediate Next Steps

1. Review these docs and edit anything that does not match the BetterNotes vision.
2. Fix the bug Miles found during real homework/testing.
3. Push current working prototype to GitHub.
4. Start a TestFlight readiness checklist.
5. Decide whether sync or TestFlight comes first.

