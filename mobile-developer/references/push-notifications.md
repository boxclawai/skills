# Push Notifications Reference

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Firebase Cloud Messaging (FCM)](#firebase-cloud-messaging)
3. [Apple Push Notification Service (APNs)](#apple-push-notification-service)
4. [React Native Implementation](#react-native-implementation)
5. [Flutter Implementation](#flutter-implementation)
6. [Server-Side Sending](#server-side-sending)
7. [Best Practices](#best-practices)

---

## Architecture Overview

```
App → Register for push → Get device token
App → Send token to your server → Store in DB
Your Server → Send notification → FCM/APNs → Device → App

Flow:
  1. App requests push permission (user grants)
  2. OS returns device token (FCM token for Android, APNs token for iOS)
  3. App sends token to backend API
  4. Backend stores: { userId, deviceToken, platform, createdAt }
  5. When event occurs, backend sends push via FCM/APNs
  6. Device receives and displays notification
  7. User taps → app opens with deep link data
```

---

## Firebase Cloud Messaging

### Setup

```
Android: google-services.json in android/app/
iOS: GoogleService-Info.plist in ios/Runner/ or ios/

Firebase Console → Project Settings → Cloud Messaging
  - Server key (legacy) or Service Account (v1 API)
  - Prefer HTTP v1 API (OAuth2, per-platform customization)
```

### Message Types

```json
// Notification message (handled by OS when app in background)
{
  "message": {
    "token": "device_token_here",
    "notification": {
      "title": "New Order",
      "body": "Order #1234 has been shipped"
    },
    "data": {
      "orderId": "1234",
      "screen": "order-detail"
    }
  }
}

// Data-only message (always handled by app, no auto-display)
{
  "message": {
    "token": "device_token_here",
    "data": {
      "type": "CHAT_MESSAGE",
      "chatId": "abc123",
      "senderName": "John",
      "messagePreview": "Hey, are you free?"
    }
  }
}

// Platform-specific customization
{
  "message": {
    "token": "device_token_here",
    "notification": {
      "title": "Sale Alert",
      "body": "50% off everything today!"
    },
    "android": {
      "notification": {
        "channel_id": "promotions",
        "icon": "ic_sale",
        "color": "#FF5722",
        "click_action": "OPEN_SALE"
      },
      "priority": "high"
    },
    "apns": {
      "payload": {
        "aps": {
          "badge": 1,
          "sound": "sale.aiff",
          "category": "SALE_CATEGORY"
        }
      }
    }
  }
}
```

---

## React Native Implementation

### Using @react-native-firebase/messaging

```typescript
import messaging from '@react-native-firebase/messaging';
import notifee, { AndroidImportance } from '@notifee/react-native';
import { Platform, PermissionsAndroid } from 'react-native';

// 1. Request permission
async function requestNotificationPermission(): Promise<boolean> {
  if (Platform.OS === 'ios') {
    const authStatus = await messaging().requestPermission();
    return (
      authStatus === messaging.AuthorizationStatus.AUTHORIZED ||
      authStatus === messaging.AuthorizationStatus.PROVISIONAL
    );
  }

  // Android 13+ requires runtime permission
  if (Platform.OS === 'android' && Platform.Version >= 33) {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS,
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  }

  return true; // Android < 13 doesn't need runtime permission
}

// 2. Get and register token
async function registerDeviceToken() {
  const token = await messaging().getToken();
  console.log('FCM Token:', token);

  // Send to your backend
  await api.post('/devices/register', {
    token,
    platform: Platform.OS,
  });

  // Listen for token refresh
  messaging().onTokenRefresh(async (newToken) => {
    await api.post('/devices/register', {
      token: newToken,
      platform: Platform.OS,
    });
  });
}

// 3. Handle notifications

// Foreground: app is open
messaging().onMessage(async (remoteMessage) => {
  // Display local notification using Notifee
  await notifee.displayNotification({
    title: remoteMessage.notification?.title,
    body: remoteMessage.notification?.body,
    data: remoteMessage.data,
    android: {
      channelId: 'default',
      importance: AndroidImportance.HIGH,
      pressAction: { id: 'default' },
    },
  });
});

// Background: app is in background (headless JS)
messaging().setBackgroundMessageHandler(async (remoteMessage) => {
  console.log('Background message:', remoteMessage.messageId);
  // Process silently or display custom notification
});

// User tapped notification (app was killed or background)
messaging().onNotificationOpenedApp((remoteMessage) => {
  navigateToScreen(remoteMessage.data);
});

// App opened from killed state via notification
messaging()
  .getInitialNotification()
  .then((remoteMessage) => {
    if (remoteMessage) {
      navigateToScreen(remoteMessage.data);
    }
  });

// 4. Navigation helper
function navigateToScreen(data?: Record<string, string>) {
  if (!data) return;
  switch (data.screen) {
    case 'order-detail':
      navigation.navigate('OrderDetail', { orderId: data.orderId });
      break;
    case 'chat':
      navigation.navigate('Chat', { chatId: data.chatId });
      break;
    default:
      navigation.navigate('Home');
  }
}

// 5. Android notification channels (create on app start)
async function createNotificationChannels() {
  await notifee.createChannel({
    id: 'default',
    name: 'Default',
    importance: AndroidImportance.HIGH,
  });
  await notifee.createChannel({
    id: 'chat',
    name: 'Chat Messages',
    importance: AndroidImportance.HIGH,
    sound: 'message',
  });
  await notifee.createChannel({
    id: 'promotions',
    name: 'Promotions',
    importance: AndroidImportance.DEFAULT,
  });
}
```

---

## Flutter Implementation

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return;
    }

    // Get token
    final token = await _messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    // Token refresh
    _messaging.onTokenRefresh.listen(_registerToken);

    // Initialize local notifications (for foreground display)
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android notification channel
    const channel = AndroidNotificationChannel(
      'default',
      'Default Notifications',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background tap (app was in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Killed state tap
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }
  }

  Future<void> _registerToken(String token) async {
    await api.registerDevice(token: token, platform: Platform.operatingSystem);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'default', 'Default Notifications',
          importance: Importance.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    switch (data['screen']) {
      case 'order-detail':
        navigator.pushNamed('/orders/${data["orderId"]}');
        break;
      case 'chat':
        navigator.pushNamed('/chat/${data["chatId"]}');
        break;
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      // Navigate based on data
    }
  }
}

// Background handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Process silently
}
```

---

## Server-Side Sending

### Node.js with Firebase Admin SDK

```typescript
import { initializeApp, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

initializeApp({
  credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT!)),
});

const messaging = getMessaging();

// Send to single device
async function sendToDevice(token: string, title: string, body: string, data?: Record<string, string>) {
  try {
    const messageId = await messaging.send({
      token,
      notification: { title, body },
      data,
      android: { priority: 'high' },
      apns: { payload: { aps: { badge: 1, sound: 'default' } } },
    });
    return { success: true, messageId };
  } catch (error: any) {
    if (error.code === 'messaging/registration-token-not-registered') {
      // Token expired → remove from DB
      await db.deviceToken.delete({ where: { token } });
    }
    throw error;
  }
}

// Send to multiple devices (batched, max 500 per batch)
async function sendToMultipleDevices(
  tokens: string[],
  notification: { title: string; body: string },
  data?: Record<string, string>,
) {
  const batchSize = 500;
  const results: { successCount: number; failureCount: number; invalidTokens: string[] } = {
    successCount: 0,
    failureCount: 0,
    invalidTokens: [],
  };

  for (let i = 0; i < tokens.length; i += batchSize) {
    const batch = tokens.slice(i, i + batchSize);
    const response = await messaging.sendEachForMulticast({
      tokens: batch,
      notification,
      data,
    });

    results.successCount += response.successCount;
    results.failureCount += response.failureCount;

    response.responses.forEach((resp, idx) => {
      if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
        results.invalidTokens.push(batch[idx]);
      }
    });
  }

  // Clean up invalid tokens
  if (results.invalidTokens.length > 0) {
    await db.deviceToken.deleteMany({
      where: { token: { in: results.invalidTokens } },
    });
  }

  return results;
}

// Topic-based (subscribe users to topics)
async function sendToTopic(topic: string, title: string, body: string) {
  return messaging.send({
    topic,
    notification: { title, body },
  });
}
```

---

## Best Practices

```
Permission:
  - Ask at contextual moment (not on first launch)
  - Explain value before requesting ("Get notified when your order ships")
  - Provide in-app notification preferences
  - Handle permission denied gracefully

Content:
  - Keep title < 50 chars, body < 150 chars
  - Be actionable: "Your order shipped" > "Order update"
  - Include deep link data for navigation
  - Use notification categories/actions (Reply, Mark as Read)

Frequency:
  - Respect user preferences (categories: chat, orders, promotions)
  - Don't send more than 3-5 non-critical pushes per day
  - Batch low-priority notifications
  - Use quiet hours (no pushes 10PM-8AM unless urgent)

Reliability:
  - Handle token refresh (re-register on every app launch)
  - Clean up invalid tokens (remove on 404/unregistered error)
  - Use topics for broadcast (not individual sends)
  - Retry transient failures with exponential backoff
  - Log delivery status for debugging

Testing:
  - FCM has a test message feature in Firebase Console
  - Use FCM HTTP v1 API with dry_run for validation
  - Test all states: foreground, background, killed
  - Test deep link navigation from notification
```
