import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TransportLogService {
  TransportLogService({
    Future<Directory> Function()? supportDirectoryProvider,
    Duration flushInterval = const Duration(milliseconds: 350),
    Duration consoleThrottleWindow = const Duration(seconds: 1),
    DateTime Function()? now,
    void Function(String message)? consoleWriter,
    bool? throttleWindowsDebugConsole,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _flushInterval = flushInterval,
       _consoleThrottleWindow = consoleThrottleWindow,
       _now = now ?? DateTime.now,
       _consoleWriter = consoleWriter ?? debugPrint,
       _throttleWindowsDebugConsole =
           throttleWindowsDebugConsole ??
           (!kIsWeb && kDebugMode && Platform.isWindows);

  final Future<Directory> Function() _supportDirectoryProvider;
  final Duration _flushInterval;
  final Duration _consoleThrottleWindow;
  final DateTime Function() _now;
  final void Function(String message) _consoleWriter;
  final bool _throttleWindowsDebugConsole;

  File? _logFile;
  IOSink? _sink;
  Future<void>? _initializeFuture;
  Timer? _flushTimer;
  final List<String> _pendingLines = <String>[];
  final Map<String, DateTime> _lastConsoleEmissionByKey = <String, DateTime>{};
  bool _disposed = false;

  String? get logFilePath => _logFile?.path;

  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    final supportDirectory = await _supportDirectoryProvider();
    final logDirectory = Directory(
      p.join(supportDirectory.path, 'LocalDrop', 'logs'),
    );
    if (!await logDirectory.exists()) {
      await logDirectory.create(recursive: true);
    }
    _logFile = File(p.join(logDirectory.path, 'transport.log'));
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
    _sink = _logFile!.openWrite(mode: FileMode.append);
  }

  Future<void> log(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) async {
    await initialize();
    if (_disposed) {
      return;
    }

    final payload = <String, Object?>{
      'timestamp': _now().toUtc().toIso8601String(),
      'category': category,
      'message': message,
      if (data != null && data.isNotEmpty) 'data': data,
    };
    final line = jsonEncode(payload);

    _emitConsoleLog(category, message, data, line);

    _pendingLines.add('$line\n');
    _scheduleFlush();
  }

  Future<void> flush() async {
    if (_pendingLines.isEmpty || _sink == null) {
      return;
    }
    final pending = _pendingLines.join();
    _pendingLines.clear();
    _sink!.write(pending);
    await _sink!.flush();
  }

  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await initialize();
    await flush();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  void _scheduleFlush() {
    if (_flushTimer != null) {
      return;
    }
    _flushTimer = Timer(_flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  void _emitConsoleLog(
    String category,
    String message,
    Map<String, Object?>? data,
    String fallbackLine,
  ) {
    final rendered =
        '[LocalDrop][$category] $message${data == null || data.isEmpty ? '' : ' ${jsonEncode(data)}'}';
    if (!_throttleWindowsDebugConsole || !_isChattyCategory(category)) {
      _consoleWriter(rendered);
      return;
    }

    final now = _now();
    final lastEmittedAt = _lastConsoleEmissionByKey[rendered];
    if (lastEmittedAt != null &&
        now.difference(lastEmittedAt) < _consoleThrottleWindow) {
      return;
    }
    _lastConsoleEmissionByKey[rendered] = now;
    if (_lastConsoleEmissionByKey.length > 256) {
      _lastConsoleEmissionByKey.removeWhere(
        (_, value) => now.difference(value) > _consoleThrottleWindow * 4,
      );
    }
    _consoleWriter(rendered.isEmpty ? fallbackLine : rendered);
  }

  bool _isChattyCategory(String category) {
    return switch (category) {
      'peer-availability' || 'transfer-server' || 'discovery' => true,
      _ => false,
    };
  }
}
