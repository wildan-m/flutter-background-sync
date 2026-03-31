import UIKit
import Flutter
import BackgroundTasks

/// AppDelegate configured for background task execution.
///
/// Key responsibilities:
/// 1. Register Flutter plugins (including our custom HealthSyncPlugin).
/// 2. Register BGTaskScheduler task identifiers on app launch.
/// 3. Handle background fetch events forwarded by the system.
///
/// For a BLE scanning app, this same structure would register
/// CoreBluetooth state restoration identifiers and configure
/// CLLocationManager for beacon region monitoring.
@main
@objc class AppDelegate: FlutterAppDelegate {

    /// The background sync plugin instance — kept alive for the app's lifetime
    /// so it can handle method channel calls and background task callbacks.
    private var healthSyncPlugin: HealthSyncPlugin?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // --- Flutter engine setup ---
        let controller = window?.rootViewController as! FlutterViewController

        // --- Register our custom plugin ---
        healthSyncPlugin = HealthSyncPlugin(messenger: controller.binaryMessenger)

        // --- Register BGTaskScheduler task identifiers ---
        // IMPORTANT: This must happen in didFinishLaunchingWithOptions, before
        // the app finishes launching. Registering later causes a crash.
        registerBackgroundTasks()

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Register all background task identifiers with BGTaskScheduler.
    ///
    /// Each identifier must also appear in Info.plist under
    /// BGTaskSchedulerPermittedIdentifiers, or registration will silently fail.
    private func registerBackgroundTasks() {
        // Short-lived background refresh task (~30 seconds of execution time).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifiers.refresh,
            using: nil
        ) { [weak self] task in
            self?.healthSyncPlugin?.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }

        // Long-running background processing task (several minutes).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifiers.processing,
            using: nil
        ) { [weak self] task in
            self?.healthSyncPlugin?.handleBackgroundProcessing(task: task as! BGProcessingTask)
        }

        print("[AppDelegate] Background tasks registered")
    }

    // MARK: - Background Fetch (Legacy)

    /// Handle legacy background fetch for iOS < 13 compatibility.
    /// Modern apps should prefer BGTaskScheduler, but this provides fallback.
    override func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        healthSyncPlugin?.performLegacyBackgroundFetch { result in
            completionHandler(result)
        }
    }
}

/// Centralized background task identifier constants.
/// These must match exactly between:
/// - Info.plist BGTaskSchedulerPermittedIdentifiers
/// - BGTaskScheduler.register() calls
/// - BGTaskScheduler.submit() calls
enum BackgroundTaskIdentifiers {
    static let refresh = "com.example.backgroundsync.refresh"
    static let processing = "com.example.backgroundsync.processing"
}
