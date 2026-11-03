class PhaseTag {
  final String id;
  final String name;
  final String category; // 'phase' | 'status'
  final bool archived;

  const PhaseTag({
    required this.id,
    required this.name,
    this.category = 'phase',
    this.archived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'archived': archived ? 1 : 0,
    };
  }

  factory PhaseTag.fromMap(Map<String, dynamic> map) {
    return PhaseTag(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String? ?? 'phase',
      archived: (map['archived'] as int? ?? 0) == 1,
    );
  }

  PhaseTag copyWith({
    String? id,
    String? name,
    String? category,
    bool? archived,
  }) {
    return PhaseTag(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      archived: archived ?? this.archived,
    );
  }
}
