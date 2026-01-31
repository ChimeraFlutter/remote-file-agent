// ignore_for_file: avoid_print
import 'dart:io';
import 'package:remote_file_agent/remote_file_agent.dart';

/// Advanced example: Full configuration with custom settings
///
/// This example demonstrates how to use the full configuration options
/// and access lower-level services for advanced use cases.
void main() async {
  print('=== Remote File Agent - Advanced Example ===\n');

  // Initialize device settings
  final deviceSettings = await DeviceSettings.getInstance();
  final deviceId = await deviceSettings.getDeviceId();
  final deviceName = await deviceSettings.getDeviceName();

  print('Device ID: $deviceId');
  print('Device Name: $deviceName');
  print('Platform: ${deviceSettings.getPlatform()}\n');

  // Create full configuration
  final config = AgentConfig(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-secret-token-change-me',
    allowedRoots: [
      AllowedRoot(
        rootId: 'desktop',
        name: 'Desktop',
        absPath: '/Users/mac/Desktop',
      ),
      AllowedRoot(
        rootId: 'documents',
        name: 'Documents',
        absPath: '/Users/mac/Documents',
      ),
      AllowedRoot(
        rootId: 'downloads',
        name: 'Downloads',
        absPath: '/Users/mac/Downloads',
      ),
    ],
    heartbeatIntervalSeconds: 15,
    reconnectDelaySeconds: 5,
    maxReconnectAttempts: -1, // Infinite reconnection
    uploadChunkSize: 1024 * 1024, // 1MB
    maxConcurrentUploads: 3,
  );

  // Create agent with full config
  final agent = await RemoteFileAgent.createWithConfig(
    config: config,
    version: '1.0.0',
  );

  // Listen to status stream
  agent.statusStream.listen((status) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] Status changed: $status');
  });

  // Listen to error stream
  agent.errorStream.listen((error) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] Error: $error');
  });

  // Listen to message stream for custom handling
  agent.messageStream.listen((envelope) {
    print('Received message: ${envelope.type}');
    // You can add custom message handling here
  });

  // Start the agent
  print('Starting agent with advanced configuration...\n');
  await agent.start();

  print('Agent is running.');
  print('Allowed roots:');
  for (final root in config.allowedRoots) {
    print('  - ${root.name}: ${root.absPath}');
  }
  print('\nPress Ctrl+C to stop.\n');

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await agent.stop();
    agent.dispose();
    exit(0);
  });

  // Keep the process running
  await Future.delayed(const Duration(days: 365));
}
