import 'dart:async';
import 'websocket_service.dart';

/// Callback type for custom system metrics provider
typedef SystemMetricsProvider = Future<Map<String, dynamic>> Function();

/// Heartbeat service for sending periodic heartbeats to the server
class HeartbeatService {
  final WebSocketService webSocketService;
  final Duration interval;

  /// Optional custom metrics provider
  final SystemMetricsProvider? metricsProvider;

  Timer? _timer;
  bool _isRunning = false;

  HeartbeatService({
    required this.webSocketService,
    this.interval = const Duration(seconds: 15),
    this.metricsProvider,
  });

  /// Whether the heartbeat service is running
  bool get isRunning => _isRunning;

  /// Start sending heartbeats
  void start() {
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _timer = Timer.periodic(interval, (_) => _sendHeartbeat());
  }

  /// Stop sending heartbeats
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Send a heartbeat message
  Future<void> _sendHeartbeat() async {
    try {
      // Get system metrics
      final metrics = await _getSystemMetrics();

      // Send heartbeat
      await webSocketService.sendHeartbeat(
        cpuPercent: metrics['cpu_percent'] as double,
        memoryMb: metrics['memory_mb'] as int,
        diskFreeGb: metrics['disk_free_gb'] as int,
      );
    } catch (e) {
      // Silently fail - heartbeat is not critical
    }
  }

  /// Get system metrics
  Future<Map<String, dynamic>> _getSystemMetrics() async {
    // Use custom provider if available
    if (metricsProvider != null) {
      return await metricsProvider!();
    }

    // Default: return mock data
    // In a real implementation, you would use platform-specific APIs
    // to get actual CPU, memory, and disk usage
    return {
      'cpu_percent': 0.0,
      'memory_mb': 0,
      'disk_free_gb': 0,
    };
  }

  /// Dispose resources
  void dispose() {
    stop();
  }
}
