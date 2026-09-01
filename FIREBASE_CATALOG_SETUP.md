# Owedly — Firebase catalog setup

The iOS app now supports two catalog sources controlled from Firebase Realtime Database:

- `useFirebaseCatalog: true` — read `/settlementCatalog/current` from RTDB.
- `useFirebaseCatalog: false` — use the existing on-device ClassAction.org scanner.
- `catalogSourceMode` is also supported for compatibility/debugging, but the boolean switch takes priority when present.
- `allowDeviceFallback: true` — if Firebase mode fails, the app may fall back to the device scanner.

The shipped `realtime-database.json` is an importable bootstrap snapshot. It contains the scanner config plus a cached settlement catalog snapshot prepared on 2026-08-21. Until the Cloud Function is added later, replacing this JSON in RTDB is the manual catalog-refresh path.

## Firebase Console

1. Open Firebase Console → **Build → Realtime Database → Data**.
2. Use the database menu → **Import JSON**.
3. Import `realtime-database.json` from the project root.
4. Open **Rules** and replace the rules with `database.rules.json`, then publish.
5. The existing `GoogleService-Info.plist` already contains the RTDB URL for project `owedly-80568`.

## Security rules

Mobile clients can read only:

- `/appConfig/settlementScanner`
- `/settlementCatalog/current`

All client writes are denied. The catalog should therefore be replaced from Firebase Console/Admin tooling, not from the iPhone app.

## Remote switch

Edit this field in Realtime Database:

`/appConfig/settlementScanner/useFirebaseCatalog`

Values:

- `true` → Firebase catalog
- `false` → iPhone/device scanner

Keep `allowDeviceFallback` enabled during MVP testing. Set it to `false` when you want Firebase-only behavior and do not want a source-site request after a Firebase failure.

In DEBUG builds the remote config cache is capped at 15 seconds so you can flip the Firebase/device switch in Firebase Console and relaunch/test almost immediately. Production keeps the normal 1-hour config TTL. A fresh local catalog cache is tagged with its origin; if the configured source changes, the app bypasses a cache created by the other source.

## Xcode Console logs

Filter the console by:

`[Owedly][DataSource]`

Examples:

- `[Owedly][DataSource] FIREBASE ✅ loaded 65 settlements ...`
- `[Owedly][DataSource] DEVICE SCANNER ✅ parsed ...`
- `[Owedly][DataSource] LOCAL CACHE ✅ ... origin = FIREBASE ...`
- `[Owedly][DataSource] FALLBACK → DEVICE SCANNER`
- `[Owedly][DataSource] BUNDLED FALLBACK ⚠️`

## Catalog shape

The app expects:

`/settlementCatalog/current`

with:

- `schemaVersion`
- `updatedAt` (ISO-8601)
- `sourceURL`
- `count`
- `settlements` (array of Owedly `Settlement` objects)

Before replacing the snapshot manually, keep the full object valid. The app validates that the catalog exists, decodes correctly, and contains at least `minimumExpectedItems` entries before caching it locally.

## Temporary manual FULL refresh (before Cloud Functions)

A local Mac helper is included under `tools/full-snapshot`.

```bash
cd tools/full-snapshot
npm install
npm run snapshot
```

It generates `realtime-database.full.json` in the project root. Import that file through Firebase Console. This helper does not deploy anything and does not need Firebase write permissions.

The iPhone fallback scanner is also now allowed to follow up to 50 open-settlement pages and 20 upcoming-news pages when remote config selects device scanning.
