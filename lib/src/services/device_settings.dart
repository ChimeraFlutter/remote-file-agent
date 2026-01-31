import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Service for managing persistent device settings
class DeviceSettings {
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceName = 'device_name';

  static DeviceSettings? _instance;
  static SharedPreferences? _prefs;

  DeviceSettings._();

  /// Initialize the device settings service
  static Future<DeviceSettings> getInstance() async {
    if (_instance == null) {
      _instance = DeviceSettings._();
      _prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Get or create device ID (persisted forever)
  Future<String> getDeviceId() async {
    String? deviceId = _prefs?.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _prefs?.setString(_keyDeviceId, deviceId);
    }
    return deviceId;
  }

  /// Get device name (returns default if not set)
  Future<String> getDeviceName() async {
    String? deviceName = _prefs?.getString(_keyDeviceName);
    if (deviceName == null || deviceName.isEmpty) {
      // Default device name based on platform
      deviceName = _getDefaultDeviceName();
    }
    return deviceName;
  }

  /// Save device name
  Future<void> setDeviceName(String name) async {
    await _prefs?.setString(_keyDeviceName, name);
  }

  /// Check if device name has been customized
  bool hasCustomDeviceName() {
    final name = _prefs?.getString(_keyDeviceName);
    return name != null && name.isNotEmpty;
  }

  /// Get default device name based on platform
  String _getDefaultDeviceName() {
    if (Platform.isMacOS) {
      return 'MacBook';
    } else if (Platform.isIOS) {
      return 'iPhone';
    } else if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isWindows) {
      return 'Windows PC';
    } else if (Platform.isLinux) {
      return 'Linux Device';
    }
    return 'Unknown Device';
  }

  /// Get platform string
  String getPlatform() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
