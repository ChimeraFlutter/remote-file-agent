# Changelog

## 1.0.0

### Added
- Initial release
- WebSocket service with automatic reconnection
- Configurable max reconnect attempts (-1 for infinite)
- Heartbeat service with custom metrics provider support
- File service (list, delete, compress, upload)
- Device settings service (persistent device ID and name)
- Message handler for RPC operations
- High-level `RemoteFileAgent` API
- Path whitelist security validation
- Cross-platform support (macOS, iOS, Android, Windows, Linux)

### Features
- `RemoteFileAgent.create()` - Simple agent creation
- `RemoteFileAgent.createWithConfig()` - Advanced configuration
- `AgentConfig` - Full configuration options
- `AgentConfig.simple()` - Quick configuration from paths
- Status and error callbacks
- Stream-based message handling
