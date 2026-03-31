/// Configuration constants for background health data sync.
///
/// This class centralizes all background task configuration, making it easy
/// to adjust intervals, task identifiers, and permission requirements.
/// In a BLE scanning context, these same patterns would configure scan
/// intervals, beacon regions, and Bluetooth permissions.
class BackgroundConfig {
  BackgroundConfig._();

  // ---------------------------------------------------------------------------
  // Task identifiers — must match the values registered in Info.plist under
  // BGTaskSchedulerPermittedIdentifiers.
  // ---------------------------------------------------------------------------

  /// Identifier for the periodic background refresh task (short-lived, ~30s).
  static const String backgroundRefreshTaskId =
      'com.example.backgroundsync.refresh';

  /// Identifier for the long-running background processing task (~minutes).
  static const String backgroundProcessingTaskId =
      'com.example.backgroundsync.processing';

  // ---------------------------------------------------------------------------
  // Scheduling parameters
  // ---------------------------------------------------------------------------

  /// Minimum interval between background refresh tasks (in minutes).
  /// iOS may defer this based on system conditions and user behavior.
  static const int refreshIntervalMinutes = 15;

  /// Minimum interval between background processing tasks (in minutes).
  static const int processingIntervalMinutes = 60;

  /// Whether the processing task requires network connectivity.
  /// Set to true if synced data needs to be uploaded to a server.
  static const bool requiresNetworkConnectivity = false;

  /// Whether the processing task requires the device to be charging.
  /// Setting this to false allows background work even on battery.
  static const bool requiresCharging = false;

  // ---------------------------------------------------------------------------
  // Platform channel
  // ---------------------------------------------------------------------------

  /// Name of the Flutter MethodChannel used to communicate with native code.
  /// Both Dart and Swift/Kotlin sides must use the same channel name.
  static const String methodChannelName =
      'com.example.backgroundsync/health_sync';

  // ---------------------------------------------------------------------------
  // Method names called over the platform channel
  // ---------------------------------------------------------------------------

  static const String methodInitialize = 'initialize';
  static const String methodRequestPermissions = 'requestPermissions';
  static const String methodStartSync = 'startSync';
  static const String methodStopSync = 'stopSync';
  static const String methodGetSyncStatus = 'getSyncStatus';
  static const String methodGetLastSyncTimestamp = 'getLastSyncTimestamp';

  // ---------------------------------------------------------------------------
  // Notification configuration
  // ---------------------------------------------------------------------------

  /// Title shown in the local notification after a background sync completes.
  static const String notificationTitle = 'Health Sync Complete';

  /// Body text for the sync-complete notification.
  static const String notificationBody =
      'Your health data has been synced in the background.';
}
