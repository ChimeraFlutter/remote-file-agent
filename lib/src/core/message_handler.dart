import 'dart:convert';
import 'dart:io';
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
        case MessageType.fileInfoReq:
          await _handleFileInfoRequest(envelope);
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

      // Get file info only (no file content)
      final fileInfo = await fileService.getFileInfo(targetPath);

      // Send response with file info only
      final response = Envelope(
        type: MessageType.fileInfoResp,
        reqId: envelope.reqId,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deviceId: wsService.deviceId,
        payload: fileInfo,
      );

      await wsService.sendMessage(response);
    } catch (e) {
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

      // Get file info
      final fileInfo = await fileService.getFileInfo(targetPath);

      // If upload_url is provided, upload via HTTP with progress reporting
      if (uploadUrl != null && uploadUrl.isNotEmpty) {
        try {
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

          // Send success response (without file data)
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
          await _sendErrorResponse(envelope.reqId, 'HTTP_UPLOAD_FAILED', e.toString());
        }
      } else {
        // Fallback: Old method (WebSocket with Base64)
        // This should not be used for large files
        final fileBytes = await fileService.readFile(targetPath);

        // Check file size limit (10MB for WebSocket)
        if (fileBytes.length > 10 * 1024 * 1024) {
          await _sendErrorResponse(
            envelope.reqId,
            'FILE_TOO_LARGE',
            'File exceeds 10MB limit for WebSocket upload. Use HTTP upload instead.',
          );
          return;
        }

        // Send response (including file info and content)
        final responsePayload = {
          ...fileInfo,
          'data': base64Encode(fileBytes),
          'upload_method': 'websocket',
        };

        final response = Envelope(
          type: MessageType.uploadResp,
          reqId: envelope.reqId,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          deviceId: wsService.deviceId,
          payload: responsePayload,
        );

        await wsService.sendMessage(response);

        // Cleanup temporary file if needed
        if (cleanupAfter) {
          await fileService.cleanupTempFile(targetPath);
        }
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
