class AppUser {
  AppUser({required this.id, required this.phone, required this.name, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        phone: json['phone'] as String,
        name: (json['name'] as String?) ?? '',
        role: json['role'] as String,
      );

  final int id;
  final String phone;
  final String name;
  final String role; // customer | merchant | admin

  String get displayName => name.isEmpty ? phone : name;
}
