import 'package:path/path.dart' as p;

import '../models/message.dart';

/// Agent configuration class
class AgentConfig {
  /// WebSocket server URL
  final String serverUrl;

  /// Enrollment token for authentication
  final String enrollToken;

  /// List of allowed root directories
  final List<AllowedRoot> allowedRoots;

  /// Heartbeat interval in seconds
  final int heartbeatIntervalSeconds;

  /// Reconnect delay in seconds
  final int reconnectDelaySeconds;

  /// Maximum reconnect attempts. Set to -1 for infinite reconnection.
  final int maxReconnectAttempts;

  /// Upload chunk size in bytes
  final int uploadChunkSize;

  /// Maximum concurrent uploads
  final int maxConcurrentUploads;

  /// Log file path (optional, if null, no file logging)
  final String? logFilePath;

  const AgentConfig({
    required this.serverUrl,
    required this.enrollToken,
    required this.allowedRoots,
    this.heartbeatIntervalSeconds = 15,
    this.reconnectDelaySeconds = 5,
    this.maxReconnectAttempts = -1,
    this.uploadChunkSize = 1024 * 1024,
    this.maxConcurrentUploads = 3,
    this.logFilePath,
  });

  /// Create config from simple parameters
  factory AgentConfig.simple({
    required String serverUrl,
    required String enrollToken,
    required List<String> allowedPaths,
    int maxReconnectAttempts = -1,
    String? logFilePath,
  }) {
    final roots = <AllowedRoot>[];
    for (int i = 0; i < allowedPaths.length; i++) {
      final path = allowedPaths[i];
      // Use path.basename() to correctly handle both Windows and Unix paths
      final name = p.basename(path);
      roots.add(AllowedRoot(
        rootId: 'root_$i',
        name: name,
        absPath: path,
      ));
    }

    return AgentConfig(
      serverUrl: serverUrl,
      enrollToken: enrollToken,
      allowedRoots: roots,
      maxReconnectAttempts: maxReconnectAttempts,
      logFilePath: logFilePath,
    );
  }
}
