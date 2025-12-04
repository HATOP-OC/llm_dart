import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'llama_types.dart';

class LlamaBindings {
  static final LlamaBindings _instance = LlamaBindings._internal();
  factory LlamaBindings() => _instance;
  
  late DynamicLibrary _lib;
  
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
    _lib = _loadLibrary();
    _initBindings();
  }
  
  DynamicLibrary _loadLibrary() {
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
    _loadModelFn = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>),
      int Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>)
    >('llama_dart_load_model');
    
    _createContextFn = _lib. lookupFunction<
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
  }
  
  /// Визначає оптимальну кількість потоків (~50% CPU)
  int getOptimalThreadCount() {
    final cpuCores = Platform.numberOfProcessors;
    
    int optimal;
    if (cpuCores >= 8) {
      optimal = 3;  // Флагман: 3 з 8 ядер (~37%)
    } else if (cpuCores >= 6) {
      optimal = 2;  // Середній: 2 з 6 ядер (~33%)
    } else if (cpuCores >= 4) {
      optimal = 2;  // Бюджет: 2 з 4 ядер (50%)
    } else {
      optimal = 1;  // Старий: 1 ядро
    }
    
    debugPrint('CPU cores: $cpuCores, optimal threads: $optimal (~${(optimal * 100 / cpuCores).round()}% CPU)');
    
    return optimal;
  }
  
  /// Завантажує модель з MMAP (оптимізація RAM)
  int loadModel(String path, {
    int nGpuLayers = 0,
    int quantizationType = 4,
    int seed = 0,
    int nBatch = 256,
  }) {
    final pathPtr = path.toNativeUtf8();
    final params = calloc<LlamaDartModelParams>();
    
    params.ref.nGpuLayers = nGpuLayers;
    params.ref.quantizationType = quantizationType;
    params.ref. seed = seed;
    params.ref. nBatch = nBatch;
    
    debugPrint('Loading model with MMAP enabled (RAM optimized)');
    
    try {
      final result = _loadModelFn(pathPtr, params);
      if (result > 0) {
        debugPrint('Model loaded successfully, ID: $result');
      }
      return result;
    } catch (e) {
      throw Exception('Error loading model: $e');
    } finally {
      calloc.free(pathPtr);
      calloc.free(params);
    }
  }
  
  /// Створює контекст з оптимізованими параметрами
  Pointer<LlamaDartContext> createContext(
    int modelId, {
    int contextLength = 1024,
    int batchSize = 256,
    int?  threads,
  }) {
    final nThreads = threads ?? getOptimalThreadCount();
    
    final params = calloc<LlamaDartContextParams>();
    params.ref. nCtx = contextLength;
    params.ref.nBatch = batchSize;
    params. ref.nThreads = nThreads;
    
    debugPrint('Creating context: n_ctx=$contextLength, n_batch=$batchSize, n_threads=$nThreads');
    
    try {
      final result = _createContextFn(modelId, params);
      if (result != nullptr) {
        debugPrint('Context created successfully');
      }
      return result;
    } catch (e) {
      throw Exception('Error creating context: $e');
    } finally {
      calloc.free(params);
    }
  }
  
  /// Токенізує текст
  Pointer<LlamaDartTokens> tokenize(Pointer<LlamaDartContext> context, String text) {
    final textPtr = text. toNativeUtf8();
    try {
      return _tokenizeFn(context, textPtr);
    } catch (e) {
      throw Exception('Error tokenizing: $e');
    } finally {
      calloc.free(textPtr);
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
    final params = calloc<LlamaDartInferenceParams>();
    
    params.ref. maxTokens = maxTokens;
    params.ref.contextLength = contextLength;
    params.ref.temperature = temperature;
    params.ref.topP = topP;
    params.ref.topK = topK;
    params.ref. repeatPenalty = repeatPenalty;
    params.ref.seed = seed;
    params.ref.frequencyPenalty = frequencyPenalty;
    params.ref.presencePenalty = presencePenalty;
    
    try {
      final resultPtr = _generateFn(context, tokens, params);
      if (resultPtr == nullptr) {
        return 'Error: Generation failed';
      }
      final result = resultPtr.toDartString();
      _freeStringFn(resultPtr);
      return result;
    } catch (e) {
      throw Exception('Error generating: $e');
    } finally {
      calloc.free(params);
    }
  }
  
  /// Звільняє контекст
  void freeContext(Pointer<LlamaDartContext> context) {
    try {
      _freeContextFn(context);
      debugPrint('Context freed');
    } catch (e) {
      debugPrint('Error freeing context: $e');
    }
  }
  
  /// Звільняє модель
  void freeModel(int modelId) {
    try {
      _freeModelFn(modelId);
      debugPrint('Model $modelId freed');
    } catch (e) {
      debugPrint('Error freeing model: $e');
    }
  }
  
  /// Звільняє токени
  void freeTokenizedText(Pointer<LlamaDartTokens> tokens) {
    try {
      _freeTokensFn(tokens);
    } catch (e) {
      debugPrint('Error freeing tokens: $e');
    }
  }
}