import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundService {
  static final SoundService instance = SoundService._init();
  bool isMuted = false;
  bool isTestMode = false;
  AudioPlayer? _player;

  SoundService._init();

  bool get _shouldSkipPlatformAudio =>
      isMuted || isTestMode || Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> _playAsset(String assetPath) async {
    if (_shouldSkipPlatformAudio) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(AssetSource(assetPath));
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  Future<void> playCompletionChime() async {
    await _playAsset('audio/chime_complete.wav');
  }

  Future<void> playOvertimeNudge() async {
    await _playAsset('audio/chime_nudge.wav');
  }

  Future<void> dispose() async {
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
