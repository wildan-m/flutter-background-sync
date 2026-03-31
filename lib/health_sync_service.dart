import 'package:flutter/services.dart';
import 'background_config.dart';

/// Status of the background sync service.
enum SyncStatus {
  /// Service has not been initialized yet.
  uninitialized,

  /// Service is initialized but not actively syncing.
  idle,

  /// A sync operation is currently in progress.
  syncing,

  /// Permissions were denied by the user.
  permissionDenied,

  /// An error occurred during the last operation.
  error,
}

/// Result of a permission request.
class PermissionResult {
  final bool healthKitGranted;
  final bool backgroundRefreshGranted;

  const PermissionResult({
    required this.healthKitGranted,
    required this.backgroundRefreshGranted,
  });

  bool get allGranted => healthKitGranted && backgroundRefreshGranted;

  @override
  String toString() =>
      'PermissionResult(healthKit: $healthKitGranted, '
      'backgroundRefresh: $backgroundRefreshGranted)';
}

/// Dart service class that bridges Flutter to the native iOS/Android
/// background sync implementation via platform channels.
///
/// This follows the same pattern used for BLE scanning plugins:
/// 1. A single MethodChannel for command/response communication.
/// 2. An optional EventChannel (not shown) for streaming data updates.
/// 3. Clean async API that hides platform-specific details.
class HealthSyncService {
  /// Singleton instance — typical for platform channel services to avoid
  /// multiple channel registrations.
  static final HealthSyncService _instance = HealthSyncService._internal();
  factory HealthSyncService() => _instance;

  HealthSyncService._internal();

  /// The platform channel used to invoke native methods.
  final MethodChannel _channel = const MethodChannel(
    BackgroundConfig.methodChannelName,
  );

  SyncStatus _status = SyncStatus.uninitialized;

  /// Current status of the sync service.
  SyncStatus get status => _status;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initialize the native background sync infrastructure.
  ///
  /// On iOS this registers BGTaskScheduler tasks. On Android this sets up
  /// WorkManager. Must be called once during app startup (e.g., in main.dart).
  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        BackgroundConfig.methodInitialize,
      );
      _status = SyncStatus.idle;
      return result ?? false;
    } on PlatformException catch (e) {
      _status = SyncStatus.error;
      throw HealthSyncException(
        'Failed to initialize background sync: ${e.message}',
      );
    }
  }

  /// Request all required permissions (HealthKit access + background refresh).
  ///
  /// Returns a [PermissionResult] indicating which permissions were granted.
  /// The UI should check [PermissionResult.allGranted] and guide the user
  /// to Settings if any permission was denied.
  Future<PermissionResult> requestPermissions() async {
    try {
      final result = await _channel.invokeMapMethod<String, bool>(
        BackgroundConfig.methodRequestPermissions,
      );

      if (result == null) {
        _status = SyncStatus.error;
        return const PermissionResult(
          healthKitGranted: false,
          backgroundRefreshGranted: false,
        );
      }

      final permResult = PermissionResult(
        healthKitGranted: result['healthKit'] ?? false,
        backgroundRefreshGranted: result['backgroundRefresh'] ?? false,
      );

      if (!permResult.allGranted) {
        _status = SyncStatus.permissionDenied;
      }

      return permResult;
    } on PlatformException catch (e) {
      _status = SyncStatus.error;
      throw HealthSyncException(
        'Failed to request permissions: ${e.message}',
      );
    }
  }

  /// Start periodic background syncing.
  ///
  /// This schedules the native background tasks. On iOS, the system decides
  /// when to actually execute them based on device usage patterns, battery
  /// level, and network conditions.
  Future<bool> startSync() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        BackgroundConfig.methodStartSync,
      );
      _status = SyncStatus.syncing;
      return result ?? false;
    } on PlatformException catch (e) {
      _status = SyncStatus.error;
      throw HealthSyncException(
        'Failed to start background sync: ${e.message}',
      );
    }
  }

  /// Stop all scheduled background sync tasks.
  Future<bool> stopSync() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        BackgroundConfig.methodStopSync,
      );
      _status = SyncStatus.idle;
      return result ?? false;
    } on PlatformException catch (e) {
      _status = SyncStatus.error;
      throw HealthSyncException('Failed to stop background sync: ${e.message}');
    }
  }

  /// Get the current sync status from the native side.
  ///
  /// Useful for restoring UI state when the app returns to foreground,
  /// since background tasks may have run while the app was suspended.
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        BackgroundConfig.methodGetSyncStatus,
      );
      return result ?? {};
    } on PlatformException catch (e) {
      throw HealthSyncException(
        'Failed to get sync status: ${e.message}',
      );
    }
  }

  /// Get the timestamp of the last successful background sync.
  ///
  /// Returns null if no sync has completed yet.
  Future<DateTime?> getLastSyncTimestamp() async {
    try {
      final result = await _channel.invokeMethod<int>(
        BackgroundConfig.methodGetLastSyncTimestamp,
      );
      if (result == null || result == 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(result);
    } on PlatformException catch (e) {
      throw HealthSyncException(
        'Failed to get last sync timestamp: ${e.message}',
      );
    }
  }
}

/// Exception thrown by [HealthSyncService] when a platform operation fails.
class HealthSyncException implements Exception {
  final String message;
  const HealthSyncException(this.message);

  @override
  String toString() => 'HealthSyncException: $message';
}
