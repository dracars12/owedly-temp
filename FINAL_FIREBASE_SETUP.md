# Owedly — final Firebase catalog setup

## Final source behavior

- `useFirebaseCatalog = true`: iPhone reads the full catalog from Firebase Realtime Database.
- `allowDeviceFallback = true`: if Firebase catalog loading fails, the iPhone may use the website scanner.
- The iPhone scanner has a **hard code cap** of **5 Open pages + 3 Upcoming pages**. Firebase cannot remotely raise it above those limits.
- The on-device catalog scan is still rate-limited to no more than once per 24 hours.
- The Mac snapshot script is separate: it follows pagination until the site ends (with a high safety ceiling) and waits 1.8s between page requests.

## 1. Firebase rules

Realtime Database → Rules → replace with `database.rules.json`:

```json
{
  "rules": {
    ".read": false,
    ".write": false,
    "appConfig": {
      "settlementScanner": {
        ".read": true
      }
    },
    "settlementCatalog": {
      "current": {
        ".read": true
      }
    }
  }
}
```

The app can read config/catalog but cannot write them.

## 2. First catalog import

For a quick initial test you can import the bundled `realtime-database.json`.

Firebase Console → Realtime Database → Data → menu → Import JSON.

For the full snapshot, run from Terminal in the project root:

```bash
./refresh-firebase-catalog.sh
```

This creates:

```text
realtime-database.full.json
```

Import that file into Realtime Database. It contains both the app config and the refreshed full catalog snapshot.

## 3. Daily manual refresh

Once per day (or only when you want to refresh):

```bash
./refresh-firebase-catalog.sh
```

Then import the new `realtime-database.full.json` in Firebase Console. Do not run multiple copies in parallel.

## 4. Recommended Firebase config

```json
{
  "useFirebaseCatalog": true,
  "catalogSourceMode": "firebase",
  "allowDeviceFallback": true,
  "maxPages": 5,
  "upcomingMaxPages": 3,
  "cacheTTLHours": 24,
  "allowDirectClassActionInRelease": true
}
```

`maxPages` and `upcomingMaxPages` can be lowered remotely, but the app hard-caps them to 5 and 3.

To force-test the iPhone scanner:

```json
"useFirebaseCatalog": false
```

To force-test Firebase with no hidden website fallback:

```json
"useFirebaseCatalog": true,
"allowDeviceFallback": false
```

## 5. Xcode logs

Open Xcode → Debug area → Console and filter by:

```text
[Owedly][DataSource]
```

Firebase download:

```text
[Owedly][DataSource] configured mode = FIREBASE, deviceFallback = true
[Owedly][DataSource] FIREBASE ✅ loaded 123 settlements; snapshot updatedAt = ...
```

Local cache originally downloaded from Firebase:

```text
[Owedly][DataSource] LOCAL CACHE ✅ 123 settlements; origin = FIREBASE; age = 8m
```

Limited iPhone scanner:

```text
[Owedly][DataSource] DEVICE SCANNER selected by Firebase config (LIMITED: max 5 Open + 3 Upcoming pages)
[Owedly][DataSource] DEVICE SCANNER ✅ parsed 42 settlements from 8 page(s)
```

Firebase failed and fallback started:

```text
[Owedly][DataSource] FIREBASE ❌ failed: ...
[Owedly][DataSource] FALLBACK → DEVICE SCANNER
```

## 6. Important test note

A fresh local cache can hide a source change until the manager deliberately bypasses a cache that belongs to another source. The build handles this when the remote source mode changes. For the cleanest test you can also delete/reinstall the app or use the existing refresh path.
