// ignore_for_file: avoid_print
import 'dart:io';
import 'package:remote_file_agent/remote_file_agent.dart';

/// Simple example: Quick start with minimal configuration
///
/// This example shows the simplest way to create and start a remote file agent.
void main() async {
  print('=== Remote File Agent - Simple Example ===\n');

  // Create agent with minimal configuration
  final agent = await RemoteFileAgent.create(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-secret-token-change-me',
    allowedPaths: [
      '/Users/mac/Desktop',
      '/Users/mac/Documents',
      '/Users/mac/Downloads',
    ],
    maxReconnectAttempts: -1, // Infinite reconnection
  );

  // Register status callback
  agent.onStatusChanged((status) {
    print('[Status] $status');

    if (status == ConnectionStatus.connected) {
      print('[Info] Agent is now connected and ready!');
    } else if (status == ConnectionStatus.reconnecting) {
      print('[Info] Connection lost, attempting to reconnect...');
    }
  });

  // Register error callback
  agent.onError((error) {
    print('[Error] $error');
  });

  // Start the agent
  print('Starting agent...');
  await agent.start();

  print('\nAgent is running. Press Ctrl+C to stop.\n');

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
