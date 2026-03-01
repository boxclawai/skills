# :iphone: Mobile Developer

> Mobile development expert covering React Native, Flutter, Swift/SwiftUI, and Kotlin/Jetpack Compose. Provides guidance on cross-platform architecture, offline-first design, push notifications, app store deployment, and native device APIs.

## What's Included

### SKILL.md
Core expertise covering:
- Core Competencies
  - Platform Decision
  - Project Architecture
  - Offline-First Architecture
  - Performance Optimization
  - Navigation Patterns
  - App Store Deployment
- Quick Commands
- References

### References
| File | Description | Lines |
|------|-------------|-------|
| [native-apis.md](references/native-apis.md) | Cross-platform reference for accessing native device capabilities (camera, location, biometrics, filesystem, secure storage, deep linking, permissions, and native module bridging) | 1080 |
| [push-notifications.md](references/push-notifications.md) | Push notifications architecture, setup, and implementation reference | 472 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [app-build.sh](scripts/app-build.sh) | Build mobile apps for React Native / Flutter | `./scripts/app-build.sh <platform> [--framework rn\|flutter] [--mode debug\|release]` |

## Tags
`react-native` `flutter` `swift` `kotlin` `ios` `android` `expo` `mobile` `cross-platform` `offline-first`

## Quick Start

```bash
# Copy this skill to your project
cp -r mobile-developer/ /path/to/project/.skills/

# Build an iOS app (React Native)
.skills/mobile-developer/scripts/app-build.sh ios --framework rn --mode release

# Build an Android app (Flutter)
.skills/mobile-developer/scripts/app-build.sh android --framework flutter --mode release
```

## Part of [BoxClaw Skills](../)
