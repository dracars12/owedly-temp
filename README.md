# Owedly — Class Action Settlements iOS MVP

UIKit + SnapKit implementation of Splash, Welcome, the six-step onboarding and the five-screen Intro Stage from Figma.

## Open and run

1. Open `Owedly.xcodeproj` in Xcode.
2. Let Swift Package Manager resolve **SnapKit 5.7.1**, **Firebase iOS SDK 11.11.0**, **Adapty 4.1.0** and **AppsFlyer 7.0.1**.
3. Run on an iPhone simulator/device. Store purchases require App Store sandbox/TestFlight conditions and the products published for the configured Adapty placements.
4. `GoogleService-Info.plist` must belong to the `com.giga.Owedly` Firebase app and be included in the Owedly target.

Minimum deployment target: **iOS 15.0**. iPhone / portrait.

## Implemented flow

- Launch screen + Splash with the grouped Owedly logo.
- Welcome screen with the Google “Match available” teaser.
- Six-step local onboarding.
- **Preparing Matches** is pushed after onboarding and performs the real settlement load + local matching scan.
- **Payout Insight** is pushed when the staged scan animation and scan have both completed.
- **Paywall** is presented full screen and loads the current weekly/annual products from Adapty placement `com.giga.default.placement`.
- Purchases and Restore Purchases are handled by Adapty; `PurchaseManager.isPurchased` reflects the active Adapty access level and is refreshed on launch, foreground, purchase/restore and profile delegate updates.
- The limited offer loads the annual product from `com.giga.special.placement` and derives its visible price/discount from current store data rather than hardcoded price strings.
- Closing the paywall, or finishing the success screen, returns to the underlying flow and pushes **Notifications**.
- Notifications asks for the system permission only after the user taps Finish.

## Intro Stage services

`Core/Services` now contains:

- `FirebaseBootstrap` — configures Firebase and enables Google Analytics when `GoogleService-Info.plist` exists.
- `SettlementDataManager` — on-device website catalog loader + local cache; Firebase Realtime Database is used only for tiny remote scanner configuration.
- `SettlementScanner` — reusable matching engine. `SettlementScanResult` contains both `allSettlements` and ranked `potentialMatches` for future catalog/home screens.
- `PurchaseManager` — Adapty-backed subscription state, placement/product loading, purchase, restore and entitlement updates.
- `NotificationManager` — notification permission, APNs/FCM client registration, foreground new-settlement monitoring and one-day-before local deadline reminders.


## Attribution and analytics

- AppsFlyer is initialized with SDK 7's session-ready flow and implements both conversion-data and Unified Deep Linking delegates.
- Firebase Analytics is linked through the existing Firebase SPM package and enabled after `FirebaseApp.configure()`.
- Cross-SDK event/attribution forwarding (AppsFlyer ↔ Adapty ↔ Firebase) is intentionally **not** enabled in this revision; it is reserved for the next analytics pass.
- No ATT prompt was added in this revision. Adapty and AppsFlyer advertising-ID collection is disabled in code.

## Firebase Realtime Database

The app reads `/appConfig/settlementScanner` plus the read-only `/settlementCatalog/current` snapshot. Firebase is the default catalog source; the existing on-device scanner remains available as a remotely controlled fallback. See `FIREBASE_CATALOG_SETUP.md`.

Project-root files:

- `database.rules.json` — public read only for scanner config; all client writes and all other reads denied.
- `firebase.json` — Firebase CLI rules config.
- `FIREBASE_SETUP.md` — setup and push-notification notes.

## Project structure

```text
Owedly
├── App
│   └── AppDelegate.swift
├── Core
│   ├── DesignSystem.swift
│   ├── Models.swift
│   └── Services
│       ├── FirebaseBootstrap.swift
│       ├── SettlementService.swift
│       ├── PurchaseManager.swift
│       └── NotificationManager.swift
├── UI
│   └── Components.swift
├── Screens
│   ├── Splash
│   ├── Intro
│   ├── Onboarding
│   └── IntroStage
│       ├── IntroStageComponents.swift
│       ├── PreparingMatchesViewController.swift
│       ├── PayoutInsightViewController.swift
│       ├── PaywallViewController.swift
│       ├── PaymentSuccessViewController.swift
│       └── NotificationsViewController.swift
└── Resources
```

## Design system

Reusable typography continues to use the global SF Pro helpers such as `UIFont.appBoldFont(size:)`, `appHeavyFont`, `appSemiBoldFont`, `appMediumFont` and `appRegularFont`. Shared colors, 8/12/16/24pt spacing, radii and standard control sizes remain centralized in `DesignSystem.swift`.

The new Intro Stage follows the supplied 393×852 Figma frames, including the staged loader/check animations, material cards, full-screen paywall, paywall shimmer/pulse and the system-style notification preview.
