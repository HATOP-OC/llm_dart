import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi/llama_bindings.dart';
import '../ffi/llama_types.dart';
import '../models/llm_model.dart';

class LlmService extends ChangeNotifier {
  static final LlmService _instance = LlmService._internal();
  factory LlmService() => _instance;
  
  LlamaBindings? _bindings;
  int?  _currentModelId;
  Pointer<LlamaDartContext>? _currentContext;
  int _contextLength = 2048;
  int _usedTokens = 0;
  final Map<String, StreamController<String>> _generationControllers = {};
  bool _isGenerating = false;
  bool _shouldStop = false;
  bool _isInitialized = false;
  
  static const List<String> _stopSequences = [
    'User:', '\nUser:', 'Human:', '\nHuman:',
    'Assistant:', '\nAssistant:',
    '<|im_end|>', '<|im_start|>', '<end_of_turn>', '<start_of_turn>',
    '<|eot_id|>', '<|end|>', '</s>', '<|assistant|>', '<|user|>',
  ];
  
  LlmService._internal();
  
  bool get isGenerating => _isGenerating;
  bool get isModelLoaded => _currentModelId != null && _currentContext != null && _currentContext != nullptr;
  bool get isInitialized => _isInitialized;
  int get contextLength => _contextLength;
  int get usedTokens => _usedTokens;
  double get contextUsage => _contextLength > 0 ? _usedTokens / _contextLength : 0;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      _bindings = LlamaBindings();
      final prefs = await SharedPreferences.getInstance();
      _contextLength = prefs. getInt('context_length') ?? 2048;
      _isInitialized = true;
      debugPrint('LlmService initialized, context_length: $_contextLength');
    } catch (e) {
      debugPrint('Error initializing LlmService: $e');
      _isInitialized = false;
      rethrow;
    }
  }
  
  void setContextLength(int length) {
    _contextLength = length;
    debugPrint('Context length set to: $length (requires model reload)');
  }
  
  void clearContext() {
    _usedTokens = 0;
    _safeNotifyListeners();
    debugPrint('Context cleared');
  }
  
  /// Безпечний notifyListeners
  void _safeNotifyListeners() {
    try {
      notifyListeners();
    } catch (e) {
      debugPrint('Error in notifyListeners: $e');
    }
  }
  
  Future<bool> loadModel(LlmModel model) async {
    debugPrint('=== LOAD MODEL START: ${model.id} ===');
    
    // Чекаємо якщо генерація в процесі
    if (_isGenerating) {
      debugPrint('Generation in progress, waiting.. .');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isGenerating) {
        debugPrint('Still generating, cannot load model');
        return false;
      }
    }
    
    if (!_isInitialized || _bindings == null) {
      await init();
      if (! _isInitialized || _bindings == null) {
        debugPrint('Failed to initialize LlmService');
        return false;
      }
    }
    
    final prefs = await SharedPreferences.getInstance();
    _contextLength = prefs. getInt('context_length') ?? 2048;
    
    _cleanup();
    _usedTokens = 0;
    
    final modelsDir = await _getModelsDirectory();
    final modelPath = '${modelsDir.path}/${model.id}.bin';
    final modelFile = File(modelPath);
    
    if (!await modelFile.exists()) {
      debugPrint('Model file not found: $modelPath');
      return false;
    }
    
    try {
      debugPrint('Loading with context_length: $_contextLength');
      
      _currentModelId = _bindings!.loadModel(
        modelPath,
        quantizationType: model.quantization == QuantizationType.bit4 ? 4 : 8,
        nBatch: 256,
      );
      
      if (_currentModelId == null || _currentModelId!  <= 0) {
        debugPrint('Failed to load model - invalid ID');
        _currentModelId = null;
        return false;
      }
      
      debugPrint('Model loaded, ID: $_currentModelId');
      
      _currentContext = _bindings!. createContext(
        _currentModelId!,
        contextLength: _contextLength,
        batchSize: 256,
      );
      
      if (_currentContext == null || _currentContext == nullptr) {
        debugPrint('Failed to create context');
        _bindings!.freeModel(_currentModelId!);
        _currentModelId = null;
        return false;
      }
      
      _safeNotifyListeners();
      debugPrint('=== LOAD MODEL SUCCESS: ${model.name} ===');
      return true;
      
    } catch (e) {
      debugPrint('Error loading model: $e');
      _cleanup();
      return false;
    }
  }
  
  void _cleanup() {
    debugPrint('=== CLEANUP START ===');
    
    // Спочатку зупиняємо всі активні генерації
    _shouldStop = true;
    _isGenerating = false;
    
    // Закриваємо всі контролери
    for (final entry in _generationControllers.entries) {
      try {
        if (! entry.value.isClosed) {
          entry.value. close();
        }
      } catch (e) {
        debugPrint('Error closing controller ${entry.key}: $e');
      }
    }
    _generationControllers.clear();
    
    // Звільняємо контекст
    if (_currentContext != null && _currentContext != nullptr && _bindings != null) {
      try {
        _bindings!.freeContext(_currentContext! );
        debugPrint('Context freed');
      } catch (e) {
        debugPrint('Error freeing context: $e');
      }
      _currentContext = null;
    }
    
    // Звільняємо модель
    if (_currentModelId != null && _bindings != null) {
      try {
        _bindings!.freeModel(_currentModelId!);
        debugPrint('Model freed');
      } catch (e) {
        debugPrint('Error freeing model: $e');
      }
      _currentModelId = null;
    }
    
    debugPrint('=== CLEANUP END ===');
  }
  
  Future<String> generateResponse(String prompt, {int maxTokens = 256}) async {
    debugPrint('=== GENERATE RESPONSE START ===');
    
    // Перевірка стану
    if (!isModelLoaded) {
      debugPrint('ERROR: Model not loaded');
      throw Exception('Model not loaded');
    }
    
    if (_bindings == null) {
      debugPrint('ERROR: Bindings is null');
      throw Exception('Bindings not initialized');
    }
    
    // Захист від паралельних викликів
    if (_isGenerating) {
      debugPrint('WARNING: Already generating, waiting...');
      // Чекаємо до 5 секунд
      for (int i = 0; i < 50 && _isGenerating; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_isGenerating) {
        debugPrint('ERROR: Timeout waiting for previous generation');
        return 'Error: Generation already in progress';
      }
    }
    
    _isGenerating = true;
    _shouldStop = false;
    
    Pointer<LlamaDartTokens>? tokens;
    
    try {
      debugPrint('Tokenizing prompt (length: ${prompt.length}).. .');
      tokens = _bindings!. tokenize(_currentContext!, prompt);
      
      if (tokens == nullptr) {
        debugPrint('ERROR: Tokenization returned nullptr');
        return 'Error: Tokenization failed';
      }
      
      final inputTokens = tokens.ref. nTokens;
      debugPrint('Input tokens: $inputTokens');
      
      if (inputTokens <= 0) {
        debugPrint('ERROR: Invalid token count: $inputTokens');
        return 'Error: Invalid input';
      }
      
      _usedTokens = inputTokens + maxTokens;
      
      // Оновлюємо UI в наступному кадрі
      Future.microtask(() => _safeNotifyListeners());
      
      debugPrint('Starting generation (maxTokens: $maxTokens).. .');
      
      final result = _bindings!.generate(
        _currentContext!,
        tokens,
        maxTokens: maxTokens,
        contextLength: _contextLength,
        temperature: 0.5,
        topP: 0.85,
        topK: 40,
        repeatPenalty: 1.2,
        frequencyPenalty: 0.1,
        presencePenalty: 0.1,
      );
      
      debugPrint('Generation completed, result length: ${result.length}');
      
      return _cleanResponse(result);
      
    } catch (e, stackTrace) {
      debugPrint('ERROR in generateResponse: $e');
      debugPrint('Stack trace: $stackTrace');
      return 'Error: $e';
    } finally {
      // Завжди звільняємо токени
      if (tokens != null && tokens != nullptr) {
        try {
          _bindings!.freeTokenizedText(tokens);
          debugPrint('Tokens freed');
        } catch (e) {
          debugPrint('Error freeing tokens: $e');
        }
      }
      
      _isGenerating = false;
      debugPrint('=== GENERATE RESPONSE END ===');
    }
  }
  
  Stream<String> generateResponseStream(String prompt, {int maxTokens = 256}) {
    final streamId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('=== STREAM START: $streamId ===');
    
    // Використовуємо broadcast контролер для безпеки
    final controller = StreamController<String>.broadcast(
      onCancel: () {
        debugPrint('Stream $streamId cancelled');
        _generationControllers.remove(streamId);
      },
    );
    
    _generationControllers[streamId] = controller;
    
    // Запускаємо генерацію асинхронно
    _generateStreamAsync(prompt, maxTokens, controller, streamId);
    
    return controller. stream;
  }
  
  Future<void> _generateStreamAsync(
    String prompt,
    int maxTokens,
    StreamController<String> controller,
    String streamId,
  ) async {
    if (! isModelLoaded) {
      debugPrint('ERROR: Model not loaded for stream $streamId');
      if (! controller.isClosed) {
        controller. addError('Model not loaded');
        await controller.close();
      }
      _generationControllers. remove(streamId);
      return;
    }
    
    try {
      // Генеруємо повну відповідь
      debugPrint('Generating response for stream $streamId...');
      String result = await generateResponse(prompt, maxTokens: maxTokens);
      
      // Перевіряємо чи не було скасовано
      if (_shouldStop || controller.isClosed) {
        debugPrint('Stream $streamId was stopped/closed');
        if (!controller.isClosed) {
          await controller.close();
        }
        _generationControllers. remove(streamId);
        return;
      }
      
      // Перевіряємо на помилку
      if (result.startsWith('Error:')) {
        debugPrint('Generation returned error: $result');
        if (!controller.isClosed) {
          controller.addError(result);
          await controller.close();
        }
        _generationControllers. remove(streamId);
        return;
      }
      
      // Стрімимо по частинах
      String accumulated = '';
      const int chunkSize = 3;
      int updateCounter = 0;
      
      for (int i = 0; i < result. length; i += chunkSize) {
        // Перевіряємо на кожній ітерації
        if (controller.isClosed || _shouldStop) {
          debugPrint('Stream $streamId stopped at char $i');
          break;
        }
        
        final end = (i + chunkSize < result.length) ?  i + chunkSize : result.length;
        accumulated += result.substring(i, end);
        
        // Перевірка на стоп-послідовності
        bool shouldStop = false;
        for (final stop in _stopSequences) {
          if (accumulated.endsWith(stop)) {
            accumulated = accumulated.substring(0, accumulated.length - stop.length);
            shouldStop = true;
            break;
          }
        }
        
        updateCounter++;
        if (updateCounter % 5 == 0 || shouldStop || i + chunkSize >= result.length) {
          if (!controller.isClosed) {
            controller.add(accumulated);
          }
          // Даємо UI час на оновлення
          await Future.delayed(const Duration(milliseconds: 16));
        }
        
        if (shouldStop) break;
      }
      
      // Фінальне оновлення
      if (!controller.isClosed) {
        controller.add(accumulated);
        await controller.close();
      }
      
      debugPrint('=== STREAM $streamId COMPLETE ===');
      
    } catch (e, stackTrace) {
      debugPrint('ERROR in stream $streamId: $e');
      debugPrint('Stack: $stackTrace');
      
      if (!controller. isClosed) {
        controller.addError('Error: $e');
        await controller.close();
      }
    } finally {
      _generationControllers.remove(streamId);
    }
  }
  
  void stopGeneration(String streamId) {
    debugPrint('=== STOP GENERATION: $streamId ===');
    
    _shouldStop = true;
    
    final controller = _generationControllers[streamId];
    if (controller != null) {
      if (!controller.isClosed) {
        try {
          controller. close();
        } catch (e) {
          debugPrint('Error closing controller: $e');
        }
      }
      _generationControllers.remove(streamId);
    }
    
    _isGenerating = false;
  }
  
  /// Зупиняє всі активні генерації
  void stopAllGenerations() {
    debugPrint('=== STOP ALL GENERATIONS ===');
    _shouldStop = true;
    _isGenerating = false;
    
    for (final entry in Map.from(_generationControllers). entries) {
      try {
        if (!entry.value. isClosed) {
          entry.value.close();
        }
      } catch (e) {
        debugPrint('Error closing controller ${entry.key}: $e');
      }
    }
    _generationControllers.clear();
  }
  
  String _cleanResponse(String response) {
    if (response.isEmpty) return '';
    
    String cleaned = response;
    
    for (final stop in _stopSequences) {
      if (cleaned.contains(stop)) {
        cleaned = cleaned.split(stop).first;
      }
    }
    
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    
    return cleaned;
  }
  
  void unloadCurrentModel() {
    debugPrint('=== UNLOAD MODEL ===');
    stopAllGenerations();
    _cleanup();
    _usedTokens = 0;
    _safeNotifyListeners();
  }
  
  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    
    return modelsDir;
  }
  
  Future<void> saveModelChecksum(String modelId, String checksum) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('checksum_$modelId', checksum);
  }
  
  Future<String?> getStoredChecksum(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('checksum_$modelId');
  }
  
  Future<bool> verifyModelChecksum(String modelId) async {
    try {
      final storedChecksum = await getStoredChecksum(modelId);
      if (storedChecksum == null) return true;
      
      final modelsDir = await _getModelsDirectory();
      final modelFile = File('${modelsDir.path}/$modelId.bin');
      
      if (!await modelFile.exists()) return false;
      
      final output = AccumulatorSink<Digest>();
      final input = sha256.startChunkedConversion(output);
      
      await for (final chunk in modelFile.openRead()) {
        input.add(chunk);
      }
      input.close();
      
      final currentChecksum = output.events.single.toString();
      return storedChecksum == currentChecksum;
      
    } catch (e) {
      debugPrint('Verify error: $e');
      return false;
    }
  }
  
  @override
  void dispose() {
    debugPrint('=== LlmService DISPOSE ===');
    stopAllGenerations();
    _cleanup();
    super.dispose();
  }
}

class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  
  @override
  void add(T event) => events.add(event);
  
  @override
  void close() {}
}