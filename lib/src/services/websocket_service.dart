import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../utils/logger.dart';

/// Connection status
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// WebSocket service for agent-server communication
class WebSocketService {
  final String serverUrl;
  final String enrollToken;
  final String deviceId;
  String _deviceName;
  final String platform;
  final String version;
  final List<AllowedRoot> allowedRoots;

  /// Maximum reconnect attempts. Set to -1 for infinite reconnection.
  final int maxReconnectAttempts;

  /// Delay between reconnection attempts.
  final Duration reconnectDelay;

  String get deviceName => _deviceName;

  WebSocket? _socket;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  final _uuid = const Uuid();

  // Stream controllers
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<Envelope>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  WebSocketService({
    required this.serverUrl,
    required this.enrollToken,
    required this.deviceId,
    required String deviceName,
    required this.platform,
    required this.version,
    required this.allowedRoots,
    this.maxReconnectAttempts = -1,
    this.reconnectDelay = const Duration(seconds: 5),
  }) : _deviceName = deviceName;

  // Getters
  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Envelope> get messageStream => _messageController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Connect to the server
  Future<void> connect() async {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }

    _updateStatus(ConnectionStatus.connecting);

    try {
      // Connect to WebSocket
      _socket = await WebSocket.connect(serverUrl);

      // Setup listeners
      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      // Send hello message
      await _sendHello();

      // Don't set connected here - wait for hello_ack
      _reconnectAttempts = 0;
    } catch (e) {
      _handleError(e);
    }
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }

    _updateStatus(ConnectionStatus.disconnected);
  }

  /// Update device name and notify server
  Future<void> updateDeviceName(String newName) async {
    if (newName == _deviceName) return;

    _deviceName = newName;

    // If connected, send a new hello to update the server
    if (_status == ConnectionStatus.connected && _socket != null) {
      await _sendHello();
    }
  }

  /// Send a message to the server
  Future<void> sendMessage(Envelope envelope) async {
    if (_socket == null || _status != ConnectionStatus.connected) {
      throw Exception('Not connected to server');
    }

    final json = envelope.toJsonString();
    _socket!.add(json);
  }

  /// Send hello message (directly to socket, bypassing status check)
  Future<void> _sendHello() async {
    if (_socket == null) {
      throw Exception('Socket not initialized');
    }

    final payload = HelloPayload(
      enrollToken: enrollToken,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
      version: version,
      allowedRoots: allowedRoots,
    );

    final envelope = Envelope(
      type: MessageType.hello,
      reqId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: deviceId,
      payload: payload.toJson(),
    );

    // Send directly to socket (status is still 'connecting' at this point)
    _socket!.add(envelope.toJsonString());
  }

  /// Send heartbeat message
  Future<void> sendHeartbeat({
    required double cpuPercent,
    required int memoryMb,
    required int diskFreeGb,
  }) async {
    final payload = HeartbeatPayload(
      cpuPercent: cpuPercent,
      memoryMb: memoryMb,
      diskFreeGb: diskFreeGb,
    );

    final envelope = Envelope(
      type: MessageType.heartbeat,
      reqId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: deviceId,
      payload: payload.toJson(),
    );

    await sendMessage(envelope);
  }

  /// Handle incoming messages
  void _handleMessage(dynamic data) {
    try {
      AppLogger.debug('WebSocket: Received raw message: ${data.toString().substring(0, min(200, data.toString().length))}');
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      AppLogger.debug('WebSocket: Decoded JSON, type=${json['type']}');
      final envelope = Envelope.fromJson(json);
      AppLogger.info('WebSocket: Parsed envelope, type=${envelope.type}, reqId=${envelope.reqId}');

      // Handle specific message types
      switch (envelope.type) {
        case MessageType.helloAck:
          AppLogger.info('WebSocket: Handling helloAck');
          _handleHelloAck(envelope);
          break;
        case MessageType.error:
          AppLogger.warning('WebSocket: Handling error message');
          _handleErrorMessage(envelope);
          break;
        default:
          // Forward to message stream
          AppLogger.info('WebSocket: Forwarding message to stream, type=${envelope.type}');
          _messageController.add(envelope);
      }
    } catch (e, stackTrace) {
      AppLogger.error('WebSocket: Error handling message', e, stackTrace);
      _errorController.add('Failed to parse message: $e');
    }
  }

  /// Handle hello acknowledgment
  void _handleHelloAck(Envelope envelope) {
    final payload = HelloAckPayload.fromJson(envelope.payload);

    if (!payload.success) {
      _errorController.add('Hello failed: ${payload.message}');
      disconnect();
    } else {
      // Hello successful, now we're truly connected
      _updateStatus(ConnectionStatus.connected);
    }
  }

  /// Handle error messages
  void _handleErrorMessage(Envelope envelope) {
    final payload = ErrorPayload.fromJson(envelope.payload);
    _errorController.add('Server error: ${payload.code} - ${payload.message}');
  }

  /// Handle errors
  void _handleError(dynamic error) {
    _errorController.add('WebSocket error: $error');
    _attemptReconnect();
  }

  /// Handle disconnection
  void _handleDisconnect() {
    _updateStatus(ConnectionStatus.disconnected);
    _attemptReconnect();
  }

  /// Attempt to reconnect
  void _attemptReconnect() {
    // maxReconnectAttempts == -1 means infinite reconnection
    if (maxReconnectAttempts != -1 &&
        _reconnectAttempts >= maxReconnectAttempts) {
      _updateStatus(ConnectionStatus.failed);
      _errorController.add('Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    _updateStatus(ConnectionStatus.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      connect();
    });
  }

  /// Reset reconnect counter (call this when you want to restart reconnection)
  void resetReconnectCounter() {
    _reconnectAttempts = 0;
  }

  /// Update connection status
  void _updateStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// Dispose resources
  void dispose() {
    _reconnectTimer?.cancel();
    _socket?.close();
    _statusController.close();
    _messageController.close();
    _errorController.close();
  }
}
