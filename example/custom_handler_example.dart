// ignore_for_file: avoid_print
import 'dart:io';
import 'package:remote_file_agent/remote_file_agent.dart';

/// Custom handler example: Implement your own message handling
///
/// This example shows how to use the low-level WebSocket service
/// directly for custom message handling scenarios.
void main() async {
  print('=== Remote File Agent - Custom Handler Example ===\n');

  // Initialize device settings
  final deviceSettings = await DeviceSettings.getInstance();
  final deviceId = await deviceSettings.getDeviceId();
  final deviceName = await deviceSettings.getDeviceName();

  // Create WebSocket service directly
  final wsService = WebSocketService(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-secret-token-change-me',
    deviceId: deviceId,
    deviceName: deviceName,
    platform: deviceSettings.getPlatform(),
    version: '1.0.0',
    allowedRoots: [
      AllowedRoot(
        rootId: 'desktop',
        name: 'Desktop',
        absPath: '/Users/mac/Desktop',
      ),
    ],
    maxReconnectAttempts: -1,
    reconnectDelay: const Duration(seconds: 5),
  );

  // Create heartbeat service with custom metrics provider
  final heartbeatService = HeartbeatService(
    webSocketService: wsService,
    interval: const Duration(seconds: 15),
    metricsProvider: () async {
      // Custom metrics collection
      // In a real app, you would collect actual system metrics here
      return {
        'cpu_percent': 25.5,
        'memory_mb': 4096,
        'disk_free_gb': 100,
      };
    },
  );

  // Listen to status changes
  wsService.statusStream.listen((status) {
    print('[Status] $status');
  });

  // Listen to errors
  wsService.errorStream.listen((error) {
    print('[Error] $error');
  });

  // Custom message handling
  wsService.messageStream.listen((envelope) {
    print('\n[Message] Type: ${envelope.type}');
    print('[Message] ReqId: ${envelope.reqId}');

    // Handle different message types
    switch (envelope.type) {
      case MessageType.listReq:
        _handleListRequest(wsService, envelope);
        break;
      case MessageType.deleteReq:
        _handleDeleteRequest(wsService, envelope);
        break;
      default:
        print('[Message] Unhandled type: ${envelope.type}');
    }
  });

  // Connect and start heartbeat
  print('Connecting to server...');
  await wsService.connect();
  heartbeatService.start();

  print('\nCustom handler is running. Press Ctrl+C to stop.\n');

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    heartbeatService.stop();
    await wsService.disconnect();
    wsService.dispose();
    exit(0);
  });

  // Keep the process running
  await Future.delayed(const Duration(days: 365));
}

/// Custom list request handler
void _handleListRequest(WebSocketService ws, Envelope envelope) async {
  print('[Handler] Processing list request...');

  final payload = envelope.payload;
  final path = payload['path'] as String;
  print('[Handler] Path: $path');

  // Custom logic here
  // For example, you could add logging, filtering, or custom validation

  // Use FileService for actual file operations
  final fileService = FileService();
  final files = await fileService.listDirectory(path);

  // Send response
  final response = Envelope(
    type: MessageType.listResp,
    reqId: envelope.reqId,
    timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    deviceId: ws.deviceId,
    payload: {
      'path': path,
      'entries': files.map((f) => f.toJson()).toList(),
    },
  );

  await ws.sendMessage(response);
  print('[Handler] Sent list response with ${files.length} entries');
}

/// Custom delete request handler
void _handleDeleteRequest(WebSocketService ws, Envelope envelope) async {
  print('[Handler] Processing delete request...');

  final payload = envelope.payload;
  final path = payload['path'] as String;
  print('[Handler] Path: $path');

  // Custom validation - for example, prevent deletion of certain files
  if (path.endsWith('.important')) {
    print('[Handler] Blocked deletion of important file');

    final errorResponse = Envelope(
      type: MessageType.error,
      reqId: envelope.reqId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: ws.deviceId,
      payload: {
        'code': 'DELETION_BLOCKED',
        'message': 'Cannot delete important files',
        'req_id': envelope.reqId,
      },
    );

    await ws.sendMessage(errorResponse);
    return;
  }

  // Proceed with deletion
  final fileService = FileService();
  final success = await fileService.delete(path);

  final response = Envelope(
    type: MessageType.deleteResp,
    reqId: envelope.reqId,
    timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    deviceId: ws.deviceId,
    payload: {
      'success': success,
      'message': success ? 'Deleted successfully' : 'Failed to delete',
    },
  );

  await ws.sendMessage(response);
  print('[Handler] Sent delete response: $success');
}
