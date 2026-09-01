# Firebase setup for the Owedly MVP

## iOS app

The app uses FirebaseCore, FirebaseDatabase and FirebaseMessaging. Realtime Database is now the primary settlement-catalog source by default, while the existing on-device website scanner remains available as a remotely controlled fallback.

`GoogleService-Info.plist` belongs in `Owedly/Resources` with Owedly target membership enabled. The current plist already contains the Realtime Database URL for project `owedly-80568`.

## Realtime Database

The iOS app reads two public read-only nodes:

- `/appConfig/settlementScanner`
- `/settlementCatalog/current`

Import `realtime-database.json` into the Realtime Database Data tab and publish `database.rules.json` in the Rules tab. Client writes are denied everywhere.

Matching, claim tracking, onboarding answers and notification scheduling remain local on the iPhone. The downloaded Firebase catalog is also cached locally for the normal catalog TTL.

See `FIREBASE_CATALOG_SETUP.md` for source switching, testing and Xcode console logs.

## Push notifications / FCM

FirebaseMessaging remains enabled exactly as before. Local deadline reminders continue to be local. No onboarding/profile answers, My Claims records, or other sensitive user data are uploaded by these managers.
