import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// App-wide full-screen switch. Only the window / system bars change: no screen is
/// rebuilt from scratch, so the match, score, teams, toss and league stay untouched.
class FullScreen extends ChangeNotifier {
  static final FullScreen I = FullScreen._();
  FullScreen._();

  bool on = false;

  bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (_desktop) {
      try {
        await windowManager.ensureInitialized();
      } catch (_) {}
    }
  }

  Future<void> set(bool v) async {
    on = v;
    notifyListeners();
    try {
      if (_desktop) {
        await windowManager.setFullScreen(v);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
            v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  Future<void> toggle() => set(!on);
}
