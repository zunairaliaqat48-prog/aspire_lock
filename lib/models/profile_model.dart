/// The user's local, on-device profile. There's no login/account
/// system in this app — this is just a display name + optional photo,
/// stored in SQLite (single row, id always 1) and editable from Settings.
class UserProfile {
  final String? name;
  final String? photoPath;
  final bool hasOnboarded;

  const UserProfile({this.name, this.photoPath, this.hasOnboarded = false});

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'name': name,
      'photoPath': photoPath,
      'hasOnboarded': hasOnboarded ? 1 : 0,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      name: map['name'] as String?,
      photoPath: map['photoPath'] as String?,
      hasOnboarded: (map['hasOnboarded'] as int?) == 1,
    );
  }

  UserProfile copyWith({String? name, String? photoPath, bool? hasOnboarded}) {
    return UserProfile(
      name: name ?? this.name,
      photoPath: photoPath ?? this.photoPath,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
    );
  }
}
