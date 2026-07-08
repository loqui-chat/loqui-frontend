class User {
  User({
    required this.id,
    required this.username,
    required this.discriminator,
    required this.handle,
    this.email,
  });

  final String id;
  final String username;
  final String discriminator;
  final String handle;
  final String? email;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String,
    username: j['username'] as String,
    discriminator: j['discriminator'] as String,
    handle: j['handle'] as String,
    email: j['email'] as String?,
  );
}
