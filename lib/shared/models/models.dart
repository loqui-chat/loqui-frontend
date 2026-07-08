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

class Author {
  Author({
    required this.id,
    required this.username,
    required this.discriminator,
    required this.handle,
  });

  final String id;
  final String username;
  final String discriminator;
  final String handle;

  factory Author.fromJson(Map<String, dynamic> j) => Author(
    id: j['id'] as String,
    username: j['username'] as String,
    discriminator: j['discriminator'] as String,
    handle: j['handle'] as String,
  );
}

class Channel {
  Channel({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
    id: j['id'] as String,
    name: j['name'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

class Message {
  Message({
    required this.id,
    required this.channelId,
    required this.content,
    required this.author,
    required this.createdAt,
    this.editedAt,
  });

  final String id;
  final String channelId;
  final String content;
  final Author author;
  final DateTime createdAt;
  final DateTime? editedAt;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'] as String,
    channelId: j['channel_id'] as String,
    content: j['content'] as String,
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    createdAt: DateTime.parse(j['created_at'] as String),
    editedAt: j['edited_at'] == null
        ? null
        : DateTime.parse(j['edited_at'] as String),
  );
}
