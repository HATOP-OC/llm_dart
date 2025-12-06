import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../services/chat_storage.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/prompt_manager.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  String?  _currentStreamId;
  String _currentGeneratedText = "";
  
  DateTime _lastUIUpdate = DateTime.now();
  static const _uiUpdateInterval = Duration(milliseconds: 50);

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
    if (mounted) {
      setState(() {
        _isGenerating = false;
      });
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

      final allMessages = chatStorage.getChatById(currentChat.id!)!.messages;
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
              final now = DateTime.now();
              if (now.difference(_lastUIUpdate) < _uiUpdateInterval) {
                _currentGeneratedText = generatedPiece;
                return;
              }
              _lastUIUpdate = now;
              
              if (mounted) {
                setState(() {
                  _currentGeneratedText = generatedPiece;
                });
              }

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
              if (mounted) {
                setState(() {
                  _isGenerating = false;
                  _currentStreamId = null;
                });
              }
              
              final chat = chatStorage.getChatById(currentChat.id!);
              if (chat != null && chat.messages.isNotEmpty && _currentGeneratedText.isNotEmpty) {
                final lastMessage = chat.messages.last;
                chatStorage.updateMessage(lastMessage.id!, _currentGeneratedText);
              }
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
              if (mounted) {
                setState(() {
                  _isGenerating = false;
                  _currentStreamId = null;
                });
              }
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
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStreamId = null;
        });
      }
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Messages area — БЕЗ горизонтальної панелі чатів
        Expanded(
          child: Consumer<ChatStorage>(
            builder: (context, chatStorage, child) {
              final currentChat = chatStorage.currentChat;

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
                          maxWidth: MediaQuery.of(context).size.width * 0.80,
                        ),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: Color(0xFF2D2D2D),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius. circular(18),
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius. circular(18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _currentGeneratedText.isEmpty
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
                                color: Colors.grey.shade400,
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
                      hintStyle: TextStyle(color: Colors.grey.shade500),
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
                          : [Colors.blue.shade500, Colors.blue.shade700],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isGenerating ?  Icons.stop : Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: _isGenerating ?  _stopGeneration : _sendMessage,
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
    return '${time.hour.toString().padLeft(2, '0')}:${time. minute.toString().padLeft(2, '0')}';
  }
}