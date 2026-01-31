# Remote File Agent

A Flutter/Dart package for remote file management agent with WebSocket communication, automatic reconnection, and file operations.

## Features

- WebSocket-based real-time communication
- Automatic reconnection with configurable retry attempts (including infinite retry)
- Heartbeat service for connection health monitoring
- File operations: list, delete, compress, upload
- Path whitelist security validation
- Cross-platform support (macOS, iOS, Android, Windows, Linux)
- High-level API for quick integration
- Low-level API for custom implementations

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  remote_file_agent:
    path: ../remote_file_agent  # or git URL
```

## Quick Start

### Simple Usage

```dart
import 'package:remote_file_agent/remote_file_agent.dart';

void main() async {
  // Create agent with minimal configuration
  final agent = await RemoteFileAgent.create(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-token',
    allowedPaths: ['/Users/mac/Desktop', '/Users/mac/Documents'],
    maxReconnectAttempts: -1, // Infinite reconnection
  );

  // Register callbacks
  agent.onStatusChanged((status) {
    print('Status: $status');
  });

  agent.onError((error) {
    print('Error: $error');
  });

  // Start the agent
  await agent.start();
}
```

### Advanced Configuration

```dart
import 'package:remote_file_agent/remote_file_agent.dart';

void main() async {
  // Full configuration
  final config = AgentConfig(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-token',
    allowedRoots: [
      AllowedRoot(rootId: 'desktop', name: 'Desktop', absPath: '/Users/mac/Desktop'),
      AllowedRoot(rootId: 'docs', name: 'Documents', absPath: '/Users/mac/Documents'),
    ],
    heartbeatIntervalSeconds: 15,
    reconnectDelaySeconds: 5,
    maxReconnectAttempts: -1,
  );

  final agent = await RemoteFileAgent.createWithConfig(config: config);
  await agent.start();
}
```

### Custom Message Handling

```dart
import 'package:remote_file_agent/remote_file_agent.dart';

void main() async {
  final deviceSettings = await DeviceSettings.getInstance();

  // Use WebSocket service directly
  final wsService = WebSocketService(
    serverUrl: 'ws://localhost:18120/ws/agent',
    enrollToken: 'your-token',
    deviceId: await deviceSettings.getDeviceId(),
    deviceName: await deviceSettings.getDeviceName(),
    platform: deviceSettings.getPlatform(),
    version: '1.0.0',
    allowedRoots: [],
    maxReconnectAttempts: -1,
  );

  // Custom message handling
  wsService.messageStream.listen((envelope) {
    switch (envelope.type) {
      case MessageType.listReq:
        // Handle list request
        break;
      default:
        break;
    }
  });

  await wsService.connect();
}
```

## API Reference

### RemoteFileAgent

High-level API for quick integration.

| Method | Description |
|--------|-------------|
| `create()` | Create agent with simple configuration |
| `createWithConfig()` | Create agent with full configuration |
| `start()` | Connect and start heartbeat |
| `stop()` | Disconnect and stop heartbeat |
| `onStatusChanged()` | Register status callback |
| `onError()` | Register error callback |
| `dispose()` | Release all resources |

### AgentConfig

Configuration class for the agent.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `serverUrl` | String | required | WebSocket server URL |
| `enrollToken` | String | required | Authentication token |
| `allowedRoots` | List<AllowedRoot> | required | Allowed directories |
| `heartbeatIntervalSeconds` | int | 15 | Heartbeat interval |
| `reconnectDelaySeconds` | int | 5 | Reconnect delay |
| `maxReconnectAttempts` | int | -1 | Max reconnect attempts (-1 = infinite) |

### ConnectionStatus

| Status | Description |
|--------|-------------|
| `disconnected` | Not connected |
| `connecting` | Connecting to server |
| `connected` | Connected and authenticated |
| `reconnecting` | Attempting to reconnect |
| `failed` | Connection failed (max retries reached) |

## Examples

See the `example/` directory for complete examples:

- `simple_example.dart` - Quick start with minimal code
- `advanced_example.dart` - Full configuration options
- `custom_handler_example.dart` - Custom message handling

## License

MIT License
