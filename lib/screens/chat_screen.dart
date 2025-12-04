import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../services/chat_storage.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/prompt_manager.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super. key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  String?  _currentStreamId;
  String _currentGeneratedText = "";
  bool _showArchived = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _stopGeneration();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding. instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position. maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves. easeOut,
        );
      }
    });
  }

  void _stopGeneration() {
    if (_currentStreamId != null) {
      final llmService = Provider.of<LlmService>(context, listen: false);
      llmService. stopGeneration(_currentStreamId!);
      _currentStreamId = null;
    }
  }

  Future<void> _sendMessage() async {
    if (_isGenerating || _textController.text.trim().isEmpty) return;

    final messageContent = _textController. text.trim();
    _textController.clear();

    final chatStorage = Provider.of<ChatStorage>(context, listen: false);
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    final llmService = Provider. of<LlmService>(context, listen: false);

    final currentChat = chatStorage.currentChat;
    if (currentChat == null) return;

    setState(() {
      _isGenerating = true;
      _currentGeneratedText = "";
    });

    await chatStorage.addMessage(currentChat.id!, messageContent, true);
    _scrollToBottom();

    if (modelManager.activeModel == null) {
      await chatStorage.addMessage(
        currentChat.id!,
        "Error: Please download and activate a model in the 'Models' section.",
        false,
      );
      setState(() {
        _isGenerating = false;
      });
      _scrollToBottom();
      return;
    }
    
    await chatStorage.addMessage(currentChat.id!, "", false);
    _scrollToBottom();

    try {
      _currentStreamId = DateTime.now().millisecondsSinceEpoch.toString();

      final allMessages = chatStorage.getChatById(currentChat.id!)!. messages;
      final historyMessages = allMessages.length > 2 
          ? allMessages. sublist(0, allMessages.length - 2) 
          : [];
      
      final history = historyMessages
          .map((m) => (m.isUser ? 'User: ' : 'Assistant: ') + m.content)
          .join('\n');
      
      final modelName = modelManager.activeModel?. name ?? 'llama';
      
      final fullPrompt = PromptManager.formatPromptWithHistory(
        messageContent, 
        history, 
        modelName,
      );

      llmService
          .generateResponseStream(fullPrompt)
          .listen(
            (generatedPiece) async {
              setState(() {
                _currentGeneratedText = generatedPiece;
              });

              final chat = chatStorage.getChatById(currentChat.id! );
              if (chat != null && chat.messages.isNotEmpty) {
                final lastMessage = chat.messages.last;
                await chatStorage.updateMessage(
                  lastMessage.id!,
                  generatedPiece,
                );
              }

              _scrollToBottom();
            },
            onDone: () {
              setState(() {
                _isGenerating = false;
                _currentStreamId = null;
              });
            },
            onError: (error) async {
              final chat = chatStorage. getChatById(currentChat.id!);
              if (chat != null && chat. messages.isNotEmpty) {
                final lastMessage = chat. messages.last;
                await chatStorage. updateMessage(
                  lastMessage.id!,
                  "Error generating response: $error",
                );
              }
              setState(() {
                _isGenerating = false;
                _currentStreamId = null;
              });
              _scrollToBottom();
            },
          );
    } catch (e) {
      final chat = chatStorage. getChatById(currentChat.id!);
      if (chat != null && chat. messages.isNotEmpty) {
        final lastMessage = chat. messages.last;
        await chatStorage. updateMessage(
          lastMessage.id! ,
          "Error: ${e.toString()}",
        );
      }
      setState(() {
        _isGenerating = false;
        _currentStreamId = null;
      });
      _scrollToBottom();
    }
  }

  void _showChatHistory(BuildContext context) {
    final chatStorage = Provider.of<ChatStorage>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey. shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final displayChats = _showArchived 
                ? chatStorage.archivedChats 
                : chatStorage.chats;
            
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius. circular(2),
                    ),
                  ),
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showArchived ? 'Archived Chats' : 'Chat History',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight. bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton. icon(
                            onPressed: () {
                              setModalState(() {
                                _showArchived = ! _showArchived;
                              });
                            },
                            icon: Icon(
                              _showArchived ? Icons.chat : Icons.archive,
                              color: Colors.blue,
                              size: 20,
                            ),
                            label: Text(
                              _showArchived ?  'Active' : 'Archived',
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.blue),
                            onPressed: () {
                              chatStorage.createChat('New Chat');
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Chat list
                  Expanded(
                    child: displayChats.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _showArchived ? Icons.archive_outlined : Icons.chat_bubble_outline,
                                  size: 48,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _showArchived 
                                      ?  'No archived chats' 
                                      : 'No chats yet.  Create one! ',
                                  style: TextStyle(color: Colors.grey. shade500),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: displayChats. length,
                            itemBuilder: (context, index) {
                              final chat = displayChats[index];
                              final isSelected = chat.id == chatStorage.currentChat?. id;
                              final lastMessage = chat.messages.isNotEmpty 
                                  ?  chat.messages.last. content 
                                  : 'No messages';
                              
                              return Card(
                                color: isSelected 
                                    ?  Colors.blue.shade900 
                                    : Colors.grey. shade800,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected 
                                        ? Colors. blue 
                                        : Colors.grey.shade700,
                                    child: Icon(
                                      _showArchived ?  Icons.archive : Icons.chat,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    chat.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight. w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    lastMessage. length > 40 
                                        ? '${lastMessage.substring(0, 40)}...' 
                                        : lastMessage,
                                    style: TextStyle(color: Colors.grey.shade400),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                                    color: Colors.grey. shade800,
                                    onSelected: (value) {
                                      if (value == 'archive') {
                                        chatStorage.archiveChat(chat.id!, ! _showArchived);
                                        setModalState(() {});
                                      } else if (value == 'delete') {
                                        chatStorage.deleteChat(chat.id!);
                                        Navigator.pop(context);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'archive',
                                        child: Row(
                                          children: [
                                            Icon(
                                              _showArchived ?  Icons.unarchive : Icons. archive,
                                              color: Colors. white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _showArchived ?  'Unarchive' : 'Archive',
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    if (! _showArchived) {
                                      chatStorage.setCurrentChat(chat);
                                    }
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with chat tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors. grey.shade900,
            border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
          ),
          child: Consumer<ChatStorage>(
            builder: (context, chatStorage, child) {
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors. white),
                    onPressed: () => _showChatHistory(context),
                    tooltip: 'Chat History',
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis. horizontal,
                        itemCount: chatStorage.chats.length,
                        itemBuilder: (context, index) {
                          final chat = chatStorage.chats[index];
                          final isSelected = chat. id == chatStorage. currentChat?.id;

                          return GestureDetector(
                            onTap: () {
                              chatStorage.setCurrentChat(chat);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue. shade700
                                    : Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(20),
                                border: isSelected 
                                    ?  Border.all(color: Colors.blue.shade400, width: 1)
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                chat.title. length > 15 
                                    ? '${chat.title. substring(0, 15)}...'
                                    : chat.title,
                                style: TextStyle(
                                  color: isSelected ?  Colors.white : Colors.grey.shade300,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                    onPressed: () {
                      chatStorage.createChat('New Chat');
                    },
                    tooltip: 'New Chat',
                  ),
                ],
              );
            },
          ),
        ),

        // Messages area
        Expanded(
          child: Consumer<ChatStorage>(
            builder: (context, chatStorage, child) {
              final currentChat = chatStorage. currentChat;

              if (currentChat == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text(
                        'Create a new chat to start',
                        style: TextStyle(color: Colors.grey. shade500, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton. icon(
                        onPressed: () {
                          chatStorage.createChat('New Chat');
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New Chat'),
                      ),
                    ],
                  ),
                );
              }

              final chat = chatStorage.getChatById(currentChat.id!);
              if (chat == null) {
                return const Center(child: Text('Chat not found'));
              }

              if (chat.messages. isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.psychology, size: 80, color: Colors. blue.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'How can I help you today?',
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Type a message below to start chatting',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 16, bottom: 80),
                itemCount: chat.messages. length,
                itemBuilder: (context, index) {
                  final message = chat.messages[index];

                  if (index == chat.messages.length - 1 &&
                      ! message.isUser &&
                      _isGenerating) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size. width * 0.80,
                        ),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius. circular(18),
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius. circular(18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _currentGeneratedText. isEmpty
                                ? AnimatedTextKit(
                                    animatedTexts: [
                                      WavyAnimatedText(
                                        'Thinking...',
                                        textStyle: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                    isRepeatingAnimation: true,
                                    totalRepeatCount: 100,
                                  )
                                : Text(
                                    _currentGeneratedText,
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                  ),
                            const SizedBox(height: 6),
                            Text(
                              _formatTime(DateTime.now()),
                              style: TextStyle(
                                color: Colors. grey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ChatBubble(message: message);
                },
              );
            },
          ),
        ),

        // Input area
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            border: Border(top: BorderSide(color: Colors.grey.shade800)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors. grey.shade500),
                      filled: true,
                      fillColor: Colors.grey.shade800,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide. none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _isGenerating ?  null : _sendMessage(),
                    maxLines: null,
                    enabled: ! _isGenerating,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isGenerating 
                          ? [Colors.red.shade600, Colors.red.shade800]
                          : [Colors.blue. shade500, Colors.blue. shade700],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isGenerating ? Icons.stop : Icons. send,
                      color: Colors.white,
                    ),
                    onPressed: _isGenerating ? _stopGeneration : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString(). padLeft(2, '0')}:${time.minute. toString().padLeft(2, '0')}';
  }
}