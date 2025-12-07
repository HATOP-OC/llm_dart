import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'llama_types.dart';

class LlamaBindings {
  static final LlamaBindings _instance = LlamaBindings._internal();
  factory LlamaBindings() => _instance;
  
  late DynamicLibrary _lib;
  bool _isInitialized = false;
  
  // FFI функції
  late final int Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>) _loadModelFn;
  late final Pointer<LlamaDartContext> Function(int, Pointer<LlamaDartContextParams>) _createContextFn;
  late final Pointer<LlamaDartTokens> Function(Pointer<LlamaDartContext>, Pointer<Utf8>) _tokenizeFn;
  late final Pointer<Utf8> Function(Pointer<LlamaDartContext>, Pointer<LlamaDartTokens>, Pointer<LlamaDartInferenceParams>) _generateFn;
  late final void Function(Pointer<LlamaDartContext>) _freeContextFn;
  late final void Function(int) _freeModelFn;
  late final void Function(Pointer<LlamaDartTokens>) _freeTokensFn;
  late final void Function(Pointer<Utf8>) _freeStringFn;
  
  LlamaBindings._internal() {
    try {
      _lib = _loadLibrary();
      _initBindings();
      _isInitialized = true;
      debugPrint('LlamaBindings initialized successfully');
    } catch (e) {
      debugPrint('ERROR initializing LlamaBindings: $e');
      _isInitialized = false;
      rethrow;
    }
  }
  
  bool get isInitialized => _isInitialized;
  
  DynamicLibrary _loadLibrary() {
    debugPrint('Loading native library...');
    if (Platform.isAndroid) {
      return DynamicLibrary. open('libllama_bindings.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libllama_bindings.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libllama_bindings.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('llama_bindings. dll');
    }
    throw UnsupportedError('Platform not supported');
  }
  
  void _initBindings() {
    debugPrint('Initializing FFI bindings...');
    
    _loadModelFn = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>),
      int Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>)
    >('llama_dart_load_model');
    
    _createContextFn = _lib.lookupFunction<
      Pointer<LlamaDartContext> Function(Int32, Pointer<LlamaDartContextParams>),
      Pointer<LlamaDartContext> Function(int, Pointer<LlamaDartContextParams>)
    >('llama_dart_create_context');
    
    _tokenizeFn = _lib. lookupFunction<
      Pointer<LlamaDartTokens> Function(Pointer<LlamaDartContext>, Pointer<Utf8>),
      Pointer<LlamaDartTokens> Function(Pointer<LlamaDartContext>, Pointer<Utf8>)
    >('llama_dart_tokenize');
    
    _generateFn = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<LlamaDartContext>, Pointer<LlamaDartTokens>, Pointer<LlamaDartInferenceParams>),
      Pointer<Utf8> Function(Pointer<LlamaDartContext>, Pointer<LlamaDartTokens>, Pointer<LlamaDartInferenceParams>)
    >('llama_dart_generate');
    
    _freeContextFn = _lib. lookupFunction<
      Void Function(Pointer<LlamaDartContext>),
      void Function(Pointer<LlamaDartContext>)
    >('llama_dart_free_context');
    
    _freeModelFn = _lib. lookupFunction<
      Void Function(Int32),
      void Function(int)
    >('llama_dart_free_model');
    
    _freeTokensFn = _lib.lookupFunction<
      Void Function(Pointer<LlamaDartTokens>),
      void Function(Pointer<LlamaDartTokens>)
    >('llama_dart_free_tokens');
    
    _freeStringFn = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)
    >('llama_dart_free_string');
    
    debugPrint('FFI bindings initialized');
  }
  
  void _ensureInitialized() {
    if (! _isInitialized) {
      throw StateError('LlamaBindings not initialized');
    }
  }
  
  /// Визначає оптимальну кількість потоків
  int getOptimalThreadCount() {
    final cpuCores = Platform.numberOfProcessors;
    
    int optimal;
    if (cpuCores >= 8) {
      optimal = 3;
    } else if (cpuCores >= 6) {
      optimal = 2;
    } else if (cpuCores >= 4) {
      optimal = 2;
    } else {
      optimal = 1;
    }
    
    debugPrint('CPU cores: $cpuCores, optimal threads: $optimal');
    return optimal;
  }
  
  /// Завантажує модель
  int loadModel(String path, {
    int nGpuLayers = 0,
    int quantizationType = 4,
    int seed = 0,
    int nBatch = 256,
  }) {
    _ensureInitialized();
    debugPrint('=== FFI: loadModel ===');
    debugPrint('Path: $path');
    
    Pointer<Utf8>? pathPtr;
    Pointer<LlamaDartModelParams>?  params;
    
    try {
      pathPtr = path.toNativeUtf8();
      params = calloc<LlamaDartModelParams>();
      
      params.ref.nGpuLayers = nGpuLayers;
      params.ref.quantizationType = quantizationType;
      params. ref.seed = seed;
      params. ref.nBatch = nBatch;
      
      final result = _loadModelFn(pathPtr, params);
      debugPrint('loadModel result: $result');
      return result;
      
    } catch (e) {
      debugPrint('ERROR in loadModel: $e');
      throw Exception('Error loading model: $e');
    } finally {
      if (pathPtr != null) {
        calloc.free(pathPtr);
      }
      if (params != null) {
        calloc.free(params);
      }
    }
  }
  
  /// Створює контекст
  Pointer<LlamaDartContext> createContext(
    int modelId, {
    int contextLength = 1024,
    int batchSize = 256,
    int?  threads,
  }) {
    _ensureInitialized();
    debugPrint('=== FFI: createContext ===');
    debugPrint('modelId: $modelId, contextLength: $contextLength');
    
    final nThreads = threads ?? getOptimalThreadCount();
    Pointer<LlamaDartContextParams>? params;
    
    try {
      params = calloc<LlamaDartContextParams>();
      params.ref.nCtx = contextLength;
      params.ref.nBatch = batchSize;
      params.ref.nThreads = nThreads;
      
      final result = _createContextFn(modelId, params);
      
      if (result == nullptr) {
        debugPrint('ERROR: createContext returned nullptr');
      } else {
        debugPrint('createContext success, handle: ${result.ref.handle}');
      }
      
      return result;
      
    } catch (e) {
      debugPrint('ERROR in createContext: $e');
      throw Exception('Error creating context: $e');
    } finally {
      if (params != null) {
        calloc.free(params);
      }
    }
  }
  
  /// Токенізує текст
  Pointer<LlamaDartTokens> tokenize(Pointer<LlamaDartContext> context, String text) {
    _ensureInitialized();
    debugPrint('=== FFI: tokenize ===');
    debugPrint('Text length: ${text.length}');
    
    if (context == nullptr) {
      debugPrint('ERROR: context is nullptr');
      throw ArgumentError('Context is null');
    }
    
    Pointer<Utf8>? textPtr;
    
    try {
      textPtr = text.toNativeUtf8();
      final result = _tokenizeFn(context, textPtr);
      
      if (result == nullptr) {
        debugPrint('ERROR: tokenize returned nullptr');
        throw Exception('Tokenization failed');
      }
      
      debugPrint('tokenize success, nTokens: ${result.ref.nTokens}');
      return result;
      
    } catch (e) {
      debugPrint('ERROR in tokenize: $e');
      throw Exception('Error tokenizing: $e');
    } finally {
      if (textPtr != null) {
        calloc.free(textPtr);
      }
    }
  }
  
  /// Генерує текст
  String generate(
    Pointer<LlamaDartContext> context,
    Pointer<LlamaDartTokens> tokens, {
    int maxTokens = 256,
    int contextLength = 1024,
    double temperature = 0.5,
    double topP = 0.85,
    double topK = 40,
    double repeatPenalty = 1.2,
    int seed = 0,
    double frequencyPenalty = 0.0,
    double presencePenalty = 0.0,
  }) {
    _ensureInitialized();
    debugPrint('=== FFI: generate ===');
    debugPrint('maxTokens: $maxTokens, temp: $temperature');
    
    if (context == nullptr) {
      debugPrint('ERROR: context is nullptr');
      return 'Error: Context is null';
    }
    
    if (tokens == nullptr) {
      debugPrint('ERROR: tokens is nullptr');
      return 'Error: Tokens is null';
    }
    
    Pointer<LlamaDartInferenceParams>?  params;
    
    try {
      params = calloc<LlamaDartInferenceParams>();
      
      params.ref. maxTokens = maxTokens;
      params.ref.contextLength = contextLength;
      params.ref.temperature = temperature;
      params.ref.topP = topP;
      params.ref.topK = topK;
      params.ref.repeatPenalty = repeatPenalty;
      params.ref.seed = seed;
      params.ref.frequencyPenalty = frequencyPenalty;
      params.ref.presencePenalty = presencePenalty;
      
      debugPrint('Calling _generateFn...');
      final resultPtr = _generateFn(context, tokens, params);
      
      if (resultPtr == nullptr) {
        debugPrint('ERROR: generate returned nullptr');
        return 'Error: Generation failed';
      }
      
      // Безпечне перетворення в Dart string
      String result;
      try {
        result = resultPtr.toDartString();
        debugPrint('generate success, result length: ${result.length}');
      } catch (e) {
        debugPrint('ERROR converting result to string: $e');
        result = 'Error: Failed to decode result';
      }
      
      // Звільняємо C++ string
      try {
        _freeStringFn(resultPtr);
      } catch (e) {
        debugPrint('ERROR freeing result string: $e');
      }
      
      return result;
      
    } catch (e) {
      debugPrint('ERROR in generate: $e');
      return 'Error: $e';
    } finally {
      if (params != null) {
        calloc.free(params);
      }
    }
  }
  
  /// Звільняє контекст
  void freeContext(Pointer<LlamaDartContext> context) {
    if (! _isInitialized) return;
    
    debugPrint('=== FFI: freeContext ===');
    
    if (context == nullptr) {
      debugPrint('WARNING: context is nullptr, skipping');
      return;
    }
    
    try {
      _freeContextFn(context);
      debugPrint('Context freed');
    } catch (e) {
      debugPrint('ERROR freeing context: $e');
    }
  }
  
  /// Звільняє модель
  void freeModel(int modelId) {
    if (!_isInitialized) return;
    
    debugPrint('=== FFI: freeModel $modelId ===');
    
    try {
      _freeModelFn(modelId);
      debugPrint('Model $modelId freed');
    } catch (e) {
      debugPrint('ERROR freeing model: $e');
    }
  }
  
  /// Звільняє токени
  void freeTokenizedText(Pointer<LlamaDartTokens> tokens) {
    if (!_isInitialized) return;
    
    debugPrint('=== FFI: freeTokens ===');
    
    if (tokens == nullptr) {
      debugPrint('WARNING: tokens is nullptr, skipping');
      return;
    }
    
    try {
      _freeTokensFn(tokens);
      debugPrint('Tokens freed');
    } catch (e) {
      debugPrint('ERROR freeing tokens: $e');
    }
  }
}