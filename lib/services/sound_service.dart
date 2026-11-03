import 'dart:io';
import 'package:flutter/services.dart';

class SoundService {
  static final SoundService instance = SoundService._init();
  bool isMuted = false;

  SoundService._init();

  Future<void> playCompletionChime() async {
    if (isMuted) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      if (Platform.isWindows) {
        await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            '[console]::beep(784, 180); [console]::beep(1046, 260)'
          ],
          runInShell: true,
        );
      }
    } catch (_) {}
  }

  Future<void> playOvertimeNudge() async {
    if (isMuted) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      if (Platform.isWindows) {
        await Process.run(
          'powershell',
          ['-NoProfile', '-Command', '[console]::beep(587, 220)'],
          runInShell: true,
        );
      }
    } catch (_) {}
  }
}
