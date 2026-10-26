import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await BoonWindow.configure();
  } catch (_) {
    // Native window setup is unavailable/failed — fall back to a normal
    // windowed app instead of not starting at all.
  }
  runApp(const BoonApp());
}
