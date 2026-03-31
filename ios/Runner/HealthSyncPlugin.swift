import Flutter
import UIKit
import BackgroundTasks
import UserNotifications

/// Native iOS plugin implementing background health data sync.
///
/// Architecture overview:
/// ┌─────────────────────────────────────────────────────┐
/// │  Flutter (Dart)                                     │
/// │  HealthSyncService  ──MethodChannel──►  This class  │
/// └─────────────────────────────────────────────────────┘
///                                              │
///                    ┌─────────────────────────┤
///                    ▼                         ▼
///           BGTaskScheduler          UNUserNotificationCenter
///           (background exec)        (completion alerts)
///
/// For BLE scanning, replace the simulated data read with:
/// - CoreBluetooth CBCentralManager for BLE device scanning
/// - CoreLocation CLLocationManager for iBeacon region monitoring
/// - The rest of the architecture (channels, scheduling, permissions) is identical.
class HealthSyncPlugin: NSObject {

    // MARK: - Properties

    /// Flutter method channel for bidirectional communication.
    private let channel: FlutterMethodChannel

    /// Tracks whether background sync is currently scheduled.
    private var isActive = false

    /// Counter for completed sync operations (persisted via UserDefaults).
    private var syncCount: Int {
        get { UserDefaults.standard.integer(forKey: "health_sync_count") }
        set { UserDefaults.standard.set(newValue, forKey: "health_sync_count") }
    }

    /// Timestamp of the last successful sync (epoch milliseconds).
    private var lastSyncTimestamp: Int {
        get { UserDefaults.standard.integer(forKey: "health_sync_last_timestamp") }
        set { UserDefaults.standard.set(newValue, forKey: "health_sync_last_timestamp") }
    }

    // MARK: - Initialization

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.example.backgroundsync/health_sync",
            binaryMessenger: messenger
        )
        super.init()

        // Register as the method call handler. Every invokeMethod call from
        // Dart arrives here.
        channel.setMethodCallHandler(handleMethodCall)

        print("[HealthSyncPlugin] Initialized with method channel")
    }

    // MARK: - Method Channel Handler

    /// Central dispatch for all method calls from Flutter.
    ///
    /// Each case maps to a method defined in BackgroundConfig on the Dart side.
    /// The pattern is identical for BLE plugins — you'd add methods like
    /// startScanning, stopScanning, getDiscoveredDevices, etc.
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "initialize":
            handleInitialize(result: result)

        case "requestPermissions":
            handleRequestPermissions(result: result)

        case "startSync":
            handleStartSync(result: result)

        case "stopSync":
            handleStopSync(result: result)

        case "getSyncStatus":
            handleGetSyncStatus(result: result)

        case "getLastSyncTimestamp":
            result(lastSyncTimestamp)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Implementations

    /// Initialize the plugin and request notification permissions.
    ///
    /// We request notification permission here so we can alert the user
    /// when a background sync completes (important for UX since the user
    /// can't see the app UI while it's backgrounded).
    private func handleInitialize(result: @escaping FlutterResult) {
        // Request notification permission for background completion alerts.
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("[HealthSyncPlugin] Notification auth error: \(error)")
            }
            print("[HealthSyncPlugin] Notification permission: \(granted)")
        }

        print("[HealthSyncPlugin] Plugin initialized")
        result(true)
    }

    /// Request HealthKit and background refresh permissions.
    ///
    /// In a real app, this would call HKHealthStore.requestAuthorization().
    /// For this sample, we simulate the permission flow and check
    /// UIApplication.shared.backgroundRefreshStatus for the real background
    /// refresh permission.
    ///
    /// For BLE: You'd request CBCentralManager authorization and
    /// CLLocationManager.requestAlwaysAuthorization() here instead.
    private func handleRequestPermissions(result: @escaping FlutterResult) {
        // Check background refresh status (this is a real system check).
        let bgStatus = UIApplication.shared.backgroundRefreshStatus
        let bgGranted = bgStatus == .available

        if !bgGranted {
            print("[HealthSyncPlugin] Background refresh is disabled. "
                  + "User must enable it in Settings > General > Background App Refresh")
        }

        // Simulate HealthKit permission (always grant in sample).
        // Real implementation: HKHealthStore().requestAuthorization(toShare:read:completion:)
        let healthKitGranted = true

        let response: [String: Bool] = [
            "healthKit": healthKitGranted,
            "backgroundRefresh": bgGranted
        ]

        print("[HealthSyncPlugin] Permissions — HealthKit: \(healthKitGranted), "
              + "Background: \(bgGranted)")
        result(response)
    }

    /// Schedule background sync tasks with the system.
    ///
    /// BGTaskScheduler.submit() tells iOS to run our task at an appropriate
    /// time. The system considers factors like:
    /// - Battery level and charging state
    /// - Network connectivity
    /// - User usage patterns (when the user typically opens the app)
    /// - System load
    ///
    /// For BLE: Instead of BGTaskScheduler, you'd start CBCentralManager
    /// scanning with the CBCentralManagerScanOptionAllowDuplicatesKey option
    /// and register for State Preservation and Restoration.
    private func handleStartSync(result: @escaping FlutterResult) {
        scheduleBackgroundRefresh()
        scheduleBackgroundProcessing()
        isActive = true
        print("[HealthSyncPlugin] Background sync started")
        result(true)
    }

    /// Cancel all scheduled background tasks.
    private func handleStopSync(result: @escaping FlutterResult) {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        isActive = false
        print("[HealthSyncPlugin] Background sync stopped")
        result(true)
    }

    /// Return current sync status to Flutter.
    private func handleGetSyncStatus(result: @escaping FlutterResult) {
        let status: [String: Any] = [
            "isActive": isActive,
            "syncCount": syncCount,
            "lastTimestamp": lastSyncTimestamp
        ]
        result(status)
    }

    // MARK: - Background Task Scheduling

    /// Schedule a short-lived background refresh task.
    ///
    /// BGAppRefreshTask gives ~30 seconds of execution time.
    /// Ideal for quick data fetches or BLE scans.
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: BackgroundTaskIdentifiers.refresh
        )
        // Earliest time the task can run. iOS may delay further.
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: TimeInterval(15 * 60) // 15 minutes
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[HealthSyncPlugin] Background refresh scheduled")
        } catch {
            print("[HealthSyncPlugin] Failed to schedule refresh: \(error)")
        }
    }

    /// Schedule a long-running background processing task.
    ///
    /// BGProcessingTask gives several minutes of execution time.
    /// Ideal for larger data syncs, batch BLE operations, or firmware updates.
    private func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(
            identifier: BackgroundTaskIdentifiers.processing
        )
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: TimeInterval(60 * 60) // 1 hour
        )
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[HealthSyncPlugin] Background processing scheduled")
        } catch {
            print("[HealthSyncPlugin] Failed to schedule processing: \(error)")
        }
    }

    // MARK: - Background Task Execution

    /// Called by the system when a background refresh task fires.
    ///
    /// This runs even when the screen is locked and the app is suspended.
    /// The key constraint is the ~30-second time limit.
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        print("[HealthSyncPlugin] Background refresh executing")

        // Schedule the next refresh before doing work, so the chain continues
        // even if this execution is interrupted.
        scheduleBackgroundRefresh()

        // Set up an expiration handler. The system calls this if we're about
        // to exceed our time limit — we must clean up immediately.
        task.expirationHandler = {
            print("[HealthSyncPlugin] Background refresh expired")
            task.setTaskCompleted(success: false)
        }

        // Perform the simulated data read.
        performDataSync { [weak self] success in
            self?.postSyncNotification()
            task.setTaskCompleted(success: success)
            print("[HealthSyncPlugin] Background refresh completed: \(success)")
        }
    }

    /// Called by the system when a background processing task fires.
    ///
    /// Similar to refresh but with more execution time (minutes vs. seconds).
    func handleBackgroundProcessing(task: BGProcessingTask) {
        print("[HealthSyncPlugin] Background processing executing")

        scheduleBackgroundProcessing()

        task.expirationHandler = {
            print("[HealthSyncPlugin] Background processing expired")
            task.setTaskCompleted(success: false)
        }

        performDataSync { [weak self] success in
            self?.postSyncNotification()
            task.setTaskCompleted(success: success)
            print("[HealthSyncPlugin] Background processing completed: \(success)")
        }
    }

    /// Legacy background fetch handler for iOS < 13 compatibility.
    func performLegacyBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        print("[HealthSyncPlugin] Legacy background fetch executing")

        performDataSync { success in
            completion(success ? .newData : .failed)
        }
    }

    // MARK: - Data Sync (Simulated)

    /// Simulate a health data read operation.
    ///
    /// In a real app, this would:
    /// - Query HKHealthStore for recent samples (steps, heart rate, etc.)
    /// - Process and aggregate the data
    /// - Optionally upload to a server
    ///
    /// For BLE: This would be replaced with:
    /// - CBCentralManager.scanForPeripherals() to discover devices
    /// - Reading characteristic values from connected peripherals
    /// - Processing beacon proximity data from CLLocationManager
    private func performDataSync(completion: @escaping (Bool) -> Void) {
        // Simulate async data read with a short delay.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            // Generate simulated health data.
            let simulatedData: [String: Any] = [
                "steps": Int.random(in: 100...500),
                "heartRate": Int.random(in: 60...100),
                "timestamp": Date().timeIntervalSince1970
            ]

            print("[HealthSyncPlugin] Synced data: \(simulatedData)")

            // Update persisted state.
            self.syncCount += 1
            self.lastSyncTimestamp = Int(Date().timeIntervalSince1970 * 1000)

            // Notify Flutter side (if the engine is running).
            // When the app is truly backgrounded, the engine may be paused,
            // so this call might not arrive until the app resumes.
            DispatchQueue.main.async {
                self.channel.invokeMethod("onSyncComplete", arguments: simulatedData)
            }

            completion(true)
        }
    }

    // MARK: - Notifications

    /// Post a local notification to inform the user that a background sync
    /// completed. This provides visibility into background activity.
    private func postSyncNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Health Sync Complete"
        content.body = "Your health data has been synced in the background."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[HealthSyncPlugin] Notification error: \(error)")
            }
        }
    }
}
