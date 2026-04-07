import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowPersistence with WindowListener {
  static const String _widthKey = 'desktop_window_width';
  static const String _heightKey = 'desktop_window_height';
  static const double _minWidth = 330;
  static const double _minHeight = 520;
  static const Size _fallbackSize = Size(1100, 760);

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> configure() async {
    if (!_isDesktop) {
      return;
    }

    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final savedWidth = prefs.getDouble(_widthKey);
    final savedHeight = prefs.getDouble(_heightKey);

    final hasStoredSize = savedWidth != null && savedHeight != null;
    final initialSize = Size(
      (savedWidth ?? _fallbackSize.width).clamp(_minWidth, 10000),
      (savedHeight ?? _fallbackSize.height).clamp(_minHeight, 10000),
    );

    final windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: const Size(_minWidth, _minHeight),
      center: !hasStoredSize,
      title: 'LocalDrop',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
    await _persistCurrentBounds();
  }

  @override
  void onWindowResize() {
    _persistCurrentBounds();
  }

  @override
  void onWindowMove() {
    _persistCurrentBounds();
  }

  Future<void> _persistCurrentBounds() async {
    if (!_isDesktop) {
      return;
    }
    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_widthKey, bounds.width.clamp(_minWidth, 10000));
    await prefs.setDouble(_heightKey, bounds.height.clamp(_minHeight, 10000));
  }
}
