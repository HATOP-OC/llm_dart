import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'llama_types.dart';

class LlamaBindings {
  static final LlamaBindings _instance = LlamaBindings._internal();
  factory LlamaBindings() => _instance;
  
  late DynamicLibrary _lib;
  
  // FFI функції з правильними типами
  late final int Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>) _loadModelFn;
  late final Pointer<LlamaDartContext> Function(int) _createContextFn;
  late final Pointer<LlamaDartTokens> Function(Pointer<LlamaDartContext>, Pointer<Utf8>) _tokenizeFn;
  late final Pointer<Utf8> Function(Pointer<LlamaDartContext>, Pointer<LlamaDartTokens>, Pointer<LlamaDartInferenceParams>) _generateFn;
  late final void Function(Pointer<LlamaDartContext>) _freeContextFn;
  late final void Function(Pointer<LlamaDartTokens>) _freeTokensFn;
  late final void Function(Pointer<Utf8>) _freeStringFn;
  
  LlamaBindings._internal() {
    _lib = _loadLibrary();
    _initBindings();
  }
  
  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libllama_bindings.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libllama_bindings.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libllama_bindings.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('llama_bindings. dll');
    }
    throw UnsupportedError('Платформа не підтримується');
  }
  
  void _initBindings() {
    _loadModelFn = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>),
      int Function(Pointer<Utf8>, Pointer<LlamaDartModelParams>)
    >('llama_dart_load_model');
    
    _createContextFn = _lib.lookupFunction<
      Pointer<LlamaDartContext> Function(Int32),
      Pointer<LlamaDartContext> Function(int)
    >('llama_dart_create_context');
    
    _tokenizeFn = _lib.lookupFunction<
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
    
    _freeTokensFn = _lib. lookupFunction<
      Void Function(Pointer<LlamaDartTokens>),
      void Function(Pointer<LlamaDartTokens>)
    >('llama_dart_free_tokens');
    
    _freeStringFn = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)
    >('llama_dart_free_string');
  }
  
  int loadModel(String path, {
    int nGpuLayers = 0,
    int quantizationType = 4,
    int seed = 0,
    int nThreads = 4,
    int nBatch = 512,
  }) {
    final pathPtr = path.toNativeUtf8();
    final params = calloc<LlamaDartModelParams>();
    
    params.ref.nGpuLayers = nGpuLayers;
    params.ref.quantizationType = quantizationType;
    params.ref. seed = seed;
    params.ref. nThreads = nThreads;
    params.ref.nBatch = nBatch;
    
    try {
      return _loadModelFn(pathPtr, params);
    } catch (e) {
      throw Exception('Помилка завантаження моделі: $e');
    } finally {
      calloc.free(pathPtr);
      calloc.free(params);
    }
  }
  
  Pointer<LlamaDartContext> createContext(int modelId) {
    try {
      return _createContextFn(modelId);
    } catch (e) {
      throw Exception('Помилка створення контексту: $e');
    }
  }
  
  Pointer<LlamaDartTokens> tokenize(Pointer<LlamaDartContext> context, String text) {
    final textPtr = text. toNativeUtf8();
    try {
      return _tokenizeFn(context, textPtr);
    } catch (e) {
      throw Exception('Помилка токенізації: $e');
    } finally {
      calloc.free(textPtr);
    }
  }
  
  String generate(
    Pointer<LlamaDartContext> context,
    Pointer<LlamaDartTokens> tokens, {
    int maxTokens = 256,
    int contextLength = 2048,
    double temperature = 0.3,
    double topP = 0.85,
    double topK = 40,
    double repeatPenalty = 1.2,
    int seed = 0,
    double frequencyPenalty = 0.0,
    double presencePenalty = 0.0,
  }) {
    final params = calloc<LlamaDartInferenceParams>();
    
    params.ref.maxTokens = maxTokens;
    params.ref. contextLength = contextLength;
    params. ref.temperature = temperature;
    params. ref.topP = topP;
    params.ref.topK = topK;
    params.ref.repeatPenalty = repeatPenalty;
    params. ref.seed = seed;
    params. ref.frequencyPenalty = frequencyPenalty;
    params.ref. presencePenalty = presencePenalty;
    
    try {
      final resultPtr = _generateFn(context, tokens, params);
      if (resultPtr == nullptr) {
        return 'Error: Generation failed';
      }
      final result = resultPtr.toDartString();
      _freeStringFn(resultPtr);
      return result;
    } catch (e) {
      throw Exception('Помилка генерації тексту: $e');
    } finally {
      calloc.free(params);
    }
  }
  
  void freeContext(Pointer<LlamaDartContext> context) {
    try {
      _freeContextFn(context);
    } catch (e) {
      debugPrint('Помилка звільнення контексту: $e');
    }
  }
  
  void freeTokenizedText(Pointer<LlamaDartTokens> tokens) {
    try {
      _freeTokensFn(tokens);
    } catch (e) {
      debugPrint('Помилка звільнення токенів: $e');
    }
  }
}