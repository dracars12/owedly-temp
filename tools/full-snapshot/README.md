# Owedly manual full snapshot

This is a temporary local helper, not a Firebase Cloud Function.

```bash
cd tools/full-snapshot
npm install
npm run snapshot
```

It scans all discoverable pages of `https://www.classaction.org/settlements` (up to 50 pages), plus recent settlement announcements, and writes:

`realtime-database.full.json`

Import that file in Firebase Console → Realtime Database → Data → ⋮ → Import JSON.

The production iOS client remains read-only. Do not loosen RTDB write rules for the app.
