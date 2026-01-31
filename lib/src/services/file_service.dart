import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

/// File information
class FileInfo {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int modifiedTime;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modifiedTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'is_dir': isDir,
      'size': size,
      'modified_time': modifiedTime,
    };
  }
}

/// File service for file system operations
class FileService {
  /// List directory contents
  Future<List<FileInfo>> listDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);

      if (!await dir.exists()) {
        return [];
      }

      final List<FileInfo> files = [];

      await for (final entity in dir.list()) {
        try {
          final stat = await entity.stat();
          final isDir = entity is Directory;

          files.add(FileInfo(
            name: path.basename(entity.path),
            path: entity.path,
            isDir: isDir,
            size: isDir ? 0 : stat.size,
            modifiedTime: stat.modified.millisecondsSinceEpoch ~/ 1000,
          ));
        } catch (e) {
          // Skip files that cannot be read
          continue;
        }
      }

      // Sort: directories first, then files
      files.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return files;
    } catch (e) {
      return [];
    }
  }

  /// Validate if path is within allowed roots
  bool isPathAllowed(String targetPath, List<String> allowedRoots) {
    try {
      final normalizedTarget = path.normalize(targetPath);

      // Allow temporary compression file directory
      if (normalizedTarget.contains('rfm_compress_')) {
        return true;
      }

      for (final root in allowedRoots) {
        final normalizedRoot = path.normalize(root);
        if (normalizedTarget.startsWith(normalizedRoot)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if path contains path traversal attack
  bool containsPathTraversal(String targetPath) {
    return targetPath.contains('../') || targetPath.contains('..\\');
  }

  /// Delete file or directory
  Future<bool> delete(String targetPath) async {
    try {
      final entity = FileSystemEntity.typeSync(targetPath);

      if (entity == FileSystemEntityType.directory) {
        await Directory(targetPath).delete(recursive: true);
      } else if (entity == FileSystemEntityType.file) {
        await File(targetPath).delete();
      } else {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Compress file or directory
  Future<Map<String, dynamic>> compress(String targetPath) async {
    final entity = FileSystemEntity.typeSync(targetPath);

    if (entity == FileSystemEntityType.notFound) {
      throw Exception('Path not found: $targetPath');
    }

    // Create temporary directory for compressed file
    final tempDir = await Directory.systemTemp.createTemp('rfm_compress_');
    final zipFileName = '${path.basenameWithoutExtension(targetPath)}.zip';
    final zipPath = path.join(tempDir.path, zipFileName);

    // Compress file or directory
    if (entity == FileSystemEntityType.directory) {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addDirectory(Directory(targetPath));
      encoder.close();
    } else if (entity == FileSystemEntityType.file) {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      await encoder.addFile(File(targetPath));
      encoder.close();
    }

    // Get compressed file info
    final zipFile = File(zipPath);
    final stat = await zipFile.stat();

    return {
      'zip_path': zipPath,
      'zip_name': zipFileName,
      'size': stat.size,
      'original_path': targetPath,
    };
  }

  /// Calculate file SHA256
  Future<String> calculateSHA256(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get file info (for upload)
  Future<Map<String, dynamic>> getFileInfo(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final stat = await file.stat();
    final sha256Hash = await calculateSHA256(filePath);

    return {
      'path': filePath,
      'name': path.basename(filePath),
      'size': stat.size,
      'sha256': sha256Hash,
      'modified_time': stat.modified.millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// Read file content (for upload)
  Future<List<int>> readFile(String filePath) async {
    final file = File(filePath);
    return await file.readAsBytes();
  }

  /// Cleanup temporary file (for post-compression cleanup)
  Future<bool> cleanupTempFile(String filePath) async {
    try {
      // Check if it's a file in temporary directory
      if (!filePath.contains('rfm_compress_')) {
        return false;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();

        // Try to delete temporary directory (if empty)
        final parentDir = file.parent;
        try {
          await parentDir.delete();
        } catch (e) {
          // Directory may not be empty or already deleted, ignore error
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}
