
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/llm_model.dart';
import 'llm_service.dart';

class ModelManager extends ChangeNotifier {
  final LlmService llmService;
  List<LlmModel> _models = [];
  String? _activeModelId;
  late SharedPreferences _prefs;
  final Map<String, StreamSubscription> _downloadSubscriptions = {};

  ModelManager({required this.llmService});
  
  List<LlmModel> get models => _models;
  
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
    
    // Add pre-defined models
    _models = [
      LlmModel(
        id: 'gemma-3n-E2B-it-Q4_K_M',
        name: 'Gemma 3n E2B It (4-bit)',
        description: 'A 3rd generation, lightweight, state-of-the-art open model from Google.',
        url: 'https://huggingface.co/unsloth/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q4_K_M.gguf?download=true',
        size: 3030000000, // ~3.03 GB
        quantization: QuantizationType.bit4,
      ),
      LlmModel(
        id: 'phi-3-mini-4k-instruct-q4',
        name: 'Phi-3 Mini Instruct (4-bit)',
        description: 'A 3.8B parameter, lightweight, state-of-the-art open model from Microsoft.',
        url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf?download=true',
        size: 2390000000, // ~2.39 GB
        quantization: QuantizationType.bit4,
      ),
      LlmModel(
       id: 'llama-3.2-1b-instruct-q4_k_m',
       name: 'Llama 3.2 1B Instruct (Q4_K_M)',
       description: 'Compact 1B model from Meta. Good balance for testing.',
       url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true',
       size: 670000000, // ~670 MB
       quantization: QuantizationType.bit4,
      ),
      LlmModel(
        id: 'tiny-llm-q5_k_m',
        name: 'TinyLLM (Q5_K_M)',
        description: 'A very small model for testing purposes.',
        url: 'https://huggingface.co/aimlresearch2023/Tiny-LLM-Q5_K_M-GGUF/resolve/main/tiny-llm-q5_k_m.gguf?download=true',
        size: 12400000, // ~12.4 MB
        quantization: QuantizationType.bit4,
      ),
    ];
    
    // Check which models are already downloaded
    await _checkDownloadedModels();
  }
  
  Future<void> _checkDownloadedModels() async {
    final modelsDir = await _getModelsDirectory();
    
    for (int i = 0; i < _models.length; i++) {
      final model = _models[i];
      final modelFile = File('${modelsDir.path}/${model.id}.bin');
      
      if (await modelFile.exists()) {
        _models[i] = model.copyWith(
          status: model.id == _activeModelId 
            ? ModelStatus.active 
            : ModelStatus.downloaded
        );
      }
    }
    
    notifyListeners();
  }
  
  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    
    return modelsDir;
  }
  
  Future<void> downloadModel(String modelId) async {
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return;
    
    final model = _models[modelIndex];
    final modelsDir = await _getModelsDirectory();
    final modelFile = File('${modelsDir.path}/${model.id}.bin');
    
    // Update model status to "downloading"
    _models[modelIndex] = model.copyWith(
      status: ModelStatus.downloading,
      downloadProgress: 0.0,
    );
    notifyListeners();
    
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(model.url));
      final response = await client.send(request);
      
      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        final sink = modelFile.openWrite();
        int received = 0;
        
        _downloadSubscriptions[modelId] = response.stream.listen(
          (chunk) {
            sink.add(chunk);
            received += chunk.length;
            
            if (contentLength > 0) {
              final progress = received / contentLength;
              _models[modelIndex] = model.copyWith(
                status: ModelStatus.downloading,
                downloadProgress: progress,
              );
              notifyListeners();
            }
          },
          onDone: () async {
            _models[modelIndex] = model.copyWith(
              status: ModelStatus.finalizing,
              downloadProgress: 1.0,
            );
            notifyListeners();

            await sink.close();

            _models[modelIndex] = model.copyWith(
              status: ModelStatus.downloaded,
              downloadProgress: 1.0,
            );
            _downloadSubscriptions.remove(modelId);
            notifyListeners();
          },
          onError: (_) async {
            await sink.close();
            await modelFile.delete();
            _models[modelIndex] = model.copyWith(
              status: ModelStatus.error,
            );
            _downloadSubscriptions.remove(modelId);
            notifyListeners();
          },
          cancelOnError: true,
        );
      } else {
        _models[modelIndex] = model.copyWith(
          status: ModelStatus.error,
        );
        notifyListeners();
      }
    } catch (e) {
      _models[modelIndex] = model.copyWith(
        status: ModelStatus.error,
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelDownload(String modelId) async {
    final subscription = _downloadSubscriptions[modelId];
    if (subscription != null) {
      await subscription.cancel();
      _downloadSubscriptions.remove(modelId);

      // Clean up partial file
      final modelIndex = _models.indexWhere((m) => m.id == modelId);
      if (modelIndex != -1) {
        final model = _models[modelIndex];
        final modelsDir = await _getModelsDirectory();
        final modelFile = File('${modelsDir.path}/${model.id}.bin');
        if (await modelFile.exists()) {
          await modelFile.delete();
        }
        _models[modelIndex] = model.copyWith(
          status: ModelStatus.notDownloaded,
          downloadProgress: 0.0,
        );
        notifyListeners();
      }
    }
  }
  
  Future<void> deleteModel(String modelId) async {
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return;
    
    final model = _models[modelIndex];
    final modelsDir = await _getModelsDirectory();
    final modelFile = File('${modelsDir.path}/${model.id}.bin');
    
    if (await modelFile.exists()) {
      await modelFile.delete();
    }
    
    _models[modelIndex] = model.copyWith(
      status: ModelStatus.notDownloaded,
      downloadProgress: 0.0,
    );
    
    if (_activeModelId == modelId) {
      _activeModelId = null;
      await _prefs.remove('active_model_id');
    }
    
    notifyListeners();
  }
  
  Future<bool> setActiveModel(String modelId) async {
    if (_activeModelId == modelId) return true;
    
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return false;
    
    final model = _models[modelIndex];

    // Check if the model is downloaded
    if (model.status != ModelStatus.downloaded) {
      return false;
    }
    
    // Set status to activating
    _models[modelIndex] = model.copyWith(status: ModelStatus.activating);
    notifyListeners();

    // Load the model into the LLM service
    final success = await llmService.loadModel(model);

    if (!success) {
      // If loading fails, revert status to downloaded
      _models[modelIndex] = model.copyWith(status: ModelStatus.downloaded);
      notifyListeners();
      return false;
    }

    // Update the previous active model
    if (_activeModelId != null) {
      final oldActiveIndex = _models.indexWhere((m) => m.id == _activeModelId);
      if (oldActiveIndex != -1) {
        _models[oldActiveIndex] = _models[oldActiveIndex].copyWith(
          status: ModelStatus.downloaded,
        );
      }
    }
    
    // Set the new active model
    _models[modelIndex] = model.copyWith(status: ModelStatus.active);
    _activeModelId = modelId;
    await _prefs.setString('active_model_id', modelId);
    
    notifyListeners();
    return true;
  }
  
  Future<void> updateModelQuantization(String modelId, QuantizationType quantization) async {
    final modelIndex = _models.indexWhere((m) => m.id == modelId);
    if (modelIndex == -1) return;
    
    _models[modelIndex] = _models[modelIndex].copyWith(
      quantization: quantization,
    );
    
    notifyListeners();
  }
}
