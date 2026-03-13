class Chat {
  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message> messages;
  final bool isArchived;

  Chat({
    this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.isArchived = false,
  });

  Chat copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
    bool? isArchived,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_archived': isArchived ? 1 : 0,
    };
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'],
      title: map['title'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      messages: [],
      isArchived: map['is_archived'] == 1,
    );
  }
}

enum AttachmentType {
  none,
  image,
  file,
}

class Message {
  final int? id;
  final int chatId;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? attachmentPath;
  final AttachmentType attachmentType;

  Message({
    this.id,
    required this.chatId,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.attachmentPath,
    this.attachmentType = AttachmentType.none,
  });

  bool get hasAttachment =>
      attachmentType != AttachmentType.none && attachmentPath != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'content': content,
      'is_user': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'attachment_path': attachmentPath,
      'attachment_type': attachmentType.index,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      chatId: map['chat_id'],
      content: map['content'],
      isUser: map['is_user'] == 1,
      timestamp: DateTime.parse(map['timestamp']),
      attachmentPath: map['attachment_path'],
      attachmentType: map['attachment_type'] != null
          ? AttachmentType.values[map['attachment_type']]
          : AttachmentType.none,
    );
  }
}