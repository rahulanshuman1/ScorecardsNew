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
  bool _wasMaximized = false;
  bool _busy = false;

  bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (_desktop) {
      try {
        await windowManager.ensureInitialized();
      } catch (_) {}
    }
  }

  Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 60));

  Future<void> set(bool v) async {
    if (_busy || v == on) return;
    _busy = true;
    on = v;
    notifyListeners();
    try {
      if (_desktop) {
        if (v) {
          // remember + leave the maximized state first (avoids a leftover title bar),
          // then drop the title bar / window buttons and go full screen
          try {
            _wasMaximized = await windowManager.isMaximized();
            if (_wasMaximized) {
              await windowManager.unmaximize();
              await _pause();
            }
          } catch (_) {}
          try {
            await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
                windowButtonVisibility: false);
            await _pause();
          } catch (_) {}
          await windowManager.setFullScreen(true);
          await _pause();
          try {
            await windowManager.focus();
          } catch (_) {}
        } else {
          await windowManager.setFullScreen(false);
          await _pause();
          try {
            await windowManager.setTitleBarStyle(TitleBarStyle.normal);
            await _pause();
          } catch (_) {}
          try {
            if (_wasMaximized) await windowManager.maximize();
          } catch (_) {}
        }
      } else {
        await SystemChrome.setEnabledSystemUIMode(
            v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> toggle() => set(!on);
}
