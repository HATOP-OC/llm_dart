import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_model.dart';
import '../services/llm_service.dart';
import '../services/chat_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _contextLength = 2048;
  bool _saveChatHistory = true;
  bool _thermalProtection = true;
  QuantizationType _defaultQuantization = QuantizationType.bit4;

  late SharedPreferences _prefs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    setState(() {
      _contextLength = _prefs.getInt('context_length') ?? 2048;
      _saveChatHistory = _prefs.getBool('save_chat_history') ?? true;
      _thermalProtection = _prefs.getBool('thermal_protection') ?? true;
      _defaultQuantization = _prefs.getInt('default_quantization') == 8
          ? QuantizationType.bit8
          : QuantizationType.bit4;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await _prefs.setInt('context_length', _contextLength);
    await _prefs.setBool('save_chat_history', _saveChatHistory);
    await _prefs.setBool('thermal_protection', _thermalProtection);
    await _prefs.setInt(
      'default_quantization',
      _defaultQuantization == QuantizationType.bit8 ? 8 : 4,
    );

    // Update the LLM service with the new settings
    if (mounted) {
      final llmService = Provider.of<LlmService>(context, listen: false);
      llmService.setContextLength(_contextLength);
      llmService.setThermalProtection(_thermalProtection);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all chats?'),
        content: const Text(
          'This action is irreversible. All chats will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (mounted) {
                final chatStorage = Provider.of<ChatStorage>(
                  context,
                  listen: false,
                );
                chatStorage.clearAllChats();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All chats deleted')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Context',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Context Length: $_contextLength tokens',
                  style: TextStyle(color: Colors.grey[300]),
                ),
                Slider(
                  value: _contextLength.toDouble(),
                  min: 512,
                  max: 4096,
                  divisions: 7,
                  label: _contextLength.toString(),
                  onChanged: (value) {
                    setState(() {
                      _contextLength = value.toInt();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'A larger context allows the model to "remember" more text, but uses more memory and may run slower.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Model Quantization',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                RadioGroup<QuantizationType>(
                  groupValue: _defaultQuantization,
                  onChanged: (value) {
                    setState(() {
                      _defaultQuantization = value!;
                    });
                  },
                  child: Column(
                    children: [
                      RadioListTile<QuantizationType>(
                        title: const Text('4-bit (faster, less precise)'),
                        value: QuantizationType.bit4,
                      ),
                      RadioListTile<QuantizationType>(
                        title: const Text('8-bit (more precise, slower)'),
                        value: QuantizationType.bit8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This is the default setting for new models. Lower bitness (4-bit) means less memory usage, but may reduce the quality of responses.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thermal Protection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enable thermal protection'),
                  subtitle: Text(
                    'Limits generation tokens for audio/image models to prevent device overheating',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  value: _thermalProtection,
                  onChanged: (value) {
                    setState(() {
                      _thermalProtection = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Disabling thermal protection may cause your device to overheat during audio/image generation. Use at your own risk.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chat History',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Save chat history'),
                  subtitle: Text(
                    'Chat history will be saved between sessions',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  value: _saveChatHistory,
                  onChanged: (value) {
                    setState(() {
                      _saveChatHistory = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _showClearDialog,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete all chats'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _saveSettings,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Save Settings'),
        ),
      ],
    );
  }
}
