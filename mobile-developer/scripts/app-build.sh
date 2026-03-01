#!/usr/bin/env bash
# app-build.sh - Build mobile apps for React Native / Flutter
# Usage: ./app-build.sh <platform> [--framework rn|flutter] [--mode debug|release]
#
# Platforms: ios, android, all
# Handles code signing, version bumping, and build output

set -euo pipefail

PLATFORM="${1:?Usage: $0 <ios|android|all> [--framework rn|flutter] [--mode debug|release]}"
FRAMEWORK=""
MODE="debug"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework) FRAMEWORK="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "======================================"
echo "  Mobile App Build"
echo "======================================"
echo "  Platform:  $PLATFORM"
echo "  Framework: $FRAMEWORK"
echo "  Mode:      $MODE"
echo "======================================"
echo ""

# Auto-detect framework only if not explicitly provided via --framework
if [[ -z "$FRAMEWORK" ]]; then
  if [[ -f "app.json" ]] || [[ -f "metro.config.js" ]]; then
    FRAMEWORK="rn"
  elif [[ -f "pubspec.yaml" ]]; then
    FRAMEWORK="flutter"
  else
    FRAMEWORK="rn"
  fi
fi

build_rn_android() {
  echo "=== Building React Native Android ($MODE) ==="
  cd android

  if [[ "$MODE" == "release" ]]; then
    # Clean
    ./gradlew clean

    # Check signing config
    if ! grep -q "MYAPP_UPLOAD_KEY_PASSWORD" gradle.properties 2>/dev/null; then
      echo "WARNING: Release signing not configured in gradle.properties"
      echo "Required: MYAPP_UPLOAD_STORE_FILE, MYAPP_UPLOAD_KEY_ALIAS, MYAPP_UPLOAD_STORE_PASSWORD, MYAPP_UPLOAD_KEY_PASSWORD"
    fi

    ./gradlew assembleRelease
    APK_PATH="app/build/outputs/apk/release/app-release.apk"

    # Also build AAB for Play Store
    ./gradlew bundleRelease
    AAB_PATH="app/build/outputs/bundle/release/app-release.aab"

    echo ""
    echo "Build outputs:"
    [[ -f "$APK_PATH" ]] && echo "  APK: $(pwd)/$APK_PATH ($(du -h "$APK_PATH" | cut -f1))"
    [[ -f "$AAB_PATH" ]] && echo "  AAB: $(pwd)/$AAB_PATH ($(du -h "$AAB_PATH" | cut -f1))"
  else
    ./gradlew assembleDebug
    APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
    echo "Debug APK: $(pwd)/$APK_PATH"
  fi

  cd ..
}

build_rn_ios() {
  echo "=== Building React Native iOS ($MODE) ==="

  # Install pods if needed
  if [[ ! -d "ios/Pods" ]]; then
    echo "Installing CocoaPods..."
    cd ios && pod install && cd ..
  fi

  cd ios

  if [[ "$MODE" == "release" ]]; then
    xcodebuild \
      -workspace *.xcworkspace \
      -scheme "$(ls *.xcworkspace | sed 's/.xcworkspace//')" \
      -configuration Release \
      -sdk iphoneos \
      -archivePath build/archive.xcarchive \
      archive

    echo ""
    echo "Archive created: ios/build/archive.xcarchive"
    echo "Export with: xcodebuild -exportArchive -archivePath build/archive.xcarchive -exportPath build/ipa -exportOptionsPlist ExportOptions.plist"
  else
    xcodebuild \
      -workspace *.xcworkspace \
      -scheme "$(ls *.xcworkspace | sed 's/.xcworkspace//')" \
      -configuration Debug \
      -sdk iphonesimulator \
      -destination "platform=iOS Simulator,name=iPhone 16" \
      build

    echo "Debug build complete for iOS Simulator"
  fi

  cd ..
}

build_flutter_android() {
  echo "=== Building Flutter Android ($MODE) ==="

  if [[ "$MODE" == "release" ]]; then
    flutter build apk --release
    flutter build appbundle --release
    echo ""
    echo "Build outputs:"
    echo "  APK: build/app/outputs/flutter-apk/app-release.apk"
    echo "  AAB: build/app/outputs/bundle/release/app-release.aab"
  else
    flutter build apk --debug
    echo "Debug APK: build/app/outputs/flutter-apk/app-debug.apk"
  fi
}

build_flutter_ios() {
  echo "=== Building Flutter iOS ($MODE) ==="

  if [[ "$MODE" == "release" ]]; then
    flutter build ios --release --no-codesign
    echo ""
    echo "Build output: build/ios/iphoneos/Runner.app"
    echo "For App Store: open ios/Runner.xcworkspace in Xcode and archive"
  else
    flutter build ios --debug --simulator
    echo "Debug build complete for iOS Simulator"
  fi
}

# Execute builds
case "$FRAMEWORK" in
  rn)
    case "$PLATFORM" in
      android) build_rn_android ;;
      ios)     build_rn_ios ;;
      all)     build_rn_android && build_rn_ios ;;
      *)       echo "Unknown platform: $PLATFORM"; exit 1 ;;
    esac
    ;;
  flutter)
    case "$PLATFORM" in
      android) build_flutter_android ;;
      ios)     build_flutter_ios ;;
      all)     build_flutter_android && build_flutter_ios ;;
      *)       echo "Unknown platform: $PLATFORM"; exit 1 ;;
    esac
    ;;
  *)
    echo "Unknown framework: $FRAMEWORK"
    exit 1
    ;;
esac

echo ""
echo "Build complete!"
