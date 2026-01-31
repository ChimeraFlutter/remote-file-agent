import 'dart:convert';

/// Message types for WebSocket communication
enum MessageType {
  hello,
  helloAck,
  listReq,
  listResp,
  deleteReq,
  deleteResp,
  zipReq,
  zipResp,
  compressReq,
  compressResp,
  uploadReq,
  uploadResp,
  progress,
  heartbeat,
  error,
}

/// Extension to convert MessageType to/from string
extension MessageTypeExtension on MessageType {
  String toJson() {
    switch (this) {
      case MessageType.hello:
        return 'hello';
      case MessageType.helloAck:
        return 'hello_ack';
      case MessageType.listReq:
        return 'list_req';
      case MessageType.listResp:
        return 'list_resp';
      case MessageType.deleteReq:
        return 'delete_req';
      case MessageType.deleteResp:
        return 'delete_resp';
      case MessageType.zipReq:
        return 'zip_req';
      case MessageType.zipResp:
        return 'zip_resp';
      case MessageType.compressReq:
        return 'compress_req';
      case MessageType.compressResp:
        return 'compress_resp';
      case MessageType.uploadReq:
        return 'upload_req';
      case MessageType.uploadResp:
        return 'upload_resp';
      case MessageType.progress:
        return 'progress';
      case MessageType.heartbeat:
        return 'heartbeat';
      case MessageType.error:
        return 'error';
    }
  }

  static MessageType fromJson(String value) {
    switch (value) {
      case 'hello':
        return MessageType.hello;
      case 'hello_ack':
        return MessageType.helloAck;
      case 'list_req':
        return MessageType.listReq;
      case 'list_resp':
        return MessageType.listResp;
      case 'delete_req':
        return MessageType.deleteReq;
      case 'delete_resp':
        return MessageType.deleteResp;
      case 'zip_req':
        return MessageType.zipReq;
      case 'zip_resp':
        return MessageType.zipResp;
      case 'compress_req':
        return MessageType.compressReq;
      case 'compress_resp':
        return MessageType.compressResp;
      case 'upload_req':
        return MessageType.uploadReq;
      case 'upload_resp':
        return MessageType.uploadResp;
      case 'progress':
        return MessageType.progress;
      case 'heartbeat':
        return MessageType.heartbeat;
      case 'error':
        return MessageType.error;
      default:
        throw ArgumentError('Unknown message type: $value');
    }
  }
}

/// Message envelope for all WebSocket messages
class Envelope {
  final MessageType type;
  final String reqId;
  final int timestamp;
  final String deviceId;
  final Map<String, dynamic> payload;

  Envelope({
    required this.type,
    required this.reqId,
    required this.timestamp,
    required this.deviceId,
    required this.payload,
  });

  factory Envelope.fromJson(Map<String, dynamic> json) {
    return Envelope(
      type: MessageTypeExtension.fromJson(json['type'] as String),
      reqId: json['req_id'] as String,
      timestamp: json['ts'] as int,
      deviceId: json['device_id'] as String,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toJson(),
      'req_id': reqId,
      'ts': timestamp,
      'device_id': deviceId,
      'payload': payload,
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }
}

/// Hello payload sent when connecting
class HelloPayload {
  final String enrollToken;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String version;
  final List<AllowedRoot> allowedRoots;

  HelloPayload({
    required this.enrollToken,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.version,
    required this.allowedRoots,
  });

  Map<String, dynamic> toJson() {
    return {
      'enroll_token': enrollToken,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'version': version,
      'allowed_roots': allowedRoots.map((r) => r.toJson()).toList(),
    };
  }
}

/// Allowed root directory
class AllowedRoot {
  final String rootId;
  final String name;
  final String absPath;

  AllowedRoot({
    required this.rootId,
    required this.name,
    required this.absPath,
  });

  factory AllowedRoot.fromJson(Map<String, dynamic> json) {
    return AllowedRoot(
      rootId: json['root_id'] as String,
      name: json['name'] as String,
      absPath: json['abs_path'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'root_id': rootId,
      'name': name,
      'abs_path': absPath,
    };
  }
}

/// Hello acknowledgment payload
class HelloAckPayload {
  final bool success;
  final String? message;

  HelloAckPayload({
    required this.success,
    this.message,
  });

  factory HelloAckPayload.fromJson(Map<String, dynamic> json) {
    return HelloAckPayload(
      success: json['success'] as bool,
      message: json['message'] as String?,
    );
  }
}

/// Heartbeat payload
class HeartbeatPayload {
  final double cpuPercent;
  final int memoryMb;
  final int diskFreeGb;

  HeartbeatPayload({
    required this.cpuPercent,
    required this.memoryMb,
    required this.diskFreeGb,
  });

  Map<String, dynamic> toJson() {
    return {
      'cpu_percent': cpuPercent,
      'memory_mb': memoryMb,
      'disk_free_gb': diskFreeGb,
    };
  }
}

/// Error payload
class ErrorPayload {
  final String code;
  final String message;
  final String? reqId;

  ErrorPayload({
    required this.code,
    required this.message,
    this.reqId,
  });

  factory ErrorPayload.fromJson(Map<String, dynamic> json) {
    return ErrorPayload(
      code: json['code'] as String,
      message: json['message'] as String,
      reqId: json['req_id'] as String?,
    );
  }
}
