enum MessageAuthor { signer, partner }

enum MessageSource { typed, sign, voice }

class Conversation {
  const Conversation({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.pending = true,
  });

  final String id;
  final String ownerId;
  final String title;
  final String location;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pending;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    ownerId: json['owner_id'] as String,
    title: json['title'] as String,
    location: json['location'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    pending: json['pending'] == 1,
  );

  Map<String, dynamic> toCloudJson() => {
    'id': id,
    'owner_id': ownerId,
    'title': title,
    'location': location,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.ownerId,
    required this.author,
    required this.source,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String ownerId;
  final MessageAuthor author;
  final MessageSource source;
  final String content;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    ownerId: json['owner_id'] as String,
    author: MessageAuthor.values.byName(json['author'] as String),
    source: MessageSource.values.byName(json['source'] as String),
    content: json['content'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  );

  Map<String, dynamic> toCloudJson() => {
    'id': id,
    'conversation_id': conversationId,
    'owner_id': ownerId,
    'author': author.name,
    'source': source.name,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
