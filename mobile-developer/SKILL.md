---
name: mobile-developer
version: "1.0.0"
description: "Mobile development expert: React Native, Flutter, Swift/SwiftUI (iOS), Kotlin/Jetpack Compose (Android), cross-platform architecture, offline-first design, push notifications, app store deployment, and native device APIs (camera, GPS, sensors). Use when: (1) building mobile apps (iOS/Android), (2) implementing cross-platform features, (3) optimizing mobile performance or battery usage, (4) handling offline data sync, (5) integrating native device capabilities, (6) preparing app store submissions. NOT for: web-only applications, backend APIs, or desktop apps."
tags: [react-native, flutter, swift, kotlin, ios, android, expo, mobile, cross-platform, offline-first]
author: "boxclaw"
references:
  - references/native-apis.md
  - references/push-notifications.md
metadata:
  boxclaw:
    emoji: "📱"
    category: "programming-role"
---

# Mobile Developer

Expert guidance for building performant cross-platform and native mobile applications.

## Core Competencies

### 1. Platform Decision

```
React Native:
  + JavaScript ecosystem, code sharing with web
  + Large community, Expo simplifies setup
  - Performance ceiling for heavy animations
  Best for: teams with JS expertise, content-heavy apps

Flutter:
  + Excellent performance, custom rendering engine
  + Beautiful widgets, single codebase for iOS/Android/Web
  - Dart language (smaller ecosystem)
  Best for: custom UI-heavy apps, startups moving fast

Native (Swift/Kotlin):
  + Best performance, full platform API access
  + First-class IDE support (Xcode/Android Studio)
  - Separate codebases, higher cost
  Best for: platform-specific features, performance-critical apps
```

### 2. Project Architecture

#### React Native (Expo)

```
app/
├── src/
│   ├── screens/         # Screen components
│   ├── components/      # Reusable UI
│   ├── navigation/      # React Navigation setup
│   ├── hooks/           # Custom hooks
│   ├── services/        # API, storage, push
│   ├── stores/          # Zustand/Redux state
│   ├── utils/           # Helpers
│   └── types/           # TypeScript types
├── assets/              # Images, fonts
├── app.json             # Expo config
└── eas.json             # EAS Build config
```

#### Flutter

```
lib/
├── core/
│   ├── network/         # Dio/HTTP client
│   ├── storage/         # Hive/SharedPrefs
│   └── theme/           # ThemeData, colors
├── features/
│   ├── auth/
│   │   ├── data/        # Repository, data sources
│   │   ├── domain/      # Entities, use cases
│   │   └── presentation/# Screens, widgets, bloc
│   └── home/
├── shared/              # Shared widgets
└── main.dart
```

### 3. Offline-First Architecture

```
Strategy:
  1. Local DB as source of truth (SQLite/Realm/WatermelonDB)
  2. Sync engine pushes/pulls changes
  3. Conflict resolution (last-write-wins or merge)
  4. Queue offline mutations, replay on reconnect
  5. Optimistic UI updates

Implementation:
  Read:  Local DB → Display → Background sync → Update if changed
  Write: Write local → Queue mutation → Sync when online → Confirm
  Conflict: Server timestamp wins OR user resolves manually
```

### 4. Performance Optimization

```
React Native:
  - Use FlatList/FlashList for lists (not ScrollView+map)
  - Memoize: React.memo, useMemo, useCallback
  - Avoid bridge: use Hermes engine, JSI for native modules
  - Image: react-native-fast-image with caching
  - Animations: Reanimated (runs on UI thread)

Flutter:
  - const constructors everywhere possible
  - RepaintBoundary for complex widgets
  - ListView.builder for lazy lists
  - Isolates for heavy computation
  - Image caching: cached_network_image

General:
  - Minimize re-renders (profile with DevTools)
  - Lazy load screens/features
  - Compress images (WebP, appropriate sizes per density)
  - Bundle size: tree-shake, remove unused assets
  - Startup: defer non-critical initialization
```

### 5. Navigation Patterns

```
Stack:    Push/pop screens (detail views)
Tab:      Bottom tabs for main sections
Drawer:   Side menu for secondary navigation
Modal:    Overlay screens (forms, confirmations)

Deep Linking:
  myapp://product/123 → ProductScreen(id: 123)
  Configure: app.json (Expo) / AndroidManifest + Info.plist (native)

Auth Flow:
  Unauthenticated → Login/Register stack
  Authenticated → Main tab navigator
  Switch based on auth state (not conditional rendering)
```

### 6. App Store Deployment

```
iOS (App Store Connect):
  1. Increment version + build number
  2. Archive in Xcode / EAS Build
  3. Upload via Xcode or Transporter
  4. Submit for review (screenshots, description, privacy policy)
  5. Review takes 24-48h typically

Android (Google Play Console):
  1. Increment versionCode + versionName
  2. Build signed AAB (not APK)
  3. Upload to internal/closed/open testing track
  4. Promote to production
  5. Review takes hours to 7 days

Checklist:
  [ ] App icons (all sizes)
  [ ] Splash screen
  [ ] Screenshots (all required devices)
  [ ] Privacy policy URL
  [ ] Data safety/privacy labels
  [ ] Performance testing on low-end devices
  [ ] Crash-free rate > 99%
```

## Quick Commands

```bash
# React Native (Expo)
npx create-expo-app myapp --template blank-typescript
cd myapp && npx expo start
npx expo run:ios
npx expo run:android
eas build --platform all

# Flutter
flutter create myapp && cd myapp
flutter run
flutter build apk --release
flutter build ios --release

# React Native debug
npx react-native doctor
adb logcat *:E  # Android logs
xcrun simctl list  # iOS simulators
```

## References

- **Platform APIs**: See [references/native-apis.md](references/native-apis.md)
- **Push notifications**: See [references/push-notifications.md](references/push-notifications.md)
