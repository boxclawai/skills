# Native Device APIs Reference

Cross-platform reference for accessing native device capabilities in React Native and Flutter.
Covers camera, location, biometrics, filesystem, secure storage, deep linking, permissions,
and native module bridging with production error-handling patterns.

## Table of Contents

1. [Camera & Image Picker](#1-camera--image-picker)
2. [Geolocation](#2-geolocation)
3. [Biometric Authentication](#3-biometric-authentication)
4. [File System](#4-file-system)
5. [Keychain / Keystore (Secure Storage)](#5-keychain--keystore-secure-storage)
6. [Deep Linking & Universal Links](#6-deep-linking--universal-links)
7. [Runtime Permissions](#7-runtime-permissions)
8. [Native Modules / Platform Channels](#8-native-modules--platform-channels)
9. [Quick Reference Table](#quick-reference-table)

---

## 1. Camera & Image Picker

### React Native -- react-native-image-picker

```typescript
import { launchCamera, launchImageLibrary, Asset, ImagePickerResponse } from 'react-native-image-picker';

interface CaptureResult {
  uri: string;
  width: number;
  height: number;
  fileSize: number;
  type: string;
}

async function capturePhoto(): Promise<CaptureResult | null> {
  try {
    const response: ImagePickerResponse = await launchCamera({
      mediaType: 'photo',
      cameraType: 'back',
      maxWidth: 1920,
      maxHeight: 1080,
      quality: 0.8,
      saveToPhotos: false,
    });

    if (response.didCancel) return null;
    if (response.errorCode) {
      throw new Error(`Camera error [${response.errorCode}]: ${response.errorMessage}`);
    }

    const asset: Asset = response.assets?.[0]!;
    return {
      uri: asset.uri!,
      width: asset.width!,
      height: asset.height!,
      fileSize: asset.fileSize!,
      type: asset.type ?? 'image/jpeg',
    };
  } catch (error) {
    console.error('capturePhoto failed:', error);
    throw error;
  }
}

async function pickFromGallery(selectionLimit = 1): Promise<CaptureResult[]> {
  const response = await launchImageLibrary({
    mediaType: 'photo',
    selectionLimit,
    quality: 0.8,
  });

  if (response.didCancel || !response.assets) return [];
  if (response.errorCode) {
    throw new Error(`Gallery error [${response.errorCode}]: ${response.errorMessage}`);
  }

  return response.assets.map((asset) => ({
    uri: asset.uri!,
    width: asset.width!,
    height: asset.height!,
    fileSize: asset.fileSize!,
    type: asset.type ?? 'image/jpeg',
  }));
}
```

### Flutter -- image_picker / camera

```dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> capturePhoto({int maxWidth = 1920, int quality = 80}) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth.toDouble(),
        imageQuality: quality,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (xfile == null) return null; // user cancelled
      return File(xfile.path);
    } on PlatformException catch (e) {
      throw Exception('Camera access denied or unavailable: ${e.message}');
    }
  }

  Future<List<File>> pickMultipleImages({int quality = 80}) async {
    try {
      final List<XFile> xfiles = await _picker.pickMultiImage(
        imageQuality: quality,
      );
      return xfiles.map((xf) => File(xf.path)).toList();
    } on PlatformException catch (e) {
      throw Exception('Gallery access denied: ${e.message}');
    }
  }
}
```

---

## 2. Geolocation

### React Native -- react-native-geolocation-service

```typescript
import Geolocation, {
  GeoPosition,
  GeoError,
} from 'react-native-geolocation-service';
import { Platform, PermissionsAndroid } from 'react-native';

interface LocationCoords {
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude: number | null;
  speed: number | null;
  timestamp: number;
}

async function requestLocationPermission(): Promise<boolean> {
  if (Platform.OS === 'ios') return true; // handled via Info.plist prompt

  const granted = await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
    {
      title: 'Location Permission',
      message: 'This app needs access to your location.',
      buttonPositive: 'Allow',
    },
  );
  return granted === PermissionsAndroid.RESULTS.GRANTED;
}

function getCurrentPosition(): Promise<LocationCoords> {
  return new Promise((resolve, reject) => {
    Geolocation.getCurrentPosition(
      (position: GeoPosition) => {
        resolve({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          altitude: position.coords.altitude,
          speed: position.coords.speed,
          timestamp: position.timestamp,
        });
      },
      (error: GeoError) => {
        reject(new Error(`Geolocation error [${error.code}]: ${error.message}`));
      },
      {
        enableHighAccuracy: true,
        timeout: 15000,
        maximumAge: 10000,
        forceRequestLocation: true,
      },
    );
  });
}

function watchPosition(
  onUpdate: (coords: LocationCoords) => void,
  onError: (error: Error) => void,
): () => void {
  const watchId = Geolocation.watchPosition(
    (position) => {
      onUpdate({
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        accuracy: position.coords.accuracy,
        altitude: position.coords.altitude,
        speed: position.coords.speed,
        timestamp: position.timestamp,
      });
    },
    (error) => onError(new Error(`Watch error [${error.code}]: ${error.message}`)),
    {
      enableHighAccuracy: true,
      distanceFilter: 10, // meters
      interval: 5000,
      fastestInterval: 2000,
    },
  );

  return () => Geolocation.clearWatch(watchId);
}
```

### Flutter -- geolocator

```dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled on the device.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied by user.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied. Open app settings to grant access.',
      );
    }
    return true;
  }

  Future<Position> getCurrentPosition() async {
    await ensurePermission();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Stream<Position> watchPosition({int distanceFilter = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    );
  }

  double distanceBetween(Position a, Position b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude,
      b.latitude, b.longitude,
    );
  }
}
```

---

## 3. Biometric Authentication

### React Native -- react-native-biometrics

```typescript
import ReactNativeBiometrics, { BiometryType } from 'react-native-biometrics';

const biometrics = new ReactNativeBiometrics({ allowDeviceCredentials: true });

interface BiometricCapability {
  available: boolean;
  biometryType: 'FaceID' | 'TouchID' | 'Biometrics' | null;
}

async function checkBiometricCapability(): Promise<BiometricCapability> {
  const { available, biometryType } = await biometrics.isSensorAvailable();
  return {
    available,
    biometryType: biometryType ?? null,
  };
}

async function authenticateUser(promptMessage: string): Promise<boolean> {
  const { available } = await checkBiometricCapability();
  if (!available) {
    throw new Error('Biometric authentication is not available on this device.');
  }

  try {
    const { success } = await biometrics.simplePrompt({
      promptMessage,
      cancelButtonText: 'Cancel',
      fallbackPromptMessage: 'Use passcode',
    });
    return success;
  } catch (error) {
    // User cancelled or authentication failed
    return false;
  }
}

// Cryptographic signature flow for server verification
async function createBiometricKeypair(): Promise<string> {
  const { publicKey } = await biometrics.createKeys();
  // Send publicKey to server for registration
  return publicKey;
}

async function signChallenge(challenge: string): Promise<string | null> {
  try {
    const { success, signature } = await biometrics.createSignature({
      promptMessage: 'Confirm your identity',
      payload: challenge,
    });
    return success ? signature : null;
  } catch {
    return null;
  }
}
```

### Flutter -- local_auth

```dart
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> get isAvailable async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return <BiometricType>[];
    }
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow passcode fallback
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notEnrolled:
          throw Exception('No biometrics enrolled on this device.');
        case auth_error.lockedOut:
          throw Exception('Too many attempts. Biometrics locked.');
        case auth_error.permanentlyLockedOut:
          throw Exception('Biometrics permanently locked. Use device passcode.');
        default:
          throw Exception('Authentication error: ${e.message}');
      }
    }
  }
}
```

---

## 4. File System

### React Native -- react-native-fs

```typescript
import RNFS from 'react-native-fs';

const DOCS_DIR = RNFS.DocumentDirectoryPath;

async function writeJsonFile(filename: string, data: object): Promise<string> {
  const path = `${DOCS_DIR}/${filename}`;
  try {
    await RNFS.writeFile(path, JSON.stringify(data, null, 2), 'utf8');
    return path;
  } catch (error) {
    throw new Error(`Failed to write ${filename}: ${(error as Error).message}`);
  }
}

async function readJsonFile<T>(filename: string): Promise<T> {
  const path = `${DOCS_DIR}/${filename}`;
  const exists = await RNFS.exists(path);
  if (!exists) {
    throw new Error(`File not found: ${filename}`);
  }

  const content = await RNFS.readFile(path, 'utf8');
  return JSON.parse(content) as T;
}

async function deleteFile(filename: string): Promise<void> {
  const path = `${DOCS_DIR}/${filename}`;
  const exists = await RNFS.exists(path);
  if (exists) {
    await RNFS.unlink(path);
  }
}

async function listDirectory(subdir = ''): Promise<RNFS.ReadDirItem[]> {
  const path = subdir ? `${DOCS_DIR}/${subdir}` : DOCS_DIR;
  return RNFS.readDir(path);
}

async function downloadToFile(url: string, filename: string): Promise<string> {
  const destPath = `${RNFS.CachesDirectoryPath}/${filename}`;
  const result = await RNFS.downloadFile({
    fromUrl: url,
    toFile: destPath,
    discretionary: true,
    cacheable: false,
  }).promise;

  if (result.statusCode !== 200) {
    throw new Error(`Download failed with status ${result.statusCode}`);
  }
  return destPath;
}
```

### Flutter -- path_provider + dart:io

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileService {
  Future<Directory> get _docsDir async => getApplicationDocumentsDirectory();
  Future<Directory> get _cacheDir async => getTemporaryDirectory();

  Future<String> writeJsonFile(String filename, Map<String, dynamic> data) async {
    final dir = await _docsDir;
    final file = File('${dir.path}/$filename');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data), flush: true);
    return file.path;
  }

  Future<Map<String, dynamic>> readJsonFile(String filename) async {
    final dir = await _docsDir;
    final file = File('${dir.path}/$filename');
    if (!await file.exists()) {
      throw FileSystemException('File not found', file.path);
    }
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> deleteFile(String filename) async {
    final dir = await _docsDir;
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<FileSystemEntity>> listDirectory({String subdir = ''}) async {
    final dir = await _docsDir;
    final target = subdir.isEmpty ? dir : Directory('${dir.path}/$subdir');
    if (!await target.exists()) return [];
    return target.listSync();
  }

  Future<int> getDirectorySize(Directory dir) async {
    int totalSize = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
    return totalSize;
  }
}
```

---

## 5. Keychain / Keystore (Secure Storage)

### React Native -- react-native-keychain

```typescript
import * as Keychain from 'react-native-keychain';

const SERVICE_NAME = 'com.myapp.auth';

async function storeCredentials(key: string, value: string): Promise<void> {
  try {
    await Keychain.setGenericPassword(key, value, {
      service: SERVICE_NAME,
      accessControl: Keychain.ACCESS_CONTROL.BIOMETRY_CURRENT_SET_OR_DEVICE_PASSCODE,
      accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      securityLevel: Keychain.SECURITY_LEVEL.SECURE_HARDWARE,
    });
  } catch (error) {
    throw new Error(`Secure store failed: ${(error as Error).message}`);
  }
}

async function getCredentials(): Promise<{ key: string; value: string } | null> {
  try {
    const result = await Keychain.getGenericPassword({ service: SERVICE_NAME });
    if (result === false) return null;
    return { key: result.username, value: result.password };
  } catch (error) {
    throw new Error(`Secure read failed: ${(error as Error).message}`);
  }
}

async function removeCredentials(): Promise<void> {
  await Keychain.resetGenericPassword({ service: SERVICE_NAME });
}

// Token management built on top of keychain
class SecureTokenStore {
  static async saveTokens(access: string, refresh: string): Promise<void> {
    await storeCredentials('tokens', JSON.stringify({ access, refresh }));
  }

  static async getAccessToken(): Promise<string | null> {
    const creds = await getCredentials();
    if (!creds) return null;
    const tokens = JSON.parse(creds.value);
    return tokens.access ?? null;
  }

  static async getRefreshToken(): Promise<string | null> {
    const creds = await getCredentials();
    if (!creds) return null;
    const tokens = JSON.parse(creds.value);
    return tokens.refresh ?? null;
  }

  static async clear(): Promise<void> {
    await removeCredentials();
  }
}
```

### Flutter -- flutter_secure_storage

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}

class TokenManager {
  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';
  final _store = SecureStorageService();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _store.write(_accessKey, accessToken),
      _store.write(_refreshKey, refreshToken),
    ]);
  }

  Future<String?> get accessToken => _store.read(_accessKey);
  Future<String?> get refreshToken => _store.read(_refreshKey);

  Future<void> clear() async {
    await Future.wait([
      _store.delete(_accessKey),
      _store.delete(_refreshKey),
    ]);
  }
}
```

---

## 6. Deep Linking & Universal Links

### React Native

**iOS -- apple-app-site-association (hosted at `https://yourdomain.com/.well-known/`):**

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["TEAMID.com.myapp.bundle"],
        "components": [
          { "/": "/product/*", "comment": "Product detail pages" },
          { "/": "/invite/*", "comment": "Invite links" }
        ]
      }
    ]
  }
}
```

**Android -- AndroidManifest.xml intent filter:**

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="yourdomain.com" android:pathPrefix="/product" />
</intent-filter>
```

**Handling in JS:**

```typescript
import { Linking } from 'react-native';

type RouteHandler = (params: Record<string, string>) => void;

class DeepLinkRouter {
  private routes: Map<RegExp, RouteHandler> = new Map();

  register(pattern: string, handler: RouteHandler): void {
    // Convert "/product/:id" to a regex with named groups
    const regexStr = pattern.replace(/:(\w+)/g, '(?<$1>[^/]+)');
    this.routes.set(new RegExp(`^${regexStr}$`), handler);
  }

  async initialize(): Promise<void> {
    // Handle cold start
    const initialUrl = await Linking.getInitialURL();
    if (initialUrl) this.handleUrl(initialUrl);

    // Handle background-to-foreground
    Linking.addEventListener('url', ({ url }) => this.handleUrl(url));
  }

  private handleUrl(url: string): void {
    try {
      const parsed = new URL(url);
      const path = parsed.pathname;

      for (const [regex, handler] of this.routes) {
        const match = path.match(regex);
        if (match?.groups) {
          handler(match.groups);
          return;
        }
      }
      console.warn('No deep link handler matched:', path);
    } catch (error) {
      console.error('Deep link parse error:', error);
    }
  }
}

// Usage
const router = new DeepLinkRouter();
router.register('/product/:id', ({ id }) => {
  navigation.navigate('ProductDetail', { productId: id });
});
router.register('/invite/:code', ({ code }) => {
  navigation.navigate('AcceptInvite', { inviteCode: code });
});
router.initialize();
```

### Flutter

**Handling with go_router (recommended):**

```dart
import 'package:go_router/go_router.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/product/:id',
      builder: (context, state) {
        final productId = state.pathParameters['id']!;
        return ProductDetailScreen(productId: productId);
      },
    ),
    GoRoute(
      path: '/invite/:code',
      builder: (context, state) {
        final code = state.pathParameters['code']!;
        return AcceptInviteScreen(inviteCode: code);
      },
    ),
  ],
);

// In MaterialApp
MaterialApp.router(routerConfig: router);
```

**Manual handling with app_links (lower-level control):**

```dart
import 'package:app_links/app_links.dart';
import 'dart:async';

class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> initialize(void Function(Uri uri) onLink) async {
    // Cold start
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) onLink(initialUri);

    // Foreground stream
    _sub = _appLinks.uriLinkStream.listen(
      (Uri uri) => onLink(uri),
      onError: (err) => print('Deep link stream error: $err'),
    );
  }

  void dispose() {
    _sub?.cancel();
  }
}
```

---

## 7. Runtime Permissions

### React Native -- react-native-permissions

```typescript
import {
  check,
  request,
  PERMISSIONS,
  RESULTS,
  Permission,
  PermissionStatus,
  openSettings,
} from 'react-native-permissions';
import { Platform, Alert } from 'react-native';

type PermissionResult = 'granted' | 'denied' | 'blocked' | 'unavailable';

async function requestPermission(permission: Permission): Promise<PermissionResult> {
  const status: PermissionStatus = await check(permission);

  switch (status) {
    case RESULTS.GRANTED:
    case RESULTS.LIMITED:
      return 'granted';

    case RESULTS.DENIED: {
      const result = await request(permission);
      return result === RESULTS.GRANTED ? 'granted' : 'denied';
    }

    case RESULTS.BLOCKED:
      Alert.alert(
        'Permission Required',
        'This feature needs a permission you previously denied. Open settings to grant it.',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Open Settings', onPress: () => openSettings() },
        ],
      );
      return 'blocked';

    case RESULTS.UNAVAILABLE:
      return 'unavailable';

    default:
      return 'denied';
  }
}

// Platform-aware permission selectors
function cameraPermission(): Permission {
  return Platform.OS === 'ios'
    ? PERMISSIONS.IOS.CAMERA
    : PERMISSIONS.ANDROID.CAMERA;
}

function locationPermission(): Permission {
  return Platform.OS === 'ios'
    ? PERMISSIONS.IOS.LOCATION_WHEN_IN_USE
    : PERMISSIONS.ANDROID.ACCESS_FINE_LOCATION;
}
```

### Flutter -- permission_handler

```dart
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestPermission(Permission permission) async {
    final status = await permission.status;

    if (status.isGranted) return true;

    if (status.isDenied) {
      final result = await permission.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      final opened = await openAppSettings();
      if (!opened) {
        throw Exception('Cannot open app settings.');
      }
      return false; // User must return to the app after granting
    }

    return false;
  }

  Future<Map<Permission, PermissionStatus>> requestMultiple(
    List<Permission> permissions,
  ) async {
    return permissions.request();
  }

  // Convenience methods
  Future<bool> ensureCamera() => requestPermission(Permission.camera);
  Future<bool> ensureLocation() => requestPermission(Permission.locationWhenInUse);
  Future<bool> ensurePhotos() => requestPermission(Permission.photos);
  Future<bool> ensureNotifications() => requestPermission(Permission.notification);
}
```

---

## 8. Native Modules / Platform Channels

### React Native -- Native Module (iOS example in Swift)

**Swift module (`ios/BatteryModule.swift`):**

```swift
import Foundation

@objc(BatteryModule)
class BatteryModule: NSObject {

  @objc func getBatteryLevel(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    DispatchQueue.main.async {
      UIDevice.current.isBatteryMonitoringEnabled = true
      let level = UIDevice.current.batteryLevel
      if level < 0 {
        reject("UNAVAILABLE", "Battery level not available on simulator", nil)
      } else {
        resolve(level * 100)
      }
    }
  }

  @objc static func requiresMainQueueSetup() -> Bool { return false }
}
```

**Bridge header (`ios/BatteryModuleBridge.m`):**

```objc
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(BatteryModule, NSObject)
RCT_EXTERN_METHOD(getBatteryLevel:
                  (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
@end
```

**TypeScript wrapper:**

```typescript
import { NativeModules, Platform } from 'react-native';

const { BatteryModule } = NativeModules;

export async function getBatteryLevel(): Promise<number> {
  if (Platform.OS !== 'ios') {
    throw new Error('BatteryModule is only available on iOS');
  }
  if (!BatteryModule) {
    throw new Error('BatteryModule native module is not linked.');
  }
  return BatteryModule.getBatteryLevel();
}
```

### Flutter -- Platform Channels

**Dart side:**

```dart
import 'package:flutter/services.dart';

class BatteryChannel {
  static const _channel = MethodChannel('com.myapp/battery');

  static Future<int> getBatteryLevel() async {
    try {
      final int level = await _channel.invokeMethod('getBatteryLevel');
      return level;
    } on PlatformException catch (e) {
      throw Exception('Failed to get battery level: ${e.message}');
    } on MissingPluginException {
      throw Exception('Battery plugin not registered on this platform.');
    }
  }

  // EventChannel for continuous updates
  static const _eventChannel = EventChannel('com.myapp/battery_stream');

  static Stream<int> get batteryLevelStream {
    return _eventChannel.receiveBroadcastStream().map((event) => event as int);
  }
}
```

**iOS native side (Swift):**

```swift
import Flutter
import UIKit

class BatteryChannelHandler {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.myapp/battery",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getBatteryLevel":
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 {
          result(FlutterError(
            code: "UNAVAILABLE",
            message: "Battery info not available",
            details: nil
          ))
        } else {
          result(Int(level * 100))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
```

**Android native side (Kotlin):**

```kotlin
package com.myapp

import android.content.Context
import android.os.BatteryManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BatteryChannelHandler(
    private val context: Context
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBatteryLevel" -> {
                val manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (level >= 0) {
                    result.success(level)
                } else {
                    result.error("UNAVAILABLE", "Battery level not available", null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
```

---

## Quick Reference Table

| Capability | React Native Package | Flutter Package |
|---|---|---|
| Camera / Gallery | `react-native-image-picker` | `image_picker` |
| Geolocation | `react-native-geolocation-service` | `geolocator` |
| Biometrics | `react-native-biometrics` | `local_auth` |
| File System | `react-native-fs` | `path_provider` + `dart:io` |
| Secure Storage | `react-native-keychain` | `flutter_secure_storage` |
| Deep Linking | `react-native` Linking API | `go_router` / `app_links` |
| Permissions | `react-native-permissions` | `permission_handler` |
| Native Bridge | `NativeModules` (built-in) | `MethodChannel` (built-in) |

### iOS Info.plist Keys

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to take photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need photo library access to select images.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show nearby results.</string>
<key>NSFaceIDUsageDescription</key>
<string>We use Face ID to secure your account.</string>
```

### Android Manifest Permissions

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.INTERNET" />
```
