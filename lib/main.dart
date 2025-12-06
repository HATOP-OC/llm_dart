import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/info_screen.dart';
import 'services/llm_service.dart';
import 'services/model_manager.dart';
import 'services/chat_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final llmService = LlmService();
  await llmService.init();
  
  final chatStorage = ChatStorage();
  await chatStorage.init();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: llmService),
        ChangeNotifierProvider.value(value: chatStorage),
        ChangeNotifierProvider(
          create: (_) => ModelManager(llmService: llmService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF2D2D2D),
        ),
      ),
      home: const AppScaffold(initialIndex: 0),
    );
  }
}

class AppScaffold extends StatefulWidget {
  final int initialIndex;
  
  const AppScaffold({super.key, required this.initialIndex});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  late int _selectedIndex;
  bool _isInitializing = true;
  bool _showArchived = false;
  
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    await modelManager.init();
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  final List<Widget> _screens = [
    const ChatScreen(),
    const ModelsScreen(),
    const SettingsScreen(),
    const InfoScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  AppBar _buildAppBar(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context);
    final llmService = Provider.of<LlmService>(context);

    switch (_selectedIndex) {
      case 0:
        return AppBar(
          title: Row(
            children: [
              const Text('Chat'),
              const SizedBox(width: 12),
              if (modelManager.activeModel != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green. withValues(alpha:0.2),
                    borderRadius: BorderRadius. circular(12),
                    border: Border.all(color: Colors. green, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.memory, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        modelManager.activeModel! .name. length > 8
                            ? '${modelManager.activeModel!.name. substring(0, 8)}...'
                            : modelManager.activeModel!. name,
                        style: const TextStyle(fontSize: 10, color: Colors. green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _buildContextIndicator(llmService),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors. orange, width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, size: 14, color: Colors. orange),
                      SizedBox(width: 4),
                      Text(
                        'No model',
                        style: TextStyle(fontSize: 10, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            if (modelManager.activeModel != null)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Clear context',
                onPressed: () {
                  llmService.clearContext();
                  ScaffoldMessenger. of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Context cleared'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
          ],
        );
      case 1:
        return AppBar(title: const Text('Models'));
      case 2:
        return AppBar(title: const Text('Settings'));
      case 3:
        return AppBar(title: const Text('Info'));
      default:
        return AppBar(title: const Text('LLM Chat'));
    }
  }

  Widget _buildContextIndicator(LlmService llmService) {
    final usage = llmService. contextUsage;
    final usedTokens = llmService.usedTokens;
    final totalTokens = llmService.contextLength;
    
    Color color;
    if (usage < 0.5) {
      color = Colors.green;
    } else if (usage < 0.8) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }
    
    return Tooltip(
      message: '$usedTokens / $totalTokens tokens',
      child: Container(
        width: 36,
        height: 14,
        decoration: BoxDecoration(
          borderRadius: BorderRadius. circular(7),
          border: Border.all(color: color. withValues (alpha: 0.5), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: usage. clamp(0.0, 1.0),
            backgroundColor: Colors.grey. shade800,
            valueColor: AlwaysStoppedAnimation<Color>(color. withValues (alpha: 0.7)),
          ),
        ),
      ),
    );
  }

  Widget _buildChatDrawer(BuildContext context) {
    final chatStorage = Provider. of<ChatStorage>(context);
    
    final displayChats = _showArchived 
        ? chatStorage.archivedChats 
        : chatStorage.chats;
    
    return Drawer(
      child: Container(
        color: const Color(0xFF1A1A1A),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showArchived ? 'Archived' : 'Chats',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (! _showArchived)
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
                          tooltip: 'New Chat',
                          onPressed: () {
                            chatStorage. createChat('New Chat');
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Перемикач Active / Archived
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius. circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showArchived = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: ! _showArchived ?  Colors.blue : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat,
                                    size: 16,
                                    color: !_showArchived ? Colors. white : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Active',
                                    style: TextStyle(
                                      color: !_showArchived ? Colors.white : Colors.grey,
                                      fontWeight: FontWeight. bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showArchived = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _showArchived ? Colors.blue : Colors. transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.archive,
                                    size: 16,
                                    color: _showArchived ? Colors.white : Colors. grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Archived',
                                    style: TextStyle(
                                      color: _showArchived ?  Colors.white : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Список чатів
            Expanded(
              child: displayChats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _showArchived ? Icons.archive_outlined : Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey. shade600,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _showArchived 
                                ? 'No archived chats' 
                                : 'No chats yet',
                            style: TextStyle(color: Colors.grey. shade500),
                          ),
                          if (! _showArchived) ...[
                            const SizedBox(height: 16),
                            ElevatedButton. icon(
                              onPressed: () {
                                chatStorage. createChat('New Chat');
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('New Chat'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: displayChats.length,
                      itemBuilder: (context, index) {
                        final chat = displayChats[index];
                        final isSelected = chat.id == chatStorage.currentChat?. id;
                        final lastMessage = chat.messages. isNotEmpty 
                            ? chat.messages.last.content 
                            : 'No messages';
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Colors.blue. withValues(alpha:0.2) 
                                : Colors.grey.shade800. withValues(alpha:0.5),
                            borderRadius: BorderRadius. circular(12),
                            border: isSelected 
                                ? Border. all(color: Colors.blue, width: 1)
                                : null,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: isSelected 
                                  ?  Colors.blue 
                                  : Colors.grey.shade700,
                              radius: 20,
                              child: Icon(
                                _showArchived ?  Icons.archive : Icons.chat,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow. ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ?  FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              lastMessage. length > 35 
                                  ?  '${lastMessage.substring(0, 35)}...' 
                                  : lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow. ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                              color: Colors.grey. shade800,
                              onSelected: (value) async {
                                switch (value) {
                                  case 'archive':
                                    await chatStorage.archiveChat(chat. id!, ! _showArchived);
                                    break;
                                  case 'delete':
                                    await chatStorage.deleteChat(chat.id! );
                                    break;
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
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
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
                                      Icon(Icons.delete, color: Colors. red, size: 20),
                                      SizedBox(width: 12),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading.. .',
                style: TextStyle(color: Colors.grey. shade400),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: _selectedIndex == 0 ? _buildChatDrawer(context) : null,
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.model_training_outlined),
            selectedIcon: Icon(Icons.model_training),
            label: 'Models',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons. info),
            label: 'Info',
          ),
        ],
      ),
    );
  }
}