# Flutter Background Health Data Sync

A Flutter application demonstrating native iOS/Android background task execution with platform channel bridging. This sample shows the architecture patterns needed for any background service — health data sync, BLE scanning, location tracking, etc.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter (Dart)                                             │
│  ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │  main.dart (UI)  │───►│  health_sync_service.dart     │   │
│  └──────────────────┘    │  (Platform channel interface) │   │
│                          └──────────┬───────────────────┘   │
│                                     │ MethodChannel         │
├─────────────────────────────────────┼───────────────────────┤
│  iOS (Swift)                        ▼                       │
│  ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │  AppDelegate.swift│───►│  HealthSyncPlugin.swift      │   │
│  │  (BGTask reg.)   │    │  (Channel handler + BGTask)  │   │
│  └──────────────────┘    └──────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Android (Kotlin)                                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  BackgroundSyncService.kt (WorkManager + Channel)    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Key Patterns Demonstrated

### 1. Flutter MethodChannel Bridge
- Dart `HealthSyncService` communicates with native code via `MethodChannel`
- Clean async API that hides platform differences
- Singleton pattern to prevent duplicate channel registrations

### 2. iOS BGTaskScheduler
- `BGAppRefreshTask` for short-lived background work (~30s)
- `BGProcessingTask` for longer background operations (minutes)
- Task chaining: each execution schedules the next occurrence
- Expiration handlers for graceful cleanup when time runs out
- Works when app is backgrounded and screen is locked

### 3. iOS Background Mode Configuration
- `Info.plist` configured with `fetch` and `processing` background modes
- `BGTaskSchedulerPermittedIdentifiers` listing all task identifiers
- Task registration in `AppDelegate.didFinishLaunchingWithOptions` (required timing)

### 4. Permission Flow
- Dart requests permissions via platform channel
- Native side checks real system permissions (background refresh status)
- Results returned as structured map to Dart for UI updates

### 5. Android WorkManager
- `PeriodicWorkRequest` for recurring background tasks
- Battery-aware constraints
- Exponential backoff for failed tasks
- Works even after app is killed

## Mapping to BLE/iBeacon Scanning

This health sync sample uses the exact same architecture needed for BLE background scanning. Here's how each component maps:

| This Sample | BLE Scanning Equivalent |
|---|---|
| `BGTaskScheduler` | `CBCentralManager` + State Preservation & Restoration |
| HealthKit permission | `CBCentralManager` authorization + `CLLocationManager.requestAlwaysAuthorization()` |
| `fetch` background mode | `bluetooth-central` background mode |
| Simulated data read | `CBCentralManager.scanForPeripherals()` |
| `UserDefaults` persistence | CoreData/UserDefaults for discovered device cache |
| Local notification on sync | Local notification on beacon detection |
| `WorkManager` (Android) | `ForegroundService` with `BluetoothLeScanner` |

### iOS BLE Background Specifics
- **Region Monitoring**: `CLLocationManager` monitors `CLBeaconRegion` entries — this wakes the app from suspended/terminated state
- **Ranging**: Once woken by region monitoring, `CLLocationManager.startRangingBeacons(in:)` identifies specific beacons
- **State Preservation**: `CBCentralManager(delegate:queue:options:)` with `CBCentralManagerOptionRestoreIdentifierKey` maintains Bluetooth state across app relaunches
- **Continuous Scanning**: Combine region monitoring (for wake-up) with foreground ranging (for precision)

## Project Structure

```
lib/
  main.dart                  — Flutter UI (status display + controls)
  health_sync_service.dart   — Dart platform channel interface
  background_config.dart     — Configuration constants
ios/Runner/
  AppDelegate.swift          — BGTaskScheduler registration
  HealthSyncPlugin.swift     — Native sync logic + background handlers
  Info.plist                 — Background modes + task identifiers
android/.../
  BackgroundSyncService.kt   — WorkManager implementation
```

## Testing Background Tasks (iOS)

To test BGTaskScheduler tasks in the Xcode debugger:

```
# Simulate a background refresh task
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.backgroundsync.refresh"]

# Simulate a background processing task
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.backgroundsync.processing"]
```

## License

MIT
