import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/chat_storage.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/prompt_manager.dart';
import '../models/chat_model.dart';
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
  StreamSubscription<String>? _streamSubscription;
  
  // Attachment state
  String? _pendingAttachmentPath;
  AttachmentType _pendingAttachmentType = AttachmentType.none;
  
  DateTime _lastUIUpdate = DateTime.now();
  static const _uiUpdateInterval = Duration(milliseconds: 50);
  
  // Прапорець для відстеження чи віджет ще живий
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _cancelStreamSubscription();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _cancelStreamSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _currentStreamId = null;
  }

  void _clearPendingAttachment() {
    _safeSetState(() {
      _pendingAttachmentPath = null;
      _pendingAttachmentType = AttachmentType.none;
    });
  }

  Future<String?> _copyFileToAppDir(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${appDir.path}/attachments');
      if (!await attachDir.exists()) {
        await attachDir.create(recursive: true);
      }
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
      final destPath = '${attachDir.path}/$fileName';
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('Error copying file: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        final savedPath = await _copyFileToAppDir(image.path);
        if (savedPath != null) {
          _safeSetState(() {
            _pendingAttachmentPath = savedPath;
            _pendingAttachmentType = AttachmentType.image;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf', 'json', 'csv', 'md', 'log',
                            'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        withData: false,
        withReadStream: false,
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final ext = p.extension(filePath).toLowerCase();
        final isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext);
        
        final savedPath = await _copyFileToAppDir(filePath);
        if (savedPath != null) {
          _safeSetState(() {
            _pendingAttachmentPath = savedPath;
            _pendingAttachmentType = isImage ? AttachmentType.image : AttachmentType.file;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  void _scrollToBottom() {
    if (_isDisposed) return;
    
    WidgetsBinding. instance.addPostFrameCallback((_) {
      if (!_isDisposed && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  /// Безпечний setState що перевіряє mounted і _isDisposed
  void _safeSetState(VoidCallback fn) {
    if (! _isDisposed && mounted) {
      setState(fn);
    }
  }

  void _stopGeneration() {
    if (_currentStreamId != null) {
      try {
        final llmService = Provider.of<LlmService>(context, listen: false);
        llmService. stopGeneration(_currentStreamId!);
      } catch (e) {
        debugPrint('Error stopping generation: $e');
      }
    }
    
    _cancelStreamSubscription();
    
    // Використовуємо безпечний setState
    _safeSetState(() {
      _isGenerating = false;
    });
  }

  Future<void> _sendMessage() async {
    if (_isGenerating || (_textController.text.trim().isEmpty && _pendingAttachmentPath == null)) return;

    final messageContent = _textController. text.trim();
    _textController.clear();

    final chatStorage = Provider.of<ChatStorage>(context, listen: false);
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    final llmService = Provider. of<LlmService>(context, listen: false);

    final currentChat = chatStorage.currentChat;
    if (currentChat == null) return;

    _safeSetState(() {
      _isGenerating = true;
      _currentGeneratedText = "";
    });

    await chatStorage.addMessage(
      currentChat.id!,
      messageContent,
      true,
      attachmentPath: _pendingAttachmentPath,
      attachmentType: _pendingAttachmentType.index,
    );
    
    // Clear pending attachment after sending
    _safeSetState(() {
      _pendingAttachmentPath = null;
      _pendingAttachmentType = AttachmentType.none;
    });
    
    _scrollToBottom();

    if (modelManager.activeModel == null) {
      await chatStorage.addMessage(
        currentChat.id!,
        "Error: Please download and activate a model in the 'Models' section.",
        false,
      );
      _safeSetState(() {
        _isGenerating = false;
      });
      _scrollToBottom();
      return;
    }
    
    await chatStorage.addMessage(currentChat.id!, "", false);
    _scrollToBottom();

    try {
      _currentStreamId = DateTime.now().millisecondsSinceEpoch.toString();
      final chatId = currentChat.id!;

      final allMessages = chatStorage.getChatById(chatId)!.messages;
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

      // Зберігаємо підписку щоб мати змогу її скасувати
      _streamSubscription = llmService
          .generateResponseStream(fullPrompt)
          .listen(
            (generatedPiece) async {
              // Перевіряємо чи віджет ще живий
              if (_isDisposed) return;
              
              final now = DateTime.now();
              if (now.difference(_lastUIUpdate) < _uiUpdateInterval) {
                _currentGeneratedText = generatedPiece;
                return;
              }
              _lastUIUpdate = now;
              
              _safeSetState(() {
                _currentGeneratedText = generatedPiece;
              });

              try {
                final chat = chatStorage.getChatById(chatId);
                if (chat != null && chat.messages.isNotEmpty) {
                  final lastMessage = chat.messages.last;
                  await chatStorage.updateMessage(
                    lastMessage.id!,
                    generatedPiece,
                  );
                }
              } catch (e) {
                debugPrint('Error updating message: $e');
              }

              _scrollToBottom();
            },
            onDone: () {
              if (_isDisposed) return;
              
              _safeSetState(() {
                _isGenerating = false;
                _currentStreamId = null;
              });
              
              try {
                final chat = chatStorage.getChatById(chatId);
                if (chat != null && chat.messages.isNotEmpty && _currentGeneratedText.isNotEmpty) {
                  final lastMessage = chat.messages.last;
                  chatStorage.updateMessage(lastMessage.id!, _currentGeneratedText);
                }
              } catch (e) {
                debugPrint('Error in onDone: $e');
              }
              
              _streamSubscription = null;
            },
            onError: (error) async {
              if (_isDisposed) return;
              
              try {
                final chat = chatStorage.getChatById(chatId);
                if (chat != null && chat.messages.isNotEmpty) {
                  final lastMessage = chat.messages.last;
                  await chatStorage.updateMessage(
                    lastMessage.id!,
                    "Error generating response: $error",
                  );
                }
              } catch (e) {
                debugPrint('Error in onError handler: $e');
              }
              
              _safeSetState(() {
                _isGenerating = false;
                _currentStreamId = null;
              });
              
              _scrollToBottom();
              _streamSubscription = null;
            },
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('Exception in _sendMessage: $e');
      
      try {
        final chat = chatStorage.getChatById(currentChat.id!);
        if (chat != null && chat. messages.isNotEmpty) {
          final lastMessage = chat. messages.last;
          await chatStorage. updateMessage(
            lastMessage.id! ,
            "Error: ${e.toString()}",
          );
        }
      } catch (updateError) {
        debugPrint('Error updating message on exception: $updateError');
      }
      
      _safeSetState(() {
        _isGenerating = false;
        _currentStreamId = null;
      });
      
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Messages area
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
                itemCount: chat.messages.length,
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
                            bottomRight: Radius.circular(18),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Attachment preview
                if (_pendingAttachmentPath != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (_pendingAttachmentType == AttachmentType.image)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_pendingAttachmentPath!),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                                size: 48,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.insert_drive_file, color: Colors.white),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.basename(_pendingAttachmentPath!),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                          onPressed: _clearPendingAttachment,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    // Attachment buttons
                    IconButton(
                      icon: Icon(Icons.image, color: Colors.blue.shade300, size: 22),
                      onPressed: _isGenerating ? null : _pickImage,
                      tooltip: 'Attach image',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.attach_file, color: Colors.blue.shade300, size: 22),
                      onPressed: _isGenerating ? null : _pickFile,
                      tooltip: 'Attach file',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
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
                          color: Colors. white,
                        ),
                        onPressed: _isGenerating ? _stopGeneration : _sendMessage,
                      ),
                    ),
                  ],
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