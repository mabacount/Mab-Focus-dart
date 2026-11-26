import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// سرویس پخش صدای محیطی طبیعت و آبشار برای حالت زندگی (استراحت)
class NatureAmbienceService extends ChangeNotifier {
  static final NatureAmbienceService instance = NatureAmbienceService._init();

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  bool _isDisposed = false;
  bool _isPlaying = false;
  double _volume = 0.65;
  bool _isMuted = false;

  NatureAmbienceService._init() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final active = state == PlayerState.playing;
      if (_isPlaying != active) {
        _isPlaying = active;
        _safeNotify();
      }
    });
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  bool get isPlaying => _isPlaying;
  double get volume => _volume;
  bool get isMuted => _isMuted;

  Future<void> play() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_isMuted ? 0.0 : _volume);
      await _player.play(AssetSource('audio/nature_waterfall.wav'));
      _isPlaying = true;
      _safeNotify();
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _safeNotify();
    } catch (_) {}
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    if (!_isMuted) {
      try {
        await _player.setVolume(_volume);
      } catch (_) {}
    }
    _safeNotify();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    try {
      await _player.setVolume(_isMuted ? 0.0 : _volume);
    } catch (_) {}
    _safeNotify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stateSub?.cancel();
    _stateSub = null;
    _player.dispose();
    super.dispose();
  }
}
