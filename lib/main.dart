import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'screens/models_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/info_screen.dart';
import 'services/model_manager.dart';
import 'services/chat_storage.dart';
import 'services/llm_service.dart';
import 'widgets/navigation_drawer.dart' as nav;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final chatStorage = ChatStorage();
  await chatStorage.init();
  
  final llmService = LlmService();
  await llmService. init();

  final modelManager = ModelManager(llmService: llmService);
  // НЕ чекаємо init() тут — він буде виконуватись асинхронно
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider. value(value: chatStorage),
        ChangeNotifierProvider. value(value: modelManager),
        Provider.value(value: llmService),
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
      title: 'Local LLM Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius. circular(12),
          ),
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
    final chatStorage = Provider.of<ChatStorage>(context);
    final modelManager = Provider.of<ModelManager>(context);

    switch (_selectedIndex) {
      case 0:
        return AppBar(
          title: Row(
            children: [
              Text(chatStorage.currentChat?. title ?? 'Chat'),
              if (modelManager.isLoadingModel) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          actions: [
            // Показуємо статус моделі
            if (modelManager.activeModel != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: Icon(
                    modelManager.isLoadingModel 
                        ? Icons.hourglass_empty 
                        : Icons.check_circle,
                    size: 16,
                    color: modelManager. isLoadingModel 
                        ? Colors.orange 
                        : Colors.green,
                  ),
                  label: Text(
                    modelManager.activeModel!. name. length > 10
                        ? '${modelManager.activeModel!.name. substring(0, 10)}...'
                        : modelManager.activeModel!. name,
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: Colors.grey. shade800,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                if (chatStorage.currentChat != null) ...[
                  PopupMenuItem(
                    onTap: () {
                      chatStorage.archiveChat(chatStorage.currentChat!.id!, true);
                    },
                    child: const Text('Archive Chat'),
                  ),
                  PopupMenuItem(
                    onTap: () {
                      chatStorage.deleteChat(chatStorage. currentChat!.id!);
                    },
                    child: const Text('Delete Chat'),
                  ),
                ],
                PopupMenuItem(
                  onTap: () {
                    chatStorage.createChat('New Chat');
                  },
                  child: const Text('New Chat'),
                ),
              ],
            ),
          ],
        );
      case 1:
        return AppBar(title: const Text('Models'));
      case 2:
        return AppBar(title: const Text('Settings'));
      case 3:
        return AppBar(title: const Text('About'));
      default:
        return AppBar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading... '),
                  SizedBox(height: 8),
                  Text(
                    'Initializing model',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : _screens[_selectedIndex],
      drawer: nav.NavigationDrawer(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }
}