# Owedly — Realtime Database catalog migration

Realtime Database now stores both the small scanner configuration and a read-only settlement catalog snapshot.

## Firebase Console

1. Open **Build → Realtime Database**.
2. In **Data**, choose **Import JSON** and import `realtime-database.json`.
3. In **Rules**, replace the rules with `database.rules.json` and publish.
4. Verify these nodes exist:
   - `/appConfig/settlementScanner`
   - `/settlementCatalog/current`
5. Keep `useFirebaseCatalog = true` for normal MVP operation.

## Security

The mobile app can read only the config and current catalog snapshot. All client writes are denied. Firebase Console/Admin access can still replace the snapshot manually.

## Later automation

The scheduled Cloud Function is intentionally not included in this version. It can later replace `/settlementCatalog/current` only after a complete parse/validation succeeds.
