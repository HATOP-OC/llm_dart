import 'dart:ui';

class PromptManager {
  // Системні промпти на різних мовах
  static final Map<String, String> _systemPrompts = {
    'en': '''You are assistant_oc, a helpful assistant. 
Answer in the same language as the user's message. 
Be brief and accurate. 
Answer math questions with step-by-step calculations.''',

    'uk': '''Ти assistant_oc, корисний помічник. 
Відповідай тією ж мовою, що й користувач.
Будь коротким і точним.
На математичні питання відповідай з покроковими розрахунками.''',

    'ru': '''Ты assistant_oc, полезный помощник.
Отвечай на том же языке, что и пользователь.
Будь кратким и точным.
На математические вопросы отвечай с пошаговыми расчётами.''',
  };

  /// Визначити мову тексту
  static String detectLanguage(String text) {
    final cyrillicPattern = RegExp(r'[а-яА-ЯёЁіІїЇєЄґҐ]');
    final ukrainianPattern = RegExp(r'[іІїЇєЄґҐ]');
    
    if (cyrillicPattern.hasMatch(text)) {
      if (ukrainianPattern.hasMatch(text)) {
        return 'uk';
      }
      return 'ru';
    }
    
    return 'en';
  }

  /// Отримати системний промпт для мови повідомлення
  static String getSystemPromptForLanguage(String languageCode) {
    return _systemPrompts[languageCode] ?? _systemPrompts['en']!;
  }

  /// Отримати системний промпт для мови пристрою
  static String getSystemPrompt() {
    final languageCode = PlatformDispatcher. instance.locale.languageCode;
    return _systemPrompts[languageCode] ?? _systemPrompts['en']!;
  }

  /// Форматування промпту для Llama з історією
  static String formatForLlamaWithHistory(String userMessage, String history) {
    final detectedLang = detectLanguage(userMessage);
    final systemPrompt = getSystemPromptForLanguage(detectedLang);
    
    if (history.isEmpty) {
      return '''<|begin_of_text|><|start_header_id|>system<|end_header_id|>

$systemPrompt<|eot_id|><|start_header_id|>user<|end_header_id|>

$userMessage<|eot_id|><|start_header_id|>assistant<|end_header_id|>

''';
    }
    
    return '''<|begin_of_text|><|start_header_id|>system<|end_header_id|>

$systemPrompt

Previous conversation:
$history<|eot_id|><|start_header_id|>user<|end_header_id|>

$userMessage<|eot_id|><|start_header_id|>assistant<|end_header_id|>

''';
  }

  /// Форматування промпту для Gemma з історією
  static String formatForGemmaWithHistory(String userMessage, String history) {
    final detectedLang = detectLanguage(userMessage);
    final systemPrompt = getSystemPromptForLanguage(detectedLang);
    
    String prompt = '<start_of_turn>user\n$systemPrompt\n';
    
    if (history. isNotEmpty) {
      prompt += '\nPrevious conversation:\n$history\n';
    }
    
    prompt += '$userMessage<end_of_turn>\n<start_of_turn>model\n';
    
    return prompt;
  }

  /// Форматування промпту для Phi з історією
  static String formatForPhiWithHistory(String userMessage, String history) {
    final detectedLang = detectLanguage(userMessage);
    final systemPrompt = getSystemPromptForLanguage(detectedLang);
    
    String prompt = '<|system|>\n$systemPrompt';
    
    if (history.isNotEmpty) {
      prompt += '\n\nPrevious conversation:\n$history';
    }
    
    prompt += '<|end|>\n<|user|>\n$userMessage<|end|>\n<|assistant|>\n';
    
    return prompt;
  }

  /// Форматування промпту для ChatML з історією
  static String formatForChatMLWithHistory(String userMessage, String history) {
    final detectedLang = detectLanguage(userMessage);
    final systemPrompt = getSystemPromptForLanguage(detectedLang);
    
    String prompt = '<|im_start|>system\n$systemPrompt';
    
    if (history.isNotEmpty) {
      prompt += '\n\nPrevious conversation:\n$history';
    }
    
    prompt += '<|im_end|>\n<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n';
    
    return prompt;
  }

  /// Автоматичне визначення формату за назвою моделі (з історією)
  static String formatPromptWithHistory(String userMessage, String history, String modelName) {
    final lowerName = modelName.toLowerCase();
    
    if (lowerName.contains('gemma')) {
      return formatForGemmaWithHistory(userMessage, history);
    } else if (lowerName.contains('phi')) {
      return formatForPhiWithHistory(userMessage, history);
    } else if (lowerName.contains('llama')) {
      return formatForLlamaWithHistory(userMessage, history);
    } else if (lowerName.contains('mistral') || lowerName. contains('qwen')) {
      return formatForChatMLWithHistory(userMessage, history);
    }
    
    // За замовчуванням — Llama формат
    return formatForLlamaWithHistory(userMessage, history);
  }

  /// Форматування промпту для Llama (без історії)
  static String formatForLlama(String userMessage) {
    return formatForLlamaWithHistory(userMessage, '');
  }

  /// Форматування промпту для Gemma (без історії)
  static String formatForGemma(String userMessage) {
    return formatForGemmaWithHistory(userMessage, '');
  }

  /// Форматування промпту для Phi (без історії)
  static String formatForPhi(String userMessage) {
    return formatForPhiWithHistory(userMessage, '');
  }

  /// Форматування промпту для ChatML (без історії)
  static String formatForChatML(String userMessage) {
    return formatForChatMLWithHistory(userMessage, '');
  }

  /// Автоматичне визначення формату за назвою моделі (без історії)
  static String formatPrompt(String userMessage, String modelName) {
    return formatPromptWithHistory(userMessage, '', modelName);
  }
}