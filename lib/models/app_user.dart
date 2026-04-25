class AppUser {
  const AppUser({
    required this.id,
    required this.login,
    required this.name,
    required this.contact,
    required this.isAdmin,
    required this.cityId,
  });

  final int id;
  final String login;
  final String name;
  final String? contact;
  final bool isAdmin;
  final int? cityId;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      login: (json['login'] as String?) ?? '',
      name: (json['user_name'] as String?) ?? (json['name'] as String?) ?? '',
      contact: (json['user_contact'] as String?)?.trim().isEmpty == true
          ? null
          : json['user_contact'] as String?,
      isAdmin: (json['is_admin'] as bool?) ?? false,
      cityId: json['city_id'] as int?,
    );
  }
}
