import 'dart:ffi';

/// Параметри моделі
final class LlamaDartModelParams extends Struct {
  @Int32()
  external int nGpuLayers;
  
  @Int32()
  external int quantizationType;
  
  @Int32()
  external int seed;
  
  @Int32()
  external int nBatch;
}

/// Параметри контексту
final class LlamaDartContextParams extends Struct {
  @Int32()
  external int nCtx;
  
  @Int32()
  external int nBatch;
  
  @Int32()
  external int nThreads;
}

/// Контекст
final class LlamaDartContext extends Struct {
  @Int64()
  external int handle;
}

/// Токени
final class LlamaDartTokens extends Struct {
  external Pointer<Int32> tokens;
  
  @Int32()
  external int nTokens;
}

/// Параметри інференсу
final class LlamaDartInferenceParams extends Struct {
  @Int32()
  external int maxTokens;
  
  @Int32()
  external int contextLength;
  
  @Float()
  external double temperature;
  
  @Float()
  external double topP;
  
  @Float()
  external double topK;
  
  @Float()
  external double repeatPenalty;
  
  @Int32()
  external int seed;
  
  @Float()
  external double frequencyPenalty;
  
  @Float()
  external double presencePenalty;
}