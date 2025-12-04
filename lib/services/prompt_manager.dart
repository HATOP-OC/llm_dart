import 'dart:ui';

class PromptManager {
  static final Map<String, String> _systemPrompts = {
    'en': '''You are assistant_oc, a helpful assistant. 
Answer in the same language as the user's message.
Be brief and accurate.
For math questions, show step-by-step calculations.
Use proper markdown formatting.''',

    'uk': '''Ти assistant_oc, корисний помічник.
Відповідай тією ж мовою, що й користувач.
Будь коротким і точним.
На математичні питання відповідай з покроковими розрахунками. 
Використовуй правильне markdown форматування.''',

    'ru': '''Ты assistant_oc, полезный помощник.
Отвечай на том же языке, что и пользователь.
Будь кратким и точным.
На математические вопросы отвечай с пошаговыми расчётами.
Используй правильное markdown форматирование.''',
  };

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

  static String getSystemPromptForLanguage(String languageCode) {
    return _systemPrompts[languageCode] ??  _systemPrompts['en']! ;
  }

  static String getSystemPrompt() {
    final languageCode = PlatformDispatcher. instance.locale.languageCode;
    return _systemPrompts[languageCode] ?? _systemPrompts['en']!;
  }

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

  /// Формат для Qwen моделей
  static String formatForQwenWithHistory(String userMessage, String history) {
    final detectedLang = detectLanguage(userMessage);
    final systemPrompt = getSystemPromptForLanguage(detectedLang);
    
    String prompt = '<|im_start|>system\n$systemPrompt<|im_end|>\n';
    
    if (history.isNotEmpty) {
      // Парсимо історію в окремі повідомлення
      final lines = history.split('\n');
      for (final line in lines) {
        if (line.startsWith('User: ')) {
          prompt += '<|im_start|>user\n${line. substring(6)}<|im_end|>\n';
        } else if (line.startsWith('Assistant: ')) {
          prompt += '<|im_start|>assistant\n${line.substring(11)}<|im_end|>\n';
        }
      }
    }
    
    prompt += '<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n';
    
    return prompt;
  }

  static String formatPromptWithHistory(String userMessage, String history, String modelName) {
    final lowerName = modelName.toLowerCase();
    
    if (lowerName.contains('gemma')) {
      return formatForGemmaWithHistory(userMessage, history);
    } else if (lowerName.contains('phi')) {
      return formatForPhiWithHistory(userMessage, history);
    } else if (lowerName.contains('llama')) {
      return formatForLlamaWithHistory(userMessage, history);
    } else if (lowerName.contains('qwen')) {
      return formatForQwenWithHistory(userMessage, history);
    } else if (lowerName. contains('mistral')) {
      return formatForChatMLWithHistory(userMessage, history);
    }
    
    return formatForLlamaWithHistory(userMessage, history);
  }

  static String formatForLlama(String userMessage) {
    return formatForLlamaWithHistory(userMessage, '');
  }

  static String formatForGemma(String userMessage) {
    return formatForGemmaWithHistory(userMessage, '');
  }

  static String formatForPhi(String userMessage) {
    return formatForPhiWithHistory(userMessage, '');
  }

  static String formatForChatML(String userMessage) {
    return formatForChatMLWithHistory(userMessage, '');
  }

  static String formatPrompt(String userMessage, String modelName) {
    return formatPromptWithHistory(userMessage, '', modelName);
  }
}