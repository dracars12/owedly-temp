# Owedly scanner setup

Owedly now supports a Firebase-cached catalog and the existing on-device ClassAction.org scanner.

## Remote source configuration

The app reads:

`/appConfig/settlementScanner`

Important fields:

- `useFirebaseCatalog: true | false` (recommended Firebase Console switch)
- `catalogSourceMode: "firebase" | "device"` (fallback compatibility field)
- `allowDeviceFallback: true | false`
- existing website parser URLs/selectors/page limits/timeouts
- `cacheTTLHours`
- `minimumExpectedItems`
- `allowDirectClassActionInRelease`

Default shipped mode is `firebase` with device fallback enabled.

## Firebase catalog

The cached catalog is read once from:

`/settlementCatalog/current`

After a successful Firebase fetch it is written only to the app's local file cache, tagged with origin `FIREBASE`. The iOS client never writes the remote catalog.

## Device scanner

When `useFirebaseCatalog` is `false`, or Firebase fails while `allowDeviceFallback` is true, the existing throttled ClassAction.org scanner is used. Its successful result is cached locally with origin `DEVICE SCANNER`.

## Debugging

Filter Xcode Console by `[Owedly][DataSource]` to see exactly which path was used.
