import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/chat_model.dart';

class ChatStorage extends ChangeNotifier {
  late Database _database;
  List<Chat> _chats = [];
  Chat? _currentChat;
  
  List<Chat> get chats => _chats.where((chat) => !chat.isArchived).toList();
  List<Chat> get archivedChats => _chats.where((chat) => chat.isArchived).toList();
  Chat? get currentChat => _currentChat;

  void setCurrentChat(Chat? chat) {
    if (_currentChat != chat) {
      _currentChat = chat;
      notifyListeners();
    }
  }

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      join(dbPath, 'chat_database.db'),
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE chats(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, created_at TEXT, updated_at TEXT, is_archived INTEGER)',
        );
        await db.execute(
          'CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id INTEGER, content TEXT, is_user INTEGER, timestamp TEXT, attachment_path TEXT, attachment_type INTEGER DEFAULT 0, FOREIGN KEY (chat_id) REFERENCES chats (id) ON DELETE CASCADE)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN attachment_path TEXT',
          );
          await db.execute(
            'ALTER TABLE messages ADD COLUMN attachment_type INTEGER DEFAULT 0',
          );
        }
      },
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    
    await _loadChats();
  }

  Future<void> _loadChats() async {
    final chatMaps = await _database.query('chats', orderBy: 'updated_at DESC');
    
    _chats = [];
    for (var chatMap in chatMaps) {
      final chat = Chat.fromMap(chatMap);
      
      final messageMaps = await _database.query(
        'messages',
        where: 'chat_id = ?',
        whereArgs: [chat.id],
        orderBy: 'timestamp ASC',
      );
      
      final messages = messageMaps.map((m) => Message.fromMap(m)).toList();
      _chats.add(chat.copyWith(messages: messages));
    }
    
    if (chats.isNotEmpty) {
      _currentChat = chats.first;
    } else {
      _currentChat = null;
    }

    notifyListeners();
  }

  Future<Chat> createChat(String title) async {
    final now = DateTime.now();
    
    final id = await _database.insert(
      'chats',
      {
        'title': title,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'is_archived': 0,
      },
    );
    
    final chat = Chat(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      messages: [],
    );
    
    _chats.add(chat);
    setCurrentChat(chat); // Set the new chat as current
    
    return chat;
  }

  Future<void> addMessage(int chatId, String content, bool isUser, {
    String? attachmentPath,
    int attachmentType = 0,
  }) async {
    final now = DateTime.now();
    
    final messageId = await _database.insert(
      'messages',
      {
        'chat_id': chatId,
        'content': content,
        'is_user': isUser ? 1 : 0,
        'timestamp': now.toIso8601String(),
        'attachment_path': attachmentPath,
        'attachment_type': attachmentType,
      },
    );
    
    await _database.update(
      'chats',
      {'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      final updatedMessages = List<Message>.from(chat.messages)
        ..add(Message(
          id: messageId,
          chatId: chatId,
          content: content,
          isUser: isUser,
          timestamp: now,
          attachmentPath: attachmentPath,
          attachmentType: AttachmentType.values[attachmentType],
        ));
      
      _chats[chatIndex] = chat.copyWith(
        messages: updatedMessages,
        updatedAt: now,
      );
      
      notifyListeners();
    }
  }

  Future<void> updateMessage(int messageId, String newContent) async {
    await _database.update(
      'messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    
    // Update the message in memory
    for (int i = 0; i < _chats.length; i++) {
      final chat = _chats[i];
      for (int j = 0; j < chat.messages.length; j++) {
        final message = chat.messages[j];
        if (message.id == messageId) {
          final updatedMessage = Message(
            id: message.id,
            chatId: message.chatId,
            content: newContent,
            isUser: message.isUser,
            timestamp: message.timestamp,
          );
          
          final updatedMessages = List<Message>.from(chat.messages);
          updatedMessages[j] = updatedMessage;
          
          _chats[i] = chat.copyWith(messages: updatedMessages);
          notifyListeners();
          return;
        }
      }
    }
  }

  Future<void> deleteChat(int chatId) async {
    await _database.delete(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    
    _chats.removeWhere((c) => c.id == chatId);
    if (_currentChat?.id == chatId) {
      setCurrentChat(chats.isNotEmpty ? chats.first : null);
    }
    notifyListeners();
  }

  Future<void> archiveChat(int chatId, bool archive) async {
    await _database.update(
      'chats',
      {'is_archived': archive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(isArchived: archive);
      if (_currentChat?.id == chatId) {
        setCurrentChat(chats.isNotEmpty ? chats.first : null);
      }
      notifyListeners();
    }
  }

  Future<void> clearAllChats() async {
    await _database.delete('chats');
    await _database.delete('messages');
    _chats.clear();
    notifyListeners();
  }
  
  Chat? getChatById(int chatId) {
    try {
      return _chats.firstWhere((chat) => chat.id == chatId);
    } catch (_) {
      return null;
    }
  }
}