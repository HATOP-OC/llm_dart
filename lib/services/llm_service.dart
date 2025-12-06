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
  bool get isModelLoaded => _currentModelId != null && _currentContext != null;
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
    }
  }
  
  void setContextLength(int length) {
    _contextLength = length;
    debugPrint('Context length set to: $length (requires model reload)');
  }
  
  void clearContext() {
    _usedTokens = 0;
    notifyListeners();
    debugPrint('Context cleared');
  }
  
  Future<bool> loadModel(LlmModel model) async {
    debugPrint('Loading model: ${model.id}');
    
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
        debugPrint('Failed to load model');
        _currentModelId = null;
        return false;
      }
      
      debugPrint('Model loaded, ID: $_currentModelId');
      
      _currentContext = _bindings!.createContext(
        _currentModelId!,
        contextLength: _contextLength,
        batchSize: 256,
      );
      
      if (_currentContext == null || _currentContext == nullptr) {
        debugPrint('Failed to create context');
        _bindings! .freeModel(_currentModelId!);
        _currentModelId = null;
        return false;
      }
      
      notifyListeners();
      debugPrint('Model ready: ${model.name}, context: $_contextLength');
      return true;
      
    } catch (e) {
      debugPrint('Error loading model: $e');
      _cleanup();
      return false;
    }
  }
  
  void _cleanup() {
    if (_currentContext != null && _bindings != null) {
      try {
        _bindings!.freeContext(_currentContext! );
      } catch (_) {}
      _currentContext = null;
    }
    if (_currentModelId != null && _bindings != null) {
      try {
        _bindings!.freeModel(_currentModelId!);
      } catch (_) {}
      _currentModelId = null;
    }
  }
  
  Future<String> generateResponse(String prompt, {int maxTokens = 256}) async {
    if (!isModelLoaded || _bindings == null) {
      throw Exception('Model not loaded');
    }
    
    _isGenerating = true;
    _shouldStop = false;
    
    try {
      final tokens = _bindings!.tokenize(_currentContext!, prompt);
      
      final inputTokens = tokens.ref.nTokens;
      _usedTokens = inputTokens + maxTokens;
      notifyListeners();
      
      debugPrint('Input tokens: $inputTokens, context usage: $_usedTokens/$_contextLength');
      
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
      
      _bindings!.freeTokenizedText(tokens);
      
      return _cleanResponse(result);
    } catch (e) {
      debugPrint('Error generating response: $e');
      return 'Error: $e';
    } finally {
      _isGenerating = false;
    }
  }
  
  Stream<String> generateResponseStream(String prompt, {int maxTokens = 256}) {
    final streamId = DateTime.now().millisecondsSinceEpoch.toString();
    final controller = StreamController<String>();
    _generationControllers[streamId] = controller;
    
    _generateStream(prompt, maxTokens, controller, streamId);
    
    return controller.stream;
  }
  
  Future<void> _generateStream(
    String prompt,
    int maxTokens,
    StreamController<String> controller,
    String streamId,
  ) async {
    if (!isModelLoaded) {
      controller.addError('Model not loaded');
      await controller.close();
      _generationControllers. remove(streamId);
      return;
    }
    
    _isGenerating = true;
    _shouldStop = false;
    
    try {
      String result = await generateResponse(prompt, maxTokens: maxTokens);
      
      if (_shouldStop || controller.isClosed) {
        await controller.close();
        return;
      }
      
      String accumulated = '';
      const int chunkSize = 5;
      
      for (int i = 0; i < result.length; i += chunkSize) {
        if (controller.isClosed || _shouldStop) break;
        
        final end = (i + chunkSize < result.length) ?  i + chunkSize : result.length;
        accumulated += result.substring(i, end);
        
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
        
        await Future.delayed(const Duration(milliseconds: 8));
      }
      
      await controller.close();
    } catch (e) {
      controller. addError('Error: $e');
      await controller.close();
    } finally {
      _isGenerating = false;
      _generationControllers.remove(streamId);
    }
  }
  
  void stopGeneration(String streamId) {
    _shouldStop = true;
    final controller = _generationControllers[streamId];
    if (controller != null && !controller.isClosed) {
      controller.close();
      _generationControllers.remove(streamId);
    }
    _isGenerating = false;
  }
  
  String _cleanResponse(String response) {
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
    debugPrint('Unloading model...');
    _cleanup();
    _usedTokens = 0;
    notifyListeners();
    debugPrint('Model unloaded');
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
      
      if (!await modelFile. exists()) return false;
      
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
}

class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  
  @override
  void add(T event) => events.add(event);
  
  @override
  void close() {}
}