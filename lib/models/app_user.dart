class AppUser {
  const AppUser({
    required this.id,
    required this.login,
    required this.password,
    required this.name,
    required this.isAdmin,
  });

  final int id;
  final String login;
  final String password;
  final String name;
  final bool isAdmin;
}
