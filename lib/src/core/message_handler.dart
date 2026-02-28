import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/file_service.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';

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
    AppLogger.info('MessageHandler: Starting to listen for messages');
    wsService.messageStream.listen((envelope) {
      AppLogger.info('MessageHandler: Received message type=${envelope.type}, reqId=${envelope.reqId}');
      _handleMessage(envelope);
    });
  }

  /// Handle message
  Future<void> _handleMessage(Envelope envelope) async {
    try {
      AppLogger.debug('MessageHandler: Handling message type=${envelope.type}');
      switch (envelope.type) {
        case MessageType.listReq:
          AppLogger.debug('MessageHandler: Handling listReq');
          await _handleListRequest(envelope);
          break;
        case MessageType.deleteReq:
          AppLogger.debug('MessageHandler: Handling deleteReq');
          await _handleDeleteRequest(envelope);
          break;
        case MessageType.zipReq:
          AppLogger.debug('MessageHandler: Handling zipReq');
          await _handleZipRequest(envelope);
          break;
        case MessageType.compressReq:
          AppLogger.debug('MessageHandler: Handling compressReq');
          await _handleCompressRequest(envelope);
          break;
        case MessageType.uploadReq:
          AppLogger.debug('MessageHandler: Handling uploadReq');
          await _handleUploadRequest(envelope);
          break;
        case MessageType.fileInfoReq:
          AppLogger.info('MessageHandler: Handling fileInfoReq for reqId=${envelope.reqId}');
          await _handleFileInfoRequest(envelope);
          break;
        default:
          AppLogger.warning('MessageHandler: Unknown message type=${envelope.type}');
          break;
      }
    } catch (e, stackTrace) {
      AppLogger.error('MessageHandler: Error handling message', e, stackTrace);
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
          path: path,
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
          path: path,
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
          path: targetPath,
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

  /// Handle file info request (get file metadata without reading content)
  Future<void> _handleFileInfoRequest(Envelope envelope) async {
    try {
      AppLogger.info('FileInfoRequest: Starting to handle reqId=${envelope.reqId}');
      final payload = envelope.payload as Map<String, dynamic>;
      final targetPath = payload['path'] as String;
      AppLogger.info('FileInfoRequest: Checking path=$targetPath');

      // Validate path
      if (fileService.containsPathTraversal(targetPath)) {
        AppLogger.warning('FileInfoRequest: Path traversal detected for path=$targetPath');
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path traversal detected',
        );
        return;
      }

      if (!fileService.isPathAllowed(targetPath, allowedRootPaths)) {
        AppLogger.warning('FileInfoRequest: Path not in whitelist: $targetPath, allowed: $allowedRootPaths');
        await _sendErrorResponse(
          envelope.reqId,
          'PATH_OUTSIDE_WHITELIST',
          'Path not in whitelist',
          path: targetPath,
        );
        return;
      }

      AppLogger.info('FileInfoRequest: Calling checkPath for $targetPath');
      // Use checkPath instead of getFileInfo (lightweight, no hash calculation)
      final pathInfo = await fileService.checkPath(targetPath);
      AppLogger.info('FileInfoRequest: checkPath completed, exists=${pathInfo['exists']}');

      // Send response with path info
      final response = Envelope(
        type: MessageType.fileInfoResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: pathInfo,
      );

      AppLogger.info('FileInfoRequest: Sending response for reqId=${envelope.reqId}');
      await wsService.sendMessage(response);
      AppLogger.info('FileInfoRequest: Response sent successfully');
    } catch (e, stackTrace) {
      AppLogger.error('FileInfoRequest: Failed for reqId=${envelope.reqId}', e, stackTrace);
      await _sendErrorResponse(envelope.reqId, 'FILE_INFO_FAILED', e.toString());
    }
  }

  /// Handle upload request
  Future<void> _handleUploadRequest(Envelope envelope) async {
    try {
      final payload = envelope.payload as Map<String, dynamic>;
      final targetPath = payload['path'] as String;
      final cleanupAfter = payload['cleanup_after'] as bool? ?? false;
      final uploadUrl = payload['upload_url'] as String?;

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
          path: targetPath,
        );
        return;
      }

      // Require upload_url
      if (uploadUrl == null || uploadUrl.isEmpty) {
        await _sendErrorResponse(
          envelope.reqId,
          'MISSING_UPLOAD_URL',
          'upload_url is required for file upload',
        );
        return;
      }

      // Get file info
      final fileInfo = await fileService.getFileInfo(targetPath);

      // Upload file via HTTP PUT with progress tracking
      final file = File(targetPath);
      final fileLength = await file.length();

      // Send initial progress (0%)
      await _sendProgressMessage(envelope.reqId, 0, fileLength, 'Starting upload');

      final client = HttpClient();
      final request = await client.putUrl(Uri.parse(uploadUrl));
      request.headers.set('Content-Type', 'application/octet-stream');
      request.headers.set('Content-Length', fileLength.toString());
      request.contentLength = fileLength;

      // Track upload progress
      var uploadedBytes = 0;
      var lastReportedPercent = 0;
      const chunkSize = 64 * 1024; // 64KB chunks
      const reportInterval = 1024 * 1024; // Report every 1MB

      final fileStream = file.openRead();
      await for (final chunk in fileStream) {
        request.add(chunk);
        uploadedBytes += chunk.length;

        // Report progress every 1MB or when percentage changes by 5%
        final currentPercent = (uploadedBytes * 100 / fileLength).round();
        if (uploadedBytes % reportInterval < chunkSize ||
            currentPercent >= lastReportedPercent + 5) {
          await _sendProgressMessage(
            envelope.reqId,
            uploadedBytes,
            fileLength,
            'Uploading',
          );
          lastReportedPercent = currentPercent;
        }
      }

      // Send final progress (100%)
      await _sendProgressMessage(envelope.reqId, fileLength, fileLength, 'Upload complete');

      final response = await request.close();

      if (response.statusCode != 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        throw Exception('HTTP upload failed: ${response.statusCode} - $responseBody');
      }

      client.close();

      // Send success response
      final responsePayload = {
        ...fileInfo,
        'uploaded': true,
        'upload_method': 'http',
      };

      final successResponse = Envelope(
        type: MessageType.uploadResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: responsePayload,
      );

      await wsService.sendMessage(successResponse);

      // Cleanup temporary file if needed
      if (cleanupAfter) {
        await fileService.cleanupTempFile(targetPath);
      }
    } catch (e) {
      await _sendErrorResponse(envelope.reqId, 'UPLOAD_FAILED', e.toString());
    }
  }

  /// Send progress message
  Future<void> _sendProgressMessage(
    String reqId,
    int uploadedBytes,
    int totalBytes,
    String status,
  ) async {
    final progressPayload = {
      'req_id': reqId,
      'uploaded_bytes': uploadedBytes,
      'total_bytes': totalBytes,
      'percent': (uploadedBytes * 100 / totalBytes).round(),
      'status': status,
    };

    final progressMessage = Envelope(
      type: MessageType.progress,
      reqId: reqId,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: wsService.deviceId,
      payload: progressPayload,
    );

    await wsService.sendMessage(progressMessage);
  }

  /// Send error response
  Future<void> _sendErrorResponse(
    String reqId,
    String code,
    String message, {
    String? path,
  }) async {
    final errorPayload = {
      'code': code,
      'message': message,
      'req_id': reqId,
      if (path != null) 'path': path,
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
