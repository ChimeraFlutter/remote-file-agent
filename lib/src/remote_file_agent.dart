import 'dart:async';
import 'models/message.dart';
import 'services/websocket_service.dart';
import 'services/heartbeat_service.dart';
import 'services/file_service.dart';
import 'services/device_settings.dart';
import 'core/config.dart';
import 'core/message_handler.dart';

/// Callback type for status changes
typedef StatusCallback = void Function(ConnectionStatus status);

/// Callback type for errors
typedef ErrorCallback = void Function(String error);

/// High-level API for Remote File Agent
///
/// This class provides a simple interface to create and manage a remote file
/// agent with automatic reconnection and heartbeat.
///
/// Example:
/// ```dart
/// final agent = await RemoteFileAgent.create(
///   serverUrl: 'ws://localhost:18120/ws/agent',
///   enrollToken: 'your-token',
///   allowedPaths: ['/Users/mac/Desktop'],
/// );
///
/// agent.onStatusChanged((status) {
///   print('Status: $status');
/// });
///
/// await agent.start();
/// ```
class RemoteFileAgent {
  final AgentConfig config;
  final DeviceSettings deviceSettings;
  final String deviceId;
  final String deviceName;
  final String version;

  late final WebSocketService _wsService;
  late final HeartbeatService _heartbeatService;
  late final MessageHandler _messageHandler;
  late final FileService _fileService;

  final List<StatusCallback> _statusCallbacks = [];
  final List<ErrorCallback> _errorCallbacks = [];

  RemoteFileAgent._({
    required this.config,
    required this.deviceSettings,
    required this.deviceId,
    required this.deviceName,
    this.version = '1.0.0',
  }) {
    _fileService = FileService();

    _wsService = WebSocketService(
      serverUrl: config.serverUrl,
      enrollToken: config.enrollToken,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: deviceSettings.getPlatform(),
      version: version,
      allowedRoots: config.allowedRoots,
      maxReconnectAttempts: config.maxReconnectAttempts,
      reconnectDelay: Duration(seconds: config.reconnectDelaySeconds),
    );

    _heartbeatService = HeartbeatService(
      webSocketService: _wsService,
      interval: Duration(seconds: config.heartbeatIntervalSeconds),
    );

    _messageHandler = MessageHandler(
      wsService: _wsService,
      fileService: _fileService,
      allowedRootPaths: config.allowedRoots.map((r) => r.absPath).toList(),
    );

    // Setup internal listeners
    _wsService.statusStream.listen((status) {
      for (final callback in _statusCallbacks) {
        callback(status);
      }
    });

    _wsService.errorStream.listen((error) {
      for (final callback in _errorCallbacks) {
        callback(error);
      }
    });
  }

  /// Create a new RemoteFileAgent instance
  ///
  /// [serverUrl] - WebSocket server URL (e.g., 'ws://localhost:18120/ws/agent')
  /// [enrollToken] - Authentication token
  /// [allowedPaths] - List of allowed directory paths
  /// [maxReconnectAttempts] - Maximum reconnect attempts (-1 for infinite)
  /// [version] - Agent version string
  static Future<RemoteFileAgent> create({
    required String serverUrl,
    required String enrollToken,
    required List<String> allowedPaths,
    int maxReconnectAttempts = -1,
    String version = '1.0.0',
  }) async {
    final deviceSettings = await DeviceSettings.getInstance();
    final deviceId = await deviceSettings.getDeviceId();
    final deviceName = await deviceSettings.getDeviceName();

    final config = AgentConfig.simple(
      serverUrl: serverUrl,
      enrollToken: enrollToken,
      allowedPaths: allowedPaths,
      maxReconnectAttempts: maxReconnectAttempts,
    );

    return RemoteFileAgent._(
      config: config,
      deviceSettings: deviceSettings,
      deviceId: deviceId,
      deviceName: deviceName,
      version: version,
    );
  }

  /// Create a new RemoteFileAgent instance with full configuration
  static Future<RemoteFileAgent> createWithConfig({
    required AgentConfig config,
    String version = '1.0.0',
  }) async {
    final deviceSettings = await DeviceSettings.getInstance();
    final deviceId = await deviceSettings.getDeviceId();
    final deviceName = await deviceSettings.getDeviceName();

    return RemoteFileAgent._(
      config: config,
      deviceSettings: deviceSettings,
      deviceId: deviceId,
      deviceName: deviceName,
      version: version,
    );
  }

  /// Current connection status
  ConnectionStatus get status => _wsService.status;

  /// Stream of connection status changes
  Stream<ConnectionStatus> get statusStream => _wsService.statusStream;

  /// Stream of error messages
  Stream<String> get errorStream => _wsService.errorStream;

  /// Stream of incoming messages
  Stream<Envelope> get messageStream => _wsService.messageStream;

  /// WebSocket service (for advanced usage)
  WebSocketService get wsService => _wsService;

  /// Heartbeat service (for advanced usage)
  HeartbeatService get heartbeatService => _heartbeatService;

  /// File service (for advanced usage)
  FileService get fileService => _fileService;

  /// Register a callback for status changes
  void onStatusChanged(StatusCallback callback) {
    _statusCallbacks.add(callback);
  }

  /// Register a callback for errors
  void onError(ErrorCallback callback) {
    _errorCallbacks.add(callback);
  }

  /// Start the agent (connect and begin heartbeat)
  Future<void> start() async {
    _messageHandler.startListening();
    await _wsService.connect();
    _heartbeatService.start();
  }

  /// Stop the agent (disconnect and stop heartbeat)
  Future<void> stop() async {
    _heartbeatService.stop();
    await _wsService.disconnect();
  }

  /// Update device name
  Future<void> updateDeviceName(String newName) async {
    await deviceSettings.setDeviceName(newName);
    await _wsService.updateDeviceName(newName);
  }

  /// Dispose all resources
  void dispose() {
    _heartbeatService.dispose();
    _wsService.dispose();
    _statusCallbacks.clear();
    _errorCallbacks.clear();
  }
}
