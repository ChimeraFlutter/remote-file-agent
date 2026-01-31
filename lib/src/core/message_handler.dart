import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/file_service.dart';
import '../services/websocket_service.dart';

/// RPC message handler
class MessageHandler {
  final WebSocketService wsService;
  final FileService fileService;
  final List<String> allowedRootPaths;
  final _uuid = const Uuid();

  MessageHandler({
    required this.wsService,
    required this.fileService,
    required this.allowedRootPaths,
  });

  /// Start listening for messages
  void startListening() {
    wsService.messageStream.listen((envelope) {
      _handleMessage(envelope);
    });
  }

  /// Handle message
  Future<void> _handleMessage(Envelope envelope) async {
    try {
      switch (envelope.type) {
        case MessageType.listReq:
          await _handleListRequest(envelope);
          break;
        case MessageType.deleteReq:
          await _handleDeleteRequest(envelope);
          break;
        case MessageType.zipReq:
          await _handleZipRequest(envelope);
          break;
        case MessageType.compressReq:
          await _handleCompressRequest(envelope);
          break;
        case MessageType.uploadReq:
          await _handleUploadRequest(envelope);
          break;
        default:
          break;
      }
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'INTERNAL_ERROR', e.toString());
    }
  }

  /// Handle file list request
  Future<void> _handleListRequest(Envelope envelope) async {
    try {
      final payload = envelope.payload as Map<String, dynamic>;
      final path = payload['path'] as String;

      // Validate path
      if (fileService.containsPathTraversal(path)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path traversal detected',
        );
        return;
      }

      if (!fileService.isPathAllowed(path, allowedRootPaths)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path not in whitelist',
        );
        return;
      }

      // List directory contents
      final files = await fileService.listDirectory(path);

      // Send response
      final responsePayload = {
        'path': path,
        'entries': files.map((f) => f.toJson()).toList(),
      };

      final response = Envelope(
        type: MessageType.listResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: responsePayload,
      );

      await wsService.sendMessage(response);
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'INTERNAL_ERROR', e.toString());
    }
  }

  /// Handle delete request
  Future<void> _handleDeleteRequest(Envelope envelope) async {
    try {
      final payload = envelope.payload as Map<String, dynamic>;
      final path = payload['path'] as String;

      // Validate path
      if (fileService.containsPathTraversal(path)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path traversal detected',
        );
        return;
      }

      if (!fileService.isPathAllowed(path, allowedRootPaths)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path not in whitelist',
        );
        return;
      }

      // Delete file/directory
      final success = await fileService.delete(path);

      // Send response
      final responsePayload = {
        'success': success,
        'message': success ? 'Deleted successfully' : 'Failed to delete',
      };

      final response = Envelope(
        type: MessageType.deleteResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: responsePayload,
      );

      await wsService.sendMessage(response);
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'DELETE_FAILED', e.toString());
    }
  }

  /// Handle zip request (placeholder)
  Future<void> _handleZipRequest(Envelope envelope) async {
    await _sendErrorResponse(
      envelope.reqId,
      'NOT_IMPLEMENTED',
      'Zip functionality not implemented',
    );
  }

  /// Handle compress request
  Future<void> _handleCompressRequest(Envelope envelope) async {
    try {
      final payload = envelope.payload as Map<String, dynamic>;
      final targetPath = payload['path'] as String;

      // Validate path
      if (fileService.containsPathTraversal(targetPath)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path traversal detected',
        );
        return;
      }

      if (!fileService.isPathAllowed(targetPath, allowedRootPaths)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path not in whitelist',
        );
        return;
      }

      // Compress file/directory
      final result = await fileService.compress(targetPath);

      // Send response
      final response = Envelope(
        type: MessageType.compressResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: result,
      );

      await wsService.sendMessage(response);
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'COMPRESS_FAILED', e.toString());
    }
  }

  /// Handle upload request
  Future<void> _handleUploadRequest(Envelope envelope) async {
    try {
      final payload = envelope.payload as Map<String, dynamic>;
      final targetPath = payload['path'] as String;
      final cleanupAfter = payload['cleanup_after'] as bool? ?? false;

      // Validate path
      if (fileService.containsPathTraversal(targetPath)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path traversal detected',
        );
        return;
      }

      if (!fileService.isPathAllowed(targetPath, allowedRootPaths)) {
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path not in whitelist',
        );
        return;
      }

      // Get file info
      final fileInfo = await fileService.getFileInfo(targetPath);

      // Read file content
      final fileBytes = await fileService.readFile(targetPath);

      // Send response (including file info and content)
      final responsePayload = {
        ...fileInfo,
        'data': base64Encode(fileBytes),
      };

      final response = Envelope(
        type: MessageType.uploadResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: responsePayload,
      );

      await wsService.sendMessage(response);

      // Cleanup temporary file if needed (for compressed files)
      if (cleanupAfter) {
        await fileService.cleanupTempFile(targetPath);
      }
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'UPLOAD_FAILED', e.toString());
    }
  }

  /// Send error response
  Future<void> _sendErrorResponse(
    String reqId,
    String code,
    String message,
  ) async {
    final errorPayload = {
      'code': code,
      'message': message,
      'req_id': reqId,
    };

    final response = Envelope(
      type: MessageType.error,
      reqId: reqId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: wsService.deviceId,
      payload: errorPayload,
    );

    await wsService.sendMessage(response);
  }
}
