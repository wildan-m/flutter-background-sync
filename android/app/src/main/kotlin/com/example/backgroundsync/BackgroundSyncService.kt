package com.example.backgroundsync

import android.content.Context
import android.util.Log
import androidx.work.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

/**
 * Android implementation of the background health sync service using WorkManager.
 *
 * WorkManager is the recommended API for deferrable, guaranteed background work
 * on Android. It handles:
 * - Doze mode and app standby constraints
 * - Battery optimization
 * - Task persistence across device reboots
 * - Automatic retry with backoff
 *
 * Architecture parallel to iOS:
 * ┌──────────────────────────────────────────────────────┐
 * │ iOS:    BGTaskScheduler  ←→  HealthSyncPlugin.swift  │
 * │ Android: WorkManager     ←→  BackgroundSyncService.kt│
 * │ Dart:   MethodChannel    ←→  HealthSyncService.dart  │
 * └──────────────────────────────────────────────────────┘
 *
 * For BLE scanning on Android, you would use a Foreground Service instead of
 * WorkManager, since BLE scanning requires continuous execution. The
 * ForegroundService would display a persistent notification and use
 * BluetoothLeScanner for device discovery.
 */
class BackgroundSyncService(private val flutterEngine: FlutterEngine) {

    companion object {
        private const val TAG = "BackgroundSyncService"
        private const val CHANNEL_NAME = "com.example.backgroundsync/health_sync"
        private const val WORK_NAME = "health_data_sync"
        private const val PREFS_NAME = "health_sync_prefs"
        private const val KEY_SYNC_COUNT = "sync_count"
        private const val KEY_LAST_TIMESTAMP = "last_sync_timestamp"
    }

    private lateinit var channel: MethodChannel

    /**
     * Register the method channel handler with the Flutter engine.
     *
     * Call this from MainActivity.configureFlutterEngine().
     */
    fun registerWith() {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
        channel.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        Log.d(TAG, "Method channel registered")
    }

    // =========================================================================
    // Method Channel Handler
    // =========================================================================

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                Log.d(TAG, "Initialized")
                result.success(true)
            }

            "requestPermissions" -> {
                // On Android, health data permissions depend on the specific
                // health API used (Google Fit, Health Connect, etc.).
                // Background execution doesn't require special permission
                // beyond what WorkManager provides.
                val response = mapOf(
                    "healthKit" to true,         // Simulated
                    "backgroundRefresh" to true  // WorkManager always available
                )
                result.success(response)
            }

            "startSync" -> {
                schedulePeriodicSync(flutterEngine.dartExecutor.binaryMessenger.javaClass.classLoader!!
                    .let { WorkManager.getInstance(getAppContext()) })
                result.success(true)
            }

            "stopSync" -> {
                WorkManager.getInstance(getAppContext())
                    .cancelUniqueWork(WORK_NAME)
                Log.d(TAG, "Background sync stopped")
                result.success(true)
            }

            "getSyncStatus" -> {
                val prefs = getAppContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val response = mapOf(
                    "isActive" to true,
                    "syncCount" to prefs.getInt(KEY_SYNC_COUNT, 0),
                    "lastTimestamp" to prefs.getLong(KEY_LAST_TIMESTAMP, 0)
                )
                result.success(response)
            }

            "getLastSyncTimestamp" -> {
                val prefs = getAppContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                result.success(prefs.getLong(KEY_LAST_TIMESTAMP, 0))
            }

            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // WorkManager Scheduling
    // =========================================================================

    /**
     * Schedule a periodic background sync using WorkManager.
     *
     * PeriodicWorkRequest runs at the specified interval (minimum 15 minutes
     * on Android). The system may batch and defer execution based on Doze
     * mode and battery optimization settings.
     *
     * ExistingPeriodicWorkPolicy.KEEP ensures only one instance of this
     * work is scheduled at a time.
     */
    private fun schedulePeriodicSync(workManager: WorkManager) {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .build()

        val syncRequest = PeriodicWorkRequestBuilder<HealthSyncWorker>(
            15, TimeUnit.MINUTES  // Minimum interval on Android
        )
            .setConstraints(constraints)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                WorkRequest.MIN_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        workManager.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            syncRequest
        )

        Log.d(TAG, "Periodic sync scheduled (every 15 minutes)")
    }

    private fun getAppContext(): Context {
        return flutterEngine.dartExecutor.binaryMessenger.javaClass.classLoader!!
            .let { throw UnsupportedOperationException("Use application context injection") }
    }
}

/**
 * WorkManager Worker that performs the actual background data sync.
 *
 * This runs in a separate process/thread managed by WorkManager.
 * It executes even when the app is killed, unlike iOS where BGTaskScheduler
 * requires the app to be suspended (not terminated) unless using silent
 * push notifications.
 */
class HealthSyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    companion object {
        private const val TAG = "HealthSyncWorker"
        private const val PREFS_NAME = "health_sync_prefs"
        private const val KEY_SYNC_COUNT = "sync_count"
        private const val KEY_LAST_TIMESTAMP = "last_sync_timestamp"
    }

    override fun doWork(): Result {
        Log.d(TAG, "Background sync worker executing")

        return try {
            // Simulate health data read.
            val simulatedSteps = (100..500).random()
            val simulatedHeartRate = (60..100).random()
            Log.d(TAG, "Synced data — steps: $simulatedSteps, heartRate: $simulatedHeartRate")

            // Persist sync metadata.
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putInt(KEY_SYNC_COUNT, prefs.getInt(KEY_SYNC_COUNT, 0) + 1)
                .putLong(KEY_LAST_TIMESTAMP, System.currentTimeMillis())
                .apply()

            Log.d(TAG, "Background sync completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background sync failed", e)
            Result.retry()
        }
    }
}
