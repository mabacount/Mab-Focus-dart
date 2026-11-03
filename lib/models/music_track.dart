class MusicPlaylist {
  final String id;
  final String name;
  final String folderPath;
  final bool isDefault;

  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.folderPath,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'folder_path': folderPath,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory MusicPlaylist.fromMap(Map<String, dynamic> map) {
    return MusicPlaylist(
      id: map['id'] as String,
      name: map['name'] as String,
      folderPath: map['folder_path'] as String,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
    );
  }

  MusicPlaylist copyWith({
    String? id,
    String? name,
    String? folderPath,
    bool? isDefault,
  }) {
    return MusicPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      folderPath: folderPath ?? this.folderPath,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class MusicTrack {
  final String filePath;
  final String title;
  final String? artist;
  final Duration? duration;

  const MusicTrack({
    required this.filePath,
    required this.title,
    this.artist,
    this.duration,
  });
}
