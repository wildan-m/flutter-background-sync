import 'package:flutter/material.dart';
import 'health_sync_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthSyncApp());
}

/// Root application widget.
class HealthSyncApp extends StatelessWidget {
  const HealthSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Health Sync',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const SyncDashboard(),
    );
  }
}

/// Main dashboard showing sync status, last sync timestamp, and controls.
class SyncDashboard extends StatefulWidget {
  const SyncDashboard({super.key});

  @override
  State<SyncDashboard> createState() => _SyncDashboardState();
}

class _SyncDashboardState extends State<SyncDashboard>
    with WidgetsBindingObserver {
  final HealthSyncService _syncService = HealthSyncService();

  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _permissionsGranted = false;
  DateTime? _lastSyncTime;
  String _statusMessage = 'Not initialized';
  int _syncCount = 0;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle to refresh status when returning from background.
    WidgetsBinding.instance.addObserver(this);
    _initializeService();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the app returns to foreground, query native side for latest status.
  /// This is critical for background services — the native layer may have
  /// executed tasks while Dart was suspended.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  /// Initialize the native background sync infrastructure.
  Future<void> _initializeService() async {
    try {
      final success = await _syncService.initialize();
      setState(() {
        _isInitialized = success;
        _statusMessage = success
            ? 'Initialized — request permissions to continue'
            : 'Initialization failed';
      });
    } on HealthSyncException catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.message}';
      });
    }
  }

  /// Request HealthKit and background refresh permissions.
  Future<void> _requestPermissions() async {
    setState(() => _statusMessage = 'Requesting permissions...');
    try {
      final result = await _syncService.requestPermissions();
      setState(() {
        _permissionsGranted = result.allGranted;
        _statusMessage = result.allGranted
            ? 'All permissions granted'
            : 'Some permissions denied — '
                'HealthKit: ${result.healthKitGranted}, '
                'Background: ${result.backgroundRefreshGranted}';
      });
    } on HealthSyncException catch (e) {
      setState(() => _statusMessage = 'Permission error: ${e.message}');
    }
  }

  /// Start or stop the background sync.
  Future<void> _toggleSync() async {
    try {
      if (_isSyncing) {
        await _syncService.stopSync();
        setState(() {
          _isSyncing = false;
          _statusMessage = 'Background sync stopped';
        });
      } else {
        await _syncService.startSync();
        setState(() {
          _isSyncing = true;
          _statusMessage = 'Background sync active';
        });
      }
    } on HealthSyncException catch (e) {
      setState(() => _statusMessage = 'Sync error: ${e.message}');
    }
  }

  /// Refresh status from the native side (e.g., after returning from background).
  Future<void> _refreshStatus() async {
    try {
      final status = await _syncService.getSyncStatus();
      final lastSync = await _syncService.getLastSyncTimestamp();
      setState(() {
        _isSyncing = status['isActive'] == true;
        _syncCount = status['syncCount'] as int? ?? _syncCount;
        _lastSyncTime = lastSync;
        if (_isSyncing) {
          _statusMessage = 'Background sync active';
        }
      });
    } on HealthSyncException catch (_) {
      // Silently handle — UI already shows last known state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Health Sync'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Status card ---
            _buildStatusCard(),
            const SizedBox(height: 16),

            // --- Last sync info ---
            _buildInfoCard(
              icon: Icons.access_time,
              label: 'Last Sync',
              value: _lastSyncTime != null
                  ? _formatTimestamp(_lastSyncTime!)
                  : 'Never',
            ),
            const SizedBox(height: 8),
            _buildInfoCard(
              icon: Icons.sync,
              label: 'Total Syncs',
              value: '$_syncCount',
            ),
            const SizedBox(height: 32),

            // --- Action buttons ---
            if (!_permissionsGranted && _isInitialized)
              FilledButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text('Request Permissions'),
              ),
            if (_permissionsGranted) ...[
              FilledButton.icon(
                onPressed: _toggleSync,
                icon: Icon(_isSyncing ? Icons.stop : Icons.play_arrow),
                label: Text(_isSyncing ? 'Stop Sync' : 'Start Sync'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _refreshStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Status'),
              ),
            ],

            const Spacer(),

            // --- Architecture note ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'This app demonstrates Flutter-to-native bridging for '
                'background task execution. The same architecture applies '
                'to BLE scanning, location tracking, or any service that '
                'must run while the app is backgrounded or the screen is '
                'locked.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final color = _isSyncing
        ? Colors.green
        : _permissionsGranted
            ? Colors.orange
            : Colors.grey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 16),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${timestamp.month}/${timestamp.day} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
