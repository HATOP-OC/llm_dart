import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_model.dart';
import 'llm_service.dart';

class ModelManager extends ChangeNotifier {
  final LlmService llmService;
  List<LlmModel> _models = [];
  String?  _activeModelId;
  late SharedPreferences _prefs;
  final Map<String, StreamSubscription> _downloadSubscriptions = {};
  final Map<String, Sink<List<int>>> _checksumSinks = {};
  final Map<String, AccumulatorSink<Digest>> _checksumOutputs = {};
  bool _isInitialized = false;
  bool _isLoadingModel = false;

  ModelManager({required this.llmService});
  
  List<LlmModel> get models => _models;
  bool get isInitialized => _isInitialized;
  bool get isLoadingModel => _isLoadingModel;
  
  LlmModel? get activeModel {
    if (_activeModelId == null) return null;
    try {
      return _models.firstWhere((m) => m.id == _activeModelId);
    } catch (_) {
      return null;
    }
  }
  
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _activeModelId = _prefs.getString('active_model_id');
    
    _models = [
      LlmModel(
        id: 'gemma-3n-E2B-it-Q4_K_M',
        name: 'Gemma 3n E2B It (4-bit)',
        description: 'A 3rd generation, lightweight model from Google.',
        url: 'https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf?download=true',
        size: 3030000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.text,
      ),
      LlmModel(
        id: 'phi-3-mini-4k-instruct-q4',
        name: 'Phi-3 Mini Instruct (4-bit)',
        description: 'A 3. 8B parameter model from Microsoft.',
        url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf?download=true',
        size: 2390000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.text,
      ),
      LlmModel(
        id: 'llama-3. 2-1b-instruct-q4_k_m',
        name: 'Llama 3. 2 1B Instruct (Q4_K_M)',
        description: 'Compact 1B model from Meta.',
        url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
        size: 808000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.text,
      ),
      LlmModel(
        id: 'qwen2. 5-1.5b-instruct-q4_k_m',
        name: 'Qwen 2.5 1. 5B Instruct (Q4_K_M)',
        description: 'Efficient 1.5B model from Alibaba.',
        url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true',
        size: 986000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.text,
      ),
      // Audio generation model (TTS)
      LlmModel(
        id: 'outte-tts-0.3-0.5b-q4_k_m',
        name: 'OuteTTS 0.3 0.5B (Q4_K_M)',
        description: 'Lightweight TTS model for audio generation. ⚠️ Uses limited resources to prevent overheating.',
        url: 'https://huggingface.co/OuteAI/OuteTTS-0.3-0.5B-GGUF/resolve/main/OuteTTS-0.3-0.5B-Q4_K_M.gguf?download=true',
        size: 534000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.audioGeneration,
        maxTokens: 128,
      ),
      // Small image generation model
      LlmModel(
        id: 'stable-diffusion-v1-5-pruned-q4_0',
        name: 'Stable Diffusion v1.5 (Q4_0, Tiny)',
        description: 'Minimal image generation model. ⚠️ Thermal-safe: limited resolution (256x256) and steps to prevent overheating.',
        url: 'https://huggingface.co/second-state/stable-diffusion-v-1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf?download=true',
        size: 1070000000,
        quantization: QuantizationType.bit4,
        modelType: ModelType.imageGeneration,
        maxTokens: 64,
      ),
    ];
    
    await _checkDownloadedModels();
    
    _isInitialized = true;
    notifyListeners();
    
    _reloadActiveModel();
  }
  
  Future<void> _reloadActiveModel() async {
    if (_activeModelId == null) return;
    
    final modelIndex = _models.indexWhere((m) => m.id == _activeModelId);
    if (modelIndex == -1) {
      await _clearActiveModel();
      return;
    }
    
    final model = _models[modelIndex];
    
    final modelsDir = await _getModelsDirectory();
    final modelFile = File('${modelsDir.path}/${model.id}.bin');
    
    if (!await modelFile.exists()) {
      debugPrint('Model file not found: ${modelFile.path}');
      await _clearActiveModel();
      _models[modelIndex] = model.copyWith(status: ModelStatus.notDownloaded);
      notifyListeners();
      return;
    }
    
    debugPrint('Reloading model: ${model.name}');
    
    _models[modelIndex] = model.copyWith(status: ModelStatus.activating);
    _isLoadingModel = true;
    notifyListeners();
    
    final success = await llmService.loadModel(model);
    
    if (success) {
      _models[modelIndex] = model.copyWith(status: ModelStatus.active);
      debugPrint('Model reloaded successfully');
    } else {
      _models[modelIndex] = model.copyWith(status: ModelStatus.downloaded);
      await _clearActiveModel();
      debugPrint('Failed to reload model');
    }
    
    _isLoadingModel = false;
    notifyListeners();
  }
  
  Future<void> _clearActiveModel() async {
    _activeModelId = null;
    await _prefs.remove('active_model_id');
    llmService.unloadCurrentModel();
  }
  
  Future<void> _checkDownloadedModels() async {
    final modelsDir = await _getModelsDirectory();
    
    for (int i = 0; i < _models. length; i++) {
      final model = _models[i];
      final modelFile = File('${modelsDir.path}/${model.id}.bin');
      
      if (await modelFile.exists()) {
        final fileSize = await modelFile.length();
        
        if (fileSize < model.size * 0.95) {
          debugPrint('Incomplete file: ${model.id}');
          await modelFile.delete();
          continue;
        }
        
        _models[i] = model.copyWith(status: ModelStatus.downloaded);
      }
    }
    
    await _cleanupTempFiles(modelsDir);
  }
  
  Future<void> _cleanupTempFiles(Directory modelsDir) async {
    try {
      final files = modelsDir.listSync();
      for (final file in files) {
        if (file is File && file.path.endsWith('.tmp')) {
          await file.delete();
        }
      }
    } catch (_) {}
  }
  
  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    
    return modelsDir;
  }
  
  void _cleanupChecksumResources(String modelId) {
    try {
      _checksumSinks[modelId]?.close();
    } catch (_) {}
    _checksumSinks.remove(modelId);
    _checksumOutputs.remove(modelId);
  }
  
  Future<void> downloadModel(String modelId) async {
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return;
    
    final model = _models[modelIndex];
    final modelsDir = await _getModelsDirectory();
    
    final tempFile = File('${modelsDir.path}/${model.id}.tmp');
    final finalFile = File('${modelsDir.path}/${model.id}.bin');
    
    if (await tempFile.exists()) await tempFile.delete();
    if (await finalFile.exists()) await finalFile.delete();
    
    _models[modelIndex] = model.copyWith(
      status: ModelStatus.downloading,
      downloadProgress: 0.0,
    );
    notifyListeners();
    
    final checksumOutput = AccumulatorSink<Digest>();
    final checksumInput = sha256.startChunkedConversion(checksumOutput);
    _checksumOutputs[modelId] = checksumOutput;
    _checksumSinks[modelId] = checksumInput;
    
    IOSink? sink;
    http.Client? client;
    
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(model.url));
      final response = await client. send(request);
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ??  0;
      sink = tempFile.openWrite();
      int received = 0;
      
      _downloadSubscriptions[modelId] = response.stream.listen(
        (chunk) {
          sink?.add(chunk);
          _checksumSinks[modelId]?.add(chunk);
          received += chunk.length;
          
          if (contentLength > 0) {
            _models[modelIndex] = model.copyWith(
              status: ModelStatus.downloading,
              downloadProgress: received / contentLength,
            );
            notifyListeners();
          }
        },
        onDone: () async {
          await _finishDownload(
            modelId, modelIndex, model, sink, tempFile, finalFile, client,
          );
        },
        onError: (error) async {
          await _handleDownloadError(
            modelId, modelIndex, model, sink, tempFile, client, error,
          );
        },
        cancelOnError: true,
      );
      
    } catch (e) {
      await sink?.close();
      _cleanupChecksumResources(modelId);
      if (await tempFile.exists()) await tempFile.delete();
      _models[modelIndex] = model.copyWith(status: ModelStatus.error);
      client?.close();
      notifyListeners();
    }
  }
  
  Future<void> _finishDownload(
    String modelId,
    int modelIndex,
    LlmModel model,
    IOSink?  sink,
    File tempFile,
    File finalFile,
    http.Client?  client,
  ) async {
    _models[modelIndex] = model.copyWith(
      status: ModelStatus.finalizing,
      downloadProgress: 1.0,
    );
    notifyListeners();
    
    await sink?.flush();
    await sink?.close();
    
    if (! await tempFile.exists()) {
      _onDownloadFailed(modelId, modelIndex, model, client);
      return;
    }
    
    final downloadedSize = await tempFile.length();
    if (downloadedSize < model.size * 0.95) {
      await tempFile.delete();
      _onDownloadFailed(modelId, modelIndex, model, client);
      return;
    }
    
    try {
      _checksumSinks[modelId]?.close();
      final digest = _checksumOutputs[modelId]?.events.single;
      if (digest != null) {
        await llmService.saveModelChecksum(modelId, digest.toString());
      }
    } catch (_) {}
    
    _cleanupChecksumResources(modelId);
    
    try {
      await tempFile.rename(finalFile.path);
    } catch (_) {
      await tempFile.openRead().pipe(finalFile.openWrite());
      await tempFile.delete();
    }
    
    if (! await finalFile.exists()) {
      _onDownloadFailed(modelId, modelIndex, model, client);
      return;
    }
    
    _models[modelIndex] = model.copyWith(
      status: ModelStatus.downloaded,
      downloadProgress: 1.0,
    );
    _downloadSubscriptions. remove(modelId);
    client?.close();
    notifyListeners();
  }
  
  Future<void> _handleDownloadError(
    String modelId,
    int modelIndex,
    LlmModel model,
    IOSink? sink,
    File tempFile,
    http. Client? client,
    dynamic error,
  ) async {
    debugPrint('Download error: $error');
    await sink?.close();
    _cleanupChecksumResources(modelId);
    if (await tempFile. exists()) await tempFile.delete();
    _onDownloadFailed(modelId, modelIndex, model, client);
  }
  
  void _onDownloadFailed(
    String modelId,
    int modelIndex,
    LlmModel model,
    http.Client?  client,
  ) {
    _cleanupChecksumResources(modelId);
    _models[modelIndex] = model.copyWith(status: ModelStatus.error);
    _downloadSubscriptions.remove(modelId);
    client?.close();
    notifyListeners();
  }

  Future<void> cancelDownload(String modelId) async {
    final subscription = _downloadSubscriptions[modelId];
    if (subscription == null) return;
    
    await subscription.cancel();
    _downloadSubscriptions.remove(modelId);
    _cleanupChecksumResources(modelId);

    final modelIndex = _models. indexWhere((m) => m.id == modelId);
    if (modelIndex != -1) {
      final model = _models[modelIndex];
      final modelsDir = await _getModelsDirectory();
      
      final tempFile = File('${modelsDir. path}/${model. id}.tmp');
      final finalFile = File('${modelsDir.path}/${model.id}.bin');
      
      if (await tempFile. exists()) await tempFile.delete();
      if (await finalFile.exists()) await finalFile.delete();
      
      _models[modelIndex] = model.copyWith(
        status: ModelStatus.notDownloaded,
        downloadProgress: 0.0,
      );
      notifyListeners();
    }
  }
  
  Future<void> deleteModel(String modelId) async {
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return;
    
    final model = _models[modelIndex];
    final modelsDir = await _getModelsDirectory();
    
    final modelFile = File('${modelsDir.path}/${model.id}.bin');
    final tempFile = File('${modelsDir. path}/${model. id}.tmp');
    
    if (await modelFile.exists()) await modelFile.delete();
    if (await tempFile. exists()) await tempFile.delete();
    
    await _prefs.remove('checksum_$modelId');
    
    _models[modelIndex] = model. copyWith(
      status: ModelStatus.notDownloaded,
      downloadProgress: 0.0,
    );
    
    if (_activeModelId == modelId) {
      await _clearActiveModel();
    }
    
    notifyListeners();
  }
  
  Future<bool> setActiveModel(String modelId) async {
    if (_activeModelId == modelId && llmService.isModelLoaded) {
      return true;
    }
    
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return false;
    
    final model = _models[modelIndex];

    if (model.status != ModelStatus.downloaded && 
        model.status != ModelStatus.active) {
      return false;
    }
    
    final modelsDir = await _getModelsDirectory();
    final modelFile = File('${modelsDir.path}/${model.id}.bin');
    
    if (!await modelFile.exists()) {
      _models[modelIndex] = model.copyWith(status: ModelStatus.notDownloaded);
      notifyListeners();
      return false;
    }
    
    _models[modelIndex] = model.copyWith(status: ModelStatus.activating);
    _isLoadingModel = true;
    notifyListeners();

    final success = await llmService.loadModel(model);

    if (! success) {
      _models[modelIndex] = model.copyWith(status: ModelStatus.downloaded);
      _isLoadingModel = false;
      notifyListeners();
      return false;
    }

    if (_activeModelId != null && _activeModelId != modelId) {
      final oldIndex = _models.indexWhere((m) => m.id == _activeModelId);
      if (oldIndex != -1) {
        _models[oldIndex] = _models[oldIndex].copyWith(status: ModelStatus.downloaded);
      }
    }
    
    _models[modelIndex] = model.copyWith(status: ModelStatus. active);
    _activeModelId = modelId;
    await _prefs.setString('active_model_id', modelId);
    
    _isLoadingModel = false;
    notifyListeners();
    return true;
  }
  
  Future<bool> verifyModelIntegrity(String modelId) async {
    return await llmService. verifyModelChecksum(modelId);
  }
}

class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  
  @override
  void add(T event) => events.add(event);
  
  @override
  void close() {}
}