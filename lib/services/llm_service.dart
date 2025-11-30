import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi/llama_bindings.dart';
import '../ffi/llama_types.dart';
import '../models/llm_model.dart';

class LlmService {
  static final LlmService _instance = LlmService._internal();
  factory LlmService() => _instance;
  
  late final LlamaBindings _bindings;
  int?  _currentModelId;
  Pointer<LlamaDartContext>? _currentContext;
  int _contextLength = 2048;
  final Map<String, StreamController<String>> _generationControllers = {};
  
  // Стоп-послідовності для очищення відповіді
  static const List<String> _stopSequences = [
    'User:',
    '\nUser:',
    'Human:',
    '\nHuman:',
    'Assistant:',
    '\nAssistant:',
    '<|im_end|>',
    '<|im_start|>',
    '<end_of_turn>',
    '<start_of_turn>',
    '<|eot_id|>',
    '<|end|>',
    '</s>',
    '<|assistant|>',
    '<|user|>',
  ];
  
  LlmService._internal();
  
  Future<void> init() async {
    _bindings = LlamaBindings();
    
    final prefs = await SharedPreferences.getInstance();
    _contextLength = prefs. getInt('context_length') ?? 2048;
  }
  
  void setContextLength(int length) {
    _contextLength = length;
  }
  
  Future<bool> loadModel(LlmModel model) async {
    // Перевіримо, чи потрібно розвантажувати поточну модель
    if (_currentModelId != null && _currentContext != null) {
      _bindings.freeContext(_currentContext! );
      _currentContext = null;
    }
    
    final modelsDir = await _getModelsDirectory();
    final modelPath = '${modelsDir. path}/${model.id}.bin';
    
    try {
      // Завантажуємо модель з FFI інтерфейсу
      final quantType = model.quantization == QuantizationType.bit4 ? 4 : 8;
      
      _currentModelId = _bindings.loadModel(
        modelPath,
        quantizationType: quantType,
        nThreads: 4,
      );
      
      if (_currentModelId!  <= 0) {
        return false;
      }
      
      // Створюємо контекст для моделі
      _currentContext = _bindings.createContext(_currentModelId! );
      return _currentContext != null;
    } catch (e) {
      debugPrint('Помилка завантаження моделі: $e');
      return false;
    }
  }
  
  Future<String> generateResponse(String prompt, {int maxTokens = 256}) async {
    if (_currentModelId == null || _currentContext == null) {
      throw Exception('Модель не завантажена');
    }
    
    try {
      // Токенізуємо вхідний текст
      final tokens = _bindings.tokenize(_currentContext!, prompt);
      
      // Генеруємо відповідь з оптимізованими параметрами
      final result = _bindings.generate(
        _currentContext! ,
        tokens,
        maxTokens: maxTokens,
        contextLength: _contextLength,
        temperature: 0.3,        // Низька для стабільності
        topP: 0.85,
        topK: 40,
        repeatPenalty: 1.2,      // Проти повторень
        frequencyPenalty: 0.1,
        presencePenalty: 0.1,
      );
      
      // Звільняємо пам'ять токенів
      _bindings.freeTokenizedText(tokens);
      
      // Очищаємо відповідь від артефактів
      return _cleanResponse(result);
    } catch (e) {
      debugPrint('Помилка генерації відповіді: $e');
      return 'Помилка генерації відповіді: $e';
    }
  }
  
  /// Очищення відповіді від стоп-послідовностей та артефактів
  String _cleanResponse(String response) {
    String cleaned = response;
    
    // Видаляємо стоп-послідовності
    for (final stop in _stopSequences) {
      if (cleaned.contains(stop)) {
        cleaned = cleaned.split(stop).first;
      }
    }
    
    // Видаляємо повторювані слова (наприклад "assistant_oc assistant_oc...")
    cleaned = _removeRepeatedPhrases(cleaned);
    
    // Видаляємо зайві пробіли та переноси
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    
    return cleaned;
  }
  
  /// Видалення повторюваних фраз
  String _removeRepeatedPhrases(String text) {
    // Перевіряємо на повторення слів більше 3 разів підряд
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 4) return text;
    
    final result = <String>[];
    int repeatCount = 0;
    String?  lastWord;
    
    for (final word in words) {
      if (word == lastWord) {
        repeatCount++;
        if (repeatCount < 2) {
          result.add(word);
        }
      } else {
        repeatCount = 0;
        result. add(word);
        lastWord = word;
      }
    }
    
    return result.join(' ');
  }
  
  // Потокова генерація відповіді для відображення у реальному часі
  Stream<String> generateResponseStream(String prompt, {int maxTokens = 256}) {
    final streamId = DateTime.now().millisecondsSinceEpoch.toString();
    final controller = StreamController<String>();
    _generationControllers[streamId] = controller;
    
    Future<void> generate() async {
      if (_currentModelId == null || _currentContext == null) {
        controller.addError('Модель не завантажена');
        await controller.close();
        _generationControllers. remove(streamId);
        return;
      }
      
      try {
        String result = await generateResponse(prompt, maxTokens: maxTokens);
        
        // Емулюємо потокову генерацію
        String accumulated = '';
        for (int i = 0; i < result.length; i++) {
          if (controller.isClosed) break;
          
          accumulated += result[i];
          
          // Перевірка на стоп-послідовності під час стрімінгу
          bool shouldStop = false;
          for (final stop in _stopSequences) {
            if (accumulated.endsWith(stop)) {
              accumulated = accumulated.substring(0, accumulated.length - stop.length);
              shouldStop = true;
              break;
            }
          }
          
          controller.add(accumulated);
          
          if (shouldStop) break;
          
          await Future.delayed(const Duration(milliseconds: 20));
        }
        
        await controller.close();
      } catch (e) {
        controller. addError('Помилка генерації: $e');
        await controller.close();
      } finally {
        _generationControllers. remove(streamId);
      }
    }
    
    generate();
    return controller.stream;
  }
  
  void stopGeneration(String streamId) {
    final controller = _generationControllers[streamId];
    if (controller != null && ! controller.isClosed) {
      controller.close();
      _generationControllers.remove(streamId);
    }
  }
  
  void unloadCurrentModel() {
    if (_currentContext != null) {
      _bindings. freeContext(_currentContext!);
      _currentContext = null;
      _currentModelId = null;
    }
  }
  
  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir. path}/models');
    
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    
    return modelsDir;
  }
  
  // Мок-метод для тестування без реальної моделі
  Future<String> generateMockResponse(String prompt) async {
    await Future.delayed(const Duration(seconds: 2));
    return "Це тестова відповідь для запиту: $prompt. ";
  }
}