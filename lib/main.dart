import 'package:flutter/material.dart';

import 'app/local_drop_app.dart';
import 'core/window/desktop_window_persistence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktopWindowPersistence = DesktopWindowPersistence();
  await desktopWindowPersistence.configure();
  runApp(const LocalDropApp());
}
