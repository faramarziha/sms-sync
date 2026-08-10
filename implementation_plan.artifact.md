# Implementation Plan - Cross-Device Sync App (Phase 1 Scaffolding)

Build a two-part cross-device synchronization system with a **Windows Server app** and an **Android Client app** written in Flutter and Kotlin.

## User Review Required

> [!IMPORTANT]
> **Android Permissions & Play Store Policy Notice**:
> - The Android client requires runtime permissions (`READ_SMS`, `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`).
> - *Play Store Distribution Note*: Google Play Store policies strictly restrict `READ_SMS` usage unless the app is declared as the Default SMS Handler. For personal use, local developer testing, or sideloaded APKs, standard runtime permission granting works directly without being the default SMS handler.

> [!NOTE]
> **Security & Pairing**:
> - Because local WebSocket channels on LAN run unencrypted by default, a lightweight **PIN / Pairing confirmation flow** is included. Upon first client connection, the server displays a 4-digit PIN (or handshake request) that the client user enters/confirms before data transfer commences.

> [!NOTE]
> **Data Storage & Deduplication**:
> - Server stores data in a local **SQLite database** (`sqflite_common_ffi` / `sqlite3` on Windows).
> - Deduplication of SMS entries is enforced on the server side using unique constraints on `sms_id` (from Android SMS `_id`) or fallback content hash (`address + date + body`).

## Proposed Changes

### Dependencies (`pubspec.yaml`)
- `nsd: ^5.0.1` — mDNS/NSD service discovery and registration.
- `sqflite: ^2.3.0` / `sqflite_common_ffi: ^2.3.0` / `sqlite3_flutter_libs: ^0.5.20` — SQLite storage on Desktop/Mobile.
- `path: ^1.9.0` — Path manipulation for database file paths.
- `crypto: ^3.0.3` — SHA-256 for payload hashing / deduplication.
- `uuid: ^4.3.3` — Unique message envelope identification.
- `permission_handler: ^11.3.1` — Runtime permission requesting on Android.

### 1. Platform & Native Bridge (Android Kotlin)

#### [MODIFY] [AndroidManifest.xml](file:///f:/android%20pro/sms_sync/android/app/src/main/AndroidManifest.xml)
- Add network permissions: `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- Add telephony/SMS permissions: `READ_SMS`, `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`.
- Add documentation comments regarding Play Store Default SMS Handler policy vs sideload / developer use.

#### [MODIFY] [MainActivity.kt](file:///f:/android%20pro/sms_sync/android/app/src/main/kotlin/com/example/sms_sync/MainActivity.kt)
- Extend `FlutterFragmentActivity` (which inherits from `ComponentActivity`) and add `onCreate()` override calling `enableEdgeToEdge()` for Android 15 (API 35) compatibility.
- Register `MethodChannel` (`com.example.sms_sync/native_channel`).
- Implement native handlers:
  - `getSubscriptionInfo`: Query SIM card phone numbers and carrier names using `SubscriptionManager` / `TelephonyManager`.
  - `getRecentSms`: Query `Telephony.Sms.CONTENT_URI` via `ContentResolver` retrieving `_id`, `address`, `body`, `date`, `type`, and `thread_id`.

### 2. Transport & Core Data Layer (Dart)

#### [NEW] [sync_message.dart](file:///f:/android%20pro/sms_sync/lib/core/models/sync_message.dart)
- Generic message envelope:
  - `id`: unique UUID.
  - `type`: `pair_request`, `pair_verify`, `contact_info`, `sms`, `ack`.
  - `timestamp`: epoch milliseconds.
  - `payload`: JSON map.

#### [NEW] [sync_transport.dart](file:///f:/android%20pro/sms_sync/lib/transport/sync_transport.dart)
- Abstract interface `SyncTransport` defining transport lifecycle (`startDiscovery`, `connect`, `send`, `startServer`, `disconnect`).
- Abstract interface `DiscoveryService` defining NSD lifecycle (`startBrowsing`, `stopBrowsing`, `startAdvertising`, `stopAdvertising`).

#### [NEW] [websocket_transport.dart](file:///f:/android%20pro/sms_sync/lib/transport/websocket_transport.dart)
- WebSocket-backed implementation of `SyncTransport` handling Server (listening via `HttpServer` + `WebSocketTransformer`) and Client (`WebSocket.connect` with 10s timeout).
- StreamControllers properly closed on `disconnect()`.

#### [NEW] [nsd_service.dart](file:///f:/android%20pro/sms_sync/lib/transport/nsd_service.dart)
- Service handles NSD advertising (Server side) and browsing/discovery (Client side) for service type `_mysync._tcp`.
- Uses `ipLookupType: IpLookupType.any` to ensure IP addresses are resolved, with hostname fallback.

### 3. Server Database Layer (SQLite)

#### [NEW] [database_service.dart](file:///f:/android%20pro/sms_sync/lib/server/db/database_service.dart)
- SQLite database initialization (FFI configured once in `main.dart`):
  - `sim_subscriptions` table: (`id`, `subscription_id`, `phone_number`, `carrier_name`, `sim_slot`, `last_synced_at`).
  - `sms_messages` table: (`id` TEXT PRIMARY KEY, `android_sms_id` INTEGER, `address` TEXT, `body` TEXT, `date` INTEGER, `type` INTEGER, `dedup_hash` TEXT UNIQUE, `created_at` INTEGER).
- Implements `insertOrUpdateSms()` with `ConflictAlgorithm.ignore` on `dedup_hash` to prevent duplicates across client reconnections.
- Implements `clearAllData()` for resetting server state.

### 4. Application UI & Business Logic

#### [NEW] [pairing_service.dart](file:///f:/android%20pro/sms_sync/lib/core/pairing_service.dart)
- Generates 4-digit PIN on server; client prompts user to input PIN during initial connection handshake before authorizing sync messages.
- Includes brute-force protection with lockout after 5 failed attempts (30s cooldown).

#### [NEW] [client_sync_service.dart](file:///f:/android%20pro/sms_sync/lib/client/client_sync_service.dart)
- Orchestrates client lifecycle: checking permissions -> browsing servers -> connecting -> PIN pairing -> fetching SIM info & recent SMS -> sending via `SyncTransport`.

#### [NEW] [server_sync_service.dart](file:///f:/android%20pro/sms_sync/lib/server/server_sync_service.dart)
- Orchestrates server lifecycle: starting WebSocket listener -> advertising NSD service -> PIN handshake verification -> receiving `SyncMessage`s -> storing into SQLite DB with deduplication.
- Uses proper `Future<void>` return type for message handling with error catching.

#### [NEW] [client_home_screen.dart](file:///f:/android%20pro/sms_sync/lib/client/ui/client_home_screen.dart)
- Mobile UI with server picker, PIN entry dialog, permission request buttons, and sync status.
- Properly disposes `TextEditingController` and `StreamSubscription`s.

#### [NEW] [server_home_screen.dart](file:///f:/android%20pro/sms_sync/lib/server/ui/server_home_screen.dart)
- Desktop UI displaying pairing PIN, active NSD service info, connected client details, and SQLite database viewer for received SIM info & SMS messages.
- Uses `Timer.periodic` for auto-refresh (not recursive `Future.delayed`) with proper `dispose()`.

#### [MODIFY] [main.dart](file:///f:/android%20pro/sms_sync/lib/main.dart)
- Main application entry point automatically selecting Desktop (Server UI + SQLite desktop init) vs Mobile (Client UI).
- Configures `sqfliteFfiInit()` and `databaseFactoryFfi` once at startup for Windows/Linux.

## Verification Plan

### Automated / Syntax Check
- Run `flutter analyze` to confirm clean Dart code without compilation or lint issues.

### Manual Verification
- Test Android Client: Verify permission rationale dialog, PIN entry dialog, platform channel native SIM/SMS query, and NSD discovery browsing.
- Test Windows Server: Verify SQLite database initialization, PIN display, NSD advertising, and WebSocket deduplicated SQLite persistence.
- Test Edge-to-Edge: Verify `enableEdgeToEdge()` renders correctly on Android 15 devices/emulators.
