# Walkthrough - Bug Fixes, Deep Code Issues & API 35 Adaptation

This update addresses connectivity issues on the Android client, state persistence on the server, full compatibility with Android 15 (API Level 35), and **10 deep source code bugs** including memory leaks, infinite recursion, and fire-and-forget async patterns.

## Key Improvements

### 1. Android 15 (API 35) Compatibility
- **Target SDK 35**: The app now targets Android 15 (`compileSdk = 36`, `targetSdk = 35`), enabling the latest platform features and security improvements.
- **Edge-to-Edge Support**: Added `enableEdgeToEdge()` call in `MainActivity.kt` via a new `onCreate()` override with the `androidx.activity.enableEdgeToEdge` import. This ensures the app correctly handles the mandatory edge-to-edge behavior in Android 15.
- **Manifest Updates**: Verified all permissions and features for API 35 compliance.

### 2. Reliable Connectivity (Client Fix)
- **Connection Timeout**: Added a 10-second timeout to the WebSocket connection attempt. This prevents the app from getting stuck on "Connecting" indefinitely if the server is unreachable or the network is blocked.
- **Error Handling**: The client UI now correctly identifies connection failures and provides a "Retry" button to restart the discovery process.
- **Improved Logging**: Added debug logs to track connection attempts and failures.

### 3. Server State & Data Management
- **Clear All Data**: Added a "Clear All Data" feature to the Server UI. This allows users to wipe the SQLite database (SMS messages and SIM subscriptions) directly from the app, resolving the issue where old connection data persisted between runs.
- **Clean Session Start**: Ensured the server resets its internal state (pairing PIN and client status) more effectively when the app is restarted or a client disconnects.

### 4. Deep Source Code Bug Fixes

#### NSD Discovery IP Resolution
- **Problem**: `NsdDiscoveryService` used `service.addresses?.first.address` but never requested IP resolution — the `nsd` package returns `null` for addresses unless `ipLookupType` is specified.
- **Fix**: Added `ipLookupType: IpLookupType.any` to `startDiscovery()` and added hostname fallback via `service.host`.

#### Server Home Screen Infinite Recursion
- **Problem**: `_refreshData()` called itself via `Future.delayed()` unconditionally, even after widget disposal, causing potential crashes.
- **Fix**: Replaced with `Timer.periodic` that is cancelled in `dispose()`.

#### Async Fire-and-Forget in Server Sync Service
- **Problem**: `_handleMessage` was declared as `void` but used `async` — making all exceptions inside it silently swallowed.
- **Fix**: Changed return type to `Future<void>` and wrapped the listener with `.catchError()` for proper error propagation.

#### Memory Leaks — Stream Subscriptions & Controllers
- **Problem**: `ClientHomeScreen` and `ServerHomeScreen` subscribed to streams in `initState()` but never cancelled them. `WebSocketTransport` created broadcast StreamControllers that were never closed. `TextEditingController` in `ClientHomeScreen` was never disposed.
- **Fix**: Added `dispose()` overrides to both screens, closing all subscriptions, timers, and controllers. Added `close()` calls for StreamControllers in `WebSocketTransport.disconnect()`.

#### Redundant SQLite Initialization
- **Problem**: `DatabaseService._initDb()` called `sqfliteFfiInit()` and set `databaseFactory` — but `main.dart` already does this at startup, creating a redundant and potentially conflicting double-init.
- **Fix**: Removed the redundant call and the unused `dart:io` import.

#### NSD Service Resource Cleanup
- **Problem**: `NsdDiscoveryService` had no `dispose()` method to stop browsing/advertising and close its StreamController.
- **Fix**: Added a `dispose()` method that stops browsing, stops advertising, and closes the StreamController.

## Files Changed

| File | Changes |
|------|---------|
| `MainActivity.kt` | Inherits from `FlutterFragmentActivity` (extends `ComponentActivity`) + `onCreate()` + `enableEdgeToEdge()` |
| `nsd_service.dart` | Added `ipLookupType`, hostname fallback, `dispose()` |
| `server_home_screen.dart` | `Timer.periodic` replaces recursion, added `dispose()` |
| `client_home_screen.dart` | Added `dispose()`, subscription cancellation, PIN controller disposal |
| `server_sync_service.dart` | `_handleMessage` → `Future<void>` + `.catchError()` |
| `websocket_transport.dart` | StreamControllers closed in `disconnect()` |
| `database_service.dart` | Removed redundant `sqfliteFfiInit()` + unused import |

## How to Verify

1. **Test Android 15**: Run the app on an Android 15 device or emulator. Observe the edge-to-edge layout and verify permissions.
2. **Test Connectivity**: Try to connect to a server. If the server is off, the client should show an error after 10 seconds instead of hanging.
3. **Test Data Clearing**: Use the "Clear All Data" button on the Windows server and verify the message list is wiped.
4. **Test Resource Cleanup**: Navigate away from screens and verify no crash/leak logs in the console.
5. **Run `flutter analyze`**: Confirm zero errors and warnings.

## Next Steps
- Implement Phase 2: Bidirectional text messaging and file transfer.
- Add persistent "Paired Devices" storage to avoid re-pairing every time.
