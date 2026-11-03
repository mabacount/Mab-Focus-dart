import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/music_track.dart';
import '../models/pomodoro_state.dart';

class MusicPlayerService extends ChangeNotifier {
  static final MusicPlayerService instance = MusicPlayerService._init();

  final AudioPlayer _player = AudioPlayer();
  List<MusicTrack> _tracks = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  double _volume = 0.7;
  bool _isMuted = false;
  bool _pausedByBreak = false;
  bool _playDuringBreaks = false;

  MusicPlayerService._init() {
    _player.onPlayerComplete.listen((_) => nextTrack());
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
  }

  List<MusicTrack> get tracks => _tracks;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  bool get playDuringBreaks => _playDuringBreaks;
  MusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _tracks.length)
          ? _tracks[_currentIndex]
          : null;

  void setPlayDuringBreaks(bool value) {
    _playDuringBreaks = value;
    notifyListeners();
  }

  Future<int> loadTracksFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return 0;

    final List<MusicTrack> loaded = [];
    const validExtensions = {'.mp3', '.wav', '.ogg', '.flac', '.m4a', '.aac'};

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (validExtensions.contains(ext)) {
          final title = p.basenameWithoutExtension(entity.path);
          loaded.add(MusicTrack(filePath: entity.path, title: title));
        }
      }
    }

    _tracks = loaded;
    _currentIndex = _tracks.isNotEmpty ? 0 : -1;
    notifyListeners();
    return _tracks.length;
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    _currentIndex = index;
    final track = _tracks[_currentIndex];
    await _player.stop();
    await _player.setSourceDeviceFile(track.filePath);
    await _player.setVolume(_isMuted ? 0.0 : _volume);
    await _player.resume();
    _pausedByBreak = false;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_tracks.isEmpty) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_currentIndex == -1) _currentIndex = 0;
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await playTrack(_currentIndex);
      }
    }
    _pausedByBreak = false;
    notifyListeners();
  }

  Future<void> nextTrack() async {
    if (_tracks.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % _tracks.length;
    await playTrack(nextIndex);
  }

  Future<void> previousTrack() async {
    if (_tracks.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + _tracks.length) % _tracks.length;
    await playTrack(prevIndex);
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    if (!_isMuted) {
      await _player.setVolume(_volume);
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _player.setVolume(_isMuted ? 0.0 : _volume);
    notifyListeners();
  }

  void onPomodoroModeChanged(PomodoroMode mode) {
    if (mode == PomodoroMode.shortBreak || mode == PomodoroMode.longBreak) {
      if (!_playDuringBreaks && _isPlaying) {
        _player.pause();
        _pausedByBreak = true;
      }
    } else if (mode == PomodoroMode.focus) {
      if (_pausedByBreak) {
        _player.resume();
        _pausedByBreak = false;
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
