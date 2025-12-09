import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
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
  
  LlamaBindings?  _bindings;
  int?  _currentModelId;
  Pointer<LlamaDartContext>? _currentContext;
  int _contextLength = 1024;
  int _batchSize = 512;  // NEW: збільшений batch size
  int _usedTokens = 0;
  final Map<String, StreamController<String>> _generationControllers = {};
  bool _isGenerating = false;
  bool _shouldStop = false;
  bool _isInitialized = false;
  
  // NEW: для incremental KV-cache
  bool _useIncrementalKvCache = false;
  
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
      _contextLength = prefs. getInt('context_length') ?? 1024;
      _batchSize = prefs.getInt('batch_size') ?? 512;
      _isInitialized = true;
      debugPrint('LlmService initialized, context_length: $_contextLength, batch_size: $_batchSize');
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
  
  void setBatchSize(int size) {
    _batchSize = size;
    debugPrint('Batch size set to: $size (requires model reload)');
  }
  
  void setIncrementalKvCache(bool enabled) {
    _useIncrementalKvCache = enabled;
    debugPrint('Incremental KV-cache: $enabled');
  }
  
  void clearContext() {
    _usedTokens = 0;
    if (_bindings != null && _currentContext != null && _currentContext != nullptr) {
      _bindings!.clearKvCache(_currentContext!);
    }
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
      debugPrint('Generation in progress, cancelling.. .');
      stopAllGenerations();
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isGenerating) {
        debugPrint('Still generating, cannot load model');
        return false;
      }
    }
    
    if (!_isInitialized || _bindings == null) {
      await init();
      if (!_isInitialized || _bindings == null) {
        debugPrint('Failed to initialize LlmService');
        return false;
      }
    }
    
    final prefs = await SharedPreferences.getInstance();
    _contextLength = prefs. getInt('context_length') ?? 1024;
    _batchSize = prefs.getInt('batch_size') ??  512;
    
    _cleanup();
    _usedTokens = 0;
    
    // Очищаємо guard sets при завантаженні нової моделі
    _bindings!.resetFreedGuards();
    
    final modelsDir = await _getModelsDirectory();
    final modelPath = '${modelsDir.path}/${model.id}.bin';
    final modelFile = File(modelPath);
    
    if (!await modelFile.exists()) {
      debugPrint('Model file not found: $modelPath');
      return false;
    }
    
    try {
      debugPrint('Loading with context_length: $_contextLength, batch_size: $_batchSize');
      
      _currentModelId = _bindings!.loadModel(
        modelPath,
        quantizationType: model.quantization == QuantizationType.bit4 ? 4 : 8,
        nBatch: _batchSize,
      );
      
      if (_currentModelId == null || _currentModelId!  <= 0) {
        debugPrint('Failed to load model - invalid ID');
        _currentModelId = null;
        return false;
      }
      
      debugPrint('Model loaded, ID: $_currentModelId');
      
      _currentContext = _bindings!.createContext(
        _currentModelId!,
        contextLength: _contextLength,
        batchSize: _batchSize,
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
    
    // Спочатку скасовуємо генерацію через C++
    if (_bindings != null && _currentContext != null && _currentContext != nullptr) {
      try {
        _bindings!.cancelGeneration(_currentContext! );
      } catch (e) {
        debugPrint('Error cancelling generation: $e');
      }
    }
    
    _shouldStop = true;
    _isGenerating = false;
    
    // Закриваємо всі контролери
    for (final entry in _generationControllers.entries) {
      try {
        if (! entry.value.isClosed) {
          entry.value.close();
        }
      } catch (e) {
        debugPrint('Error closing controller ${entry.key}: $e');
      }
    }
    _generationControllers. clear();
    
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
  
  Future<String> generateResponse(String prompt, {
    int maxTokens = 256,
    int timeoutMs = 60000,  // NEW: 60 секунд timeout
  }) async {
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
    
    // Перевіряємо чи генерація вже активна через C++
    if (_bindings!.isGenerating(_currentContext!)) {
      debugPrint('WARNING: C++ reports generation in progress');
      // Чекаємо або скасовуємо
      for (int i = 0; i < 30 && _bindings!.isGenerating(_currentContext! ); i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_bindings!.isGenerating(_currentContext!)) {
        debugPrint('ERROR: Timeout waiting for previous generation');
        return 'Error: Generation already in progress';
      }
    }
    
    // Захист від паралельних викликів на Dart стороні
    if (_isGenerating) {
      debugPrint('WARNING: Dart reports already generating, waiting...');
      for (int i = 0; i < 50 && _isGenerating; i++) {
        await Future. delayed(const Duration(milliseconds: 100));
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
      debugPrint('Tokenizing prompt (length: ${prompt.length})...');
      tokens = _bindings!.tokenize(_currentContext!, prompt);
      
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
      
      // Перевіряємо чи вміщаємось в контекст
      final kvPos = _bindings! .getKvCachePosition(_currentContext!);
      final totalNeeded = kvPos + inputTokens + maxTokens;
      
      if (totalNeeded > _contextLength) {
        debugPrint('WARNING: Context overflow predicted ($totalNeeded > $_contextLength), clearing KV-cache');
        _bindings!.clearKvCache(_currentContext!);
      }
      
      _usedTokens = inputTokens + maxTokens;
      
      // Оновлюємо UI в наступному кадрі
      Future.microtask(() => _safeNotifyListeners());
      
      debugPrint('Starting generation (maxTokens: $maxTokens, timeout: ${timeoutMs}ms)...');
      
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
        timeoutMs: timeoutMs,
        clearKvCache: ! _useIncrementalKvCache,
      );
      
      debugPrint('Generation completed, result length: ${result.length}');
      
      // Оновлюємо used tokens з реальної позиції
      _usedTokens = _bindings!.getKvCachePosition(_currentContext!);
      
      return _cleanResponse(result);
      
    } catch (e, stackTrace) {
      debugPrint('ERROR in generateResponse: $e');
      debugPrint('Stack trace: $stackTrace');
      return 'Error: $e';
    } finally {
      // Завжди звільняємо токени (з guard проти double-free)
      if (tokens != null && tokens != nullptr) {
        try {
          _bindings!.freeTokenizedText(tokens);
        } catch (e) {
          debugPrint('Error freeing tokens: $e');
        }
      }
      
      _isGenerating = false;
      debugPrint('=== GENERATE RESPONSE END ===');
    }
  }
  
  Stream<String> generateResponseStream(String prompt, {
    int maxTokens = 256,
    int timeoutMs = 60000,
  }) {
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
    _generateStreamAsync(prompt, maxTokens, timeoutMs, controller, streamId);
    
    return controller. stream;
  }
  
  Future<void> _generateStreamAsync(
    String prompt,
    int maxTokens,
    int timeoutMs,
    StreamController<String> controller,
    String streamId,
  ) async {
    if (!isModelLoaded) {
      debugPrint('ERROR: Model not loaded for stream $streamId');
      if (!controller.isClosed) {
        controller.addError('Model not loaded');
        await controller.close();
      }
      _generationControllers.remove(streamId);
      return;
    }

    if (_isGenerating) {
      debugPrint('ERROR: Generation already in progress for stream $streamId');
      if (!controller.isClosed) {
        controller.addError('Error: Generation already in progress');
        await controller.close();
      }
      return;
    }

    _isGenerating = true;
    _shouldStop = false;
    Pointer<LlamaDartTokens>? tokens;
    ReceivePort? receivePort;

    try {
      tokens = _bindings!.tokenize(_currentContext!, prompt);
      if (tokens == nullptr) {
        throw Exception('Tokenization failed');
      }

      final kvPos = _bindings!.getKvCachePosition(_currentContext!);
      final inputTokens = tokens.ref.nTokens;
      final totalNeeded = kvPos + inputTokens + maxTokens;

      if (totalNeeded > _contextLength) {
        _bindings!.clearKvCache(_currentContext!);
      }

      _usedTokens = inputTokens + maxTokens;
      Future.microtask(() => _safeNotifyListeners());

      receivePort = ReceivePort();
      final completer = Completer<String>();

      debugPrint('[$streamId] Listening on receive port...');
      receivePort.listen(
        (dynamic message) {
          debugPrint('[$streamId] Received message: $message');
          if (message is String) {
            completer.complete(message);
          } else {
            completer.completeError('Unexpected message type: ${message.runtimeType}');
          }
          receivePort?.close();
        },
        onError: (error) {
          debugPrint('[$streamId] Received error on port: $error');
          completer.completeError(error);
          receivePort?.close();
        },
      );

      debugPrint('[$streamId] Calling generateAsync in C++...');
      _bindings!.generateAsync(
        receivePort.sendPort,
        _currentContext!,
        tokens,
        maxTokens: maxTokens,
        timeoutMs: timeoutMs,
        clearKvCache: !_useIncrementalKvCache,
      );

      debugPrint('[$streamId] Waiting for C++ result with timeout...');
      final result = await completer.future.timeout(
        Duration(milliseconds: timeoutMs + 5000), // Add 5s buffer to C++ timeout
        onTimeout: () {
          debugPrint('[$streamId] Dart-side timeout reached!');
          throw TimeoutException('Generation timed out on the Dart side.');
        },
      );

      debugPrint('[$streamId] C++ result received: ${result.substring(0, min(result.length, 100))}...');

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }
      
      if (_shouldStop || controller.isClosed) {
        debugPrint('Stream $streamId was stopped/closed');
        if (!controller.isClosed) {
          await controller.close();
        }
        _generationControllers.remove(streamId);
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
          await Future. delayed(const Duration(milliseconds: 16));
        }
        
        if (shouldStop) break;
      }
      
      // Фінальне оновлення
      if (!controller. isClosed) {
        controller.add(accumulated);
        await controller.close();
      }

    } catch (e, stackTrace) {
      debugPrint('ERROR in stream $streamId: $e');
      debugPrint('Stack: $stackTrace');
      if (!controller.isClosed) {
        controller.addError('Error: $e');
      }
    } finally {
      _isGenerating = false;
      _usedTokens = _bindings?.getKvCachePosition(_currentContext!) ?? _usedTokens;
      if (tokens != null && tokens != nullptr) {
        _bindings!.freeTokenizedText(tokens);
      }
      receivePort?.close();
      if (!controller.isClosed) {
        await controller.close();
      }
      _generationControllers.remove(streamId);
      debugPrint('=== STREAM $streamId COMPLETE ===');
    }
  }
  
  void stopGeneration(String streamId) {
    debugPrint('=== STOP GENERATION: $streamId ===');
    
    _shouldStop = true;
    
    // Скасовуємо через C++
    if (_bindings != null && _currentContext != null && _currentContext != nullptr) {
      _bindings!.cancelGeneration(_currentContext!);
    }
    
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
    
    // Скасовуємо через C++
    if (_bindings != null && _currentContext != null && _currentContext != nullptr) {
      _bindings!.cancelGeneration(_currentContext!);
    }
    
    for (final entry in Map.from(_generationControllers). entries) {
      try {
        if (! entry.value.isClosed) {
          entry.value. close();
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
        cleaned = cleaned. split(stop).first;
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
    _bindings?. resetFreedGuards();
    _safeNotifyListeners();
  }
  
  /// Отримує поточну позицію KV-cache
  int getKvCachePosition() {
    if (_bindings == null || _currentContext == null || _currentContext == nullptr) {
      return 0;
    }
    return _bindings!.getKvCachePosition(_currentContext!);
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
  
  Future<String? > getStoredChecksum(String modelId) async {
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
    super. dispose();
  }
}

class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  
  @override
  void add(T event) => events.add(event);
  
  @override
  void close() {}
}