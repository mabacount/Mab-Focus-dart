import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/music_track.dart';
import '../models/pomodoro_state.dart';
import 'database_service.dart';
import 'ecosystem_bridge_service.dart';

class MusicPlayerService extends ChangeNotifier {
  static final MusicPlayerService instance = MusicPlayerService._init();

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _isDisposed = false;
  List<MusicPlaylist> _playlists = [];
  MusicPlaylist? _activePlaylist;
  List<MusicTrack> _tracks = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isShuffle = true; // پخش رندم به صورت پیش‌فرض فعال است
  double _volume = 0.7;
  bool _isMuted = false;
  bool _pausedByBreak = false;
  bool _playDuringBreaks = false;

  MusicPlayerService._init() {
    _completeSub = _player.onPlayerComplete.listen((_) => nextTrack());
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _safeNotify();
    });
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  List<MusicPlaylist> get playlists => _playlists;
  MusicPlaylist? get activePlaylist => _activePlaylist;
  List<MusicTrack> get tracks => _tracks;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isShuffle => _isShuffle;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  bool get playDuringBreaks => _playDuringBreaks;
  MusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _tracks.length)
          ? _tracks[_currentIndex]
          : null;

  void setPlayDuringBreaks(bool value) {
    _playDuringBreaks = value;
    _safeNotify();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    _safeNotify();
  }

  Future<void> loadPlaylists() async {
    try {
      _playlists = await DatabaseService.instance.getAllMusicPlaylists();
      if (_playlists.isNotEmpty) {
        MusicPlaylist? target;
        for (final item in _playlists) {
          if (item.isDefault) {
            target = item;
            break;
          }
        }
        target ??= _playlists.first;
        if (_activePlaylist == null ||
            !_playlists.any((p) => p.id == _activePlaylist!.id)) {
          await selectPlaylist(target, autoPlay: false);
        }
      } else {
        _activePlaylist = null;
        _tracks = [];
        _currentIndex = -1;
      }
    } catch (_) {}
    _safeNotify();
  }

  Future<MusicPlaylist?> addFolder(String folderPath,
      {String? customName}) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    final name = (customName != null && customName.trim().isNotEmpty)
        ? customName.trim()
        : p.basename(folderPath);

    final isFirst = _playlists.isEmpty;
    final playlist = MusicPlaylist(
      id: const Uuid().v4(),
      name: name.isEmpty ? 'پوشه موسیقی' : name,
      folderPath: folderPath,
      isDefault: isFirst,
    );

    EcosystemBridgeService.instance.notifyInternalWrite();
    await DatabaseService.instance.insertMusicPlaylist(playlist);
    EcosystemBridgeService.instance.notifyInternalWrite();
    _playlists = await DatabaseService.instance.getAllMusicPlaylists();
    await selectPlaylist(playlist, autoPlay: false);
    _safeNotify();
    return playlist;
  }

  Future<void> selectPlaylist(MusicPlaylist playlist,
      {bool autoPlay = false}) async {
    _activePlaylist = playlist;
    try {
      EcosystemBridgeService.instance.notifyInternalWrite();
      await DatabaseService.instance.setDefaultMusicPlaylist(playlist.id);
      EcosystemBridgeService.instance.notifyInternalWrite();
      _playlists = await DatabaseService.instance.getAllMusicPlaylists();
    } catch (_) {}

    await loadTracksFromFolder(playlist.folderPath);

    if (_tracks.isNotEmpty) {
      if (_isShuffle) {
        _currentIndex = Random().nextInt(_tracks.length);
      } else {
        _currentIndex = 0;
      }
      if (autoPlay) {
        await playTrack(_currentIndex);
      }
    }
    _safeNotify();
  }

  Future<void> deletePlaylist(String playlistId) async {
    EcosystemBridgeService.instance.notifyInternalWrite();
    await DatabaseService.instance.deleteMusicPlaylist(playlistId);
    EcosystemBridgeService.instance.notifyInternalWrite();
    if (_activePlaylist?.id == playlistId) {
      await _player.stop();
      _isPlaying = false;
      _tracks = [];
      _currentIndex = -1;
      _activePlaylist = null;
    }
    _playlists = await DatabaseService.instance.getAllMusicPlaylists();
    if (_playlists.isNotEmpty && _activePlaylist == null) {
      await selectPlaylist(_playlists.first, autoPlay: false);
    }
    _safeNotify();
  }

  Future<int> loadTracksFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      _tracks = [];
      _currentIndex = -1;
      _safeNotify();
      return 0;
    }

    final List<MusicTrack> loaded = [];
    const validExtensions = {'.mp3', '.wav', '.ogg', '.flac', '.m4a', '.aac'};

    try {
      await for (final entity
          in dir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (validExtensions.contains(ext)) {
            final title = p.basenameWithoutExtension(entity.path);
            loaded.add(MusicTrack(filePath: entity.path, title: title));
          }
        }
      }
    } catch (_) {}

    _tracks = loaded;
    if (_tracks.isNotEmpty) {
      _currentIndex = _isShuffle ? Random().nextInt(_tracks.length) : 0;
    } else {
      _currentIndex = -1;
    }
    _safeNotify();
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
    _safeNotify();
  }

  Future<void> togglePlayPause() async {
    if (_tracks.isEmpty) {
      if (_activePlaylist != null) {
        await loadTracksFromFolder(_activePlaylist!.folderPath);
      }
      if (_tracks.isEmpty) return;
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_currentIndex == -1 || _currentIndex >= _tracks.length) {
        _currentIndex = _isShuffle ? Random().nextInt(_tracks.length) : 0;
      }
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await playTrack(_currentIndex);
      }
    }
    _pausedByBreak = false;
    _safeNotify();
  }

  Future<void> nextTrack() async {
    if (_tracks.isEmpty) return;
    if (_tracks.length == 1) {
      await playTrack(0);
      return;
    }
    if (_isShuffle) {
      int nextIndex;
      final rng = Random();
      do {
        nextIndex = rng.nextInt(_tracks.length);
      } while (nextIndex == _currentIndex && _tracks.length > 1);
      await playTrack(nextIndex);
    } else {
      final nextIndex = (_currentIndex + 1) % _tracks.length;
      await playTrack(nextIndex);
    }
  }

  Future<void> previousTrack() async {
    if (_tracks.isEmpty) return;
    if (_tracks.length == 1) {
      await playTrack(0);
      return;
    }
    if (_isShuffle) {
      int prevIndex;
      final rng = Random();
      do {
        prevIndex = rng.nextInt(_tracks.length);
      } while (prevIndex == _currentIndex && _tracks.length > 1);
      await playTrack(prevIndex);
    } else {
      final prevIndex = (_currentIndex - 1 + _tracks.length) % _tracks.length;
      await playTrack(prevIndex);
    }
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

  void onRealmChanged(AppRealm realm) {
    if (realm == AppRealm.life) {
      if (!_playDuringBreaks && _isPlaying) {
        _player.pause();
        _pausedByBreak = true;
      }
    } else if (realm == AppRealm.work) {
      if (_pausedByBreak) {
        _player.resume();
        _pausedByBreak = false;
      }
    }
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
    _isDisposed = true;
    _completeSub?.cancel();
    _completeSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _player.dispose();
    super.dispose();
  }
}
