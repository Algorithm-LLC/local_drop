import 'dart:io';

import 'package:flutter/services.dart';

class AndroidNetworkLockService {
  static const MethodChannel _channel = MethodChannel('localdrop/network');

  Future<void> acquire() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {
      // Non-fatal: app can still run without explicit lock.
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {
      // Ignore release errors.
    }
  }
}
