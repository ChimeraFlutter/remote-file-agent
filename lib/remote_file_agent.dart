/// Remote File Agent - A Flutter package for remote file management
///
/// This package provides WebSocket-based communication with a remote file
/// management server, including automatic reconnection, heartbeat, and
/// file operations.
library remote_file_agent;

// Models
export 'src/models/message.dart';

// Services
export 'src/services/websocket_service.dart';
export 'src/services/heartbeat_service.dart';
export 'src/services/file_service.dart';
export 'src/services/device_settings.dart';

// Core
export 'src/core/config.dart';
export 'src/core/message_handler.dart';

// Utils
export 'src/utils/logger.dart';

// High-level API
export 'src/remote_file_agent.dart';
