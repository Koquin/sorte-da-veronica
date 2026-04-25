class AppCity {
  const AppCity({required this.id, required this.name});

  final int id;
  final String name;

  factory AppCity.fromJson(Map<String, dynamic> json) {
    return AppCity(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
    );
  }
}
