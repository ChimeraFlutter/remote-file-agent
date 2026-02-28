import 'dart:io';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

/// Global logger utility
class AppLogger {
  static Logger? _logger;
  static File? _logFile;
  static IOSink? _logSink;

  /// Initialize logger with optional file output
  static void init({String? logFilePath}) {
    // Create file output if path is provided
    FileOutput? fileOutput;
    if (logFilePath != null) {
      try {
        _logFile = File(logFilePath);
        // Create parent directory if it doesn't exist
        final dir = _logFile!.parent;
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        // Open file for appending
        _logSink = _logFile!.openWrite(mode: FileMode.append);
        fileOutput = FileOutput(file: _logFile!, overrideExisting: false);
      } catch (e) {
        print('Failed to create log file: $e');
      }
    }

    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      output: fileOutput ?? ConsoleOutput(),
    );
  }

  /// Close log file
  static Future<void> close() async {
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    _logFile = null;
  }

  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.d(message, error: error, stackTrace: stackTrace);
    _writeToFile('DEBUG', message, error, stackTrace);
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.i(message, error: error, stackTrace: stackTrace);
    _writeToFile('INFO', message, error, stackTrace);
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.w(message, error: error, stackTrace: stackTrace);
    _writeToFile('WARN', message, error, stackTrace);
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.e(message, error: error, stackTrace: stackTrace);
    _writeToFile('ERROR', message, error, stackTrace);
  }

  static void _writeToFile(
    String level,
    String message,
    dynamic error,
    StackTrace? stackTrace,
  ) {
    if (_logSink == null) return;

    try {
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final logLine = StringBuffer('$timestamp [$level] $message');

      if (error != null) {
        logLine.write(' | Error: $error');
      }

      if (stackTrace != null) {
        logLine.write('\n$stackTrace');
      }

      _logSink!.writeln(logLine.toString());
    } catch (e) {
      // Ignore write errors
    }
  }
}
