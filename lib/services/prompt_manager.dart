import 'dart:ui';

class PromptManager {
  static final Map<String, String> _systemPrompts = {
    'en': '''You are assistant_oc, a helpful assistant. 
Reply in the same language as the user.
Be brief and accurate.
If unsure, say "I don't know."''',

    'uk': '''Ти assistant_oc, корисний помічник.
Відповідай тією ж мовою, що й користувач.
Будь коротким і точним. 
Якщо не знаєш — скажи "Не знаю."''',

    'ru': '''Ты assistant_oc, полезный помощник. 
Отвечай на том же языке, что и пользователь.
Будь кратким и точным.
Если не знаешь — скажи "Не знаю."''',
  };

  /// Отримати системний промпт для поточної мови
  static String getSystemPrompt() {
    final languageCode = PlatformDispatcher.instance.locale. languageCode;
    return _systemPrompts[languageCode] ?? _systemPrompts['en']!;
  }

  /// Форматування промпту для Gemma
  static String formatForGemma(String userMessage) {
    final systemPrompt = getSystemPrompt();
    return '''<start_of_turn>user
$systemPrompt

$userMessage<end_of_turn>
<start_of_turn>model
''';
  }

  /// Форматування промпту для Phi
  static String formatForPhi(String userMessage) {
    final systemPrompt = getSystemPrompt();
    return '''<|system|>
$systemPrompt<|end|>
<|user|>
$userMessage<|end|>
<|assistant|>
''';
  }

  /// Форматування промпту для Llama
  static String formatForLlama(String userMessage) {
    final systemPrompt = getSystemPrompt();
    return '''<|begin_of_text|><|start_header_id|>system<|end_header_id|>

$systemPrompt<|eot_id|><|start_header_id|>user<|end_header_id|>

$userMessage<|eot_id|><|start_header_id|>assistant<|end_header_id|>

''';
  }

  /// Форматування промпту для ChatML (Mistral, Qwen тощо)
  static String formatForChatML(String userMessage) {
    final systemPrompt = getSystemPrompt();
    return '''<|im_start|>system
$systemPrompt<|im_end|>
<|im_start|>user
$userMessage<|im_end|>
<|im_start|>assistant
''';
  }

  /// Автоматичне визначення формату за назвою моделі
  static String formatPrompt(String userMessage, String modelName) {
    final lowerName = modelName.toLowerCase();
    
    if (lowerName. contains('gemma')) {
      return formatForGemma(userMessage);
    } else if (lowerName.contains('phi')) {
      return formatForPhi(userMessage);
    } else if (lowerName.contains('llama')) {
      return formatForLlama(userMessage);
    } else if (lowerName.contains('mistral') || lowerName. contains('qwen')) {
      return formatForChatML(userMessage);
    }
    
    // За замовчуванням — ChatML
    return formatForChatML(userMessage);
  }
}