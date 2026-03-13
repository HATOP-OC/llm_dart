import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/llm_model.dart';
import '../services/model_manager.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelManager>(
      builder: (context, modelManager, child) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: modelManager.models.length,
          itemBuilder: (context, index) {
            final model = modelManager.models[index];
            return ModelCard(model: model);
          },
        );
      },
    );
  }
}

class ModelCard extends StatelessWidget {
  final LlmModel model;

  const ModelCard({super.key, required this.model});

  IconData _getModelTypeIcon() {
    switch (model.modelType) {
      case ModelType.audioGeneration:
        return Icons.audiotrack;
      case ModelType.imageGeneration:
        return Icons.image;
      case ModelType.text:
        return Icons.model_training;
    }
  }

  Color _getModelTypeColor() {
    if (model.status == ModelStatus.active) return Colors.green;
    switch (model.modelType) {
      case ModelType.audioGeneration:
        return Colors.purple;
      case ModelType.imageGeneration:
        return Colors.orange;
      case ModelType.text:
        return Colors.blue;
    }
  }

  String _getModelTypeLabel() {
    switch (model.modelType) {
      case ModelType.audioGeneration:
        return 'Audio';
      case ModelType.imageGeneration:
        return 'Image';
      case ModelType.text:
        return 'Text';
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getModelTypeIcon(),
                  color: _getModelTypeColor(),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _getSizeString(model.size),
                            style: TextStyle(color: Colors.grey[400], fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getModelTypeColor().withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getModelTypeLabel(),
                              style: TextStyle(
                                color: _getModelTypeColor(),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (model.status == ModelStatus.active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(model.description),
            // Thermal warning for non-text models
            if (model.modelType != ModelType.text) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.thermostat, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thermal-safe: max ${model.maxTokens} tokens per generation to prevent device overheating.',
                        style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Download progress
            if (model.status == ModelStatus.downloading ||
                model.status == ModelStatus.finalizing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: model.downloadProgress,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.status == ModelStatus.downloading
                        ? 'Downloading: ${(model.downloadProgress * 100).toInt()}%'
                        : 'Finalizing...',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (model.status == ModelStatus.downloaded ||
                    model.status == ModelStatus.active)
                  OutlinedButton(
                    onPressed: () async {
                      await modelManager.deleteModel(model.id);
                    },
                    child: const Text('Delete'),
                  ),
                const SizedBox(width: 8),
                if (model.status == ModelStatus.notDownloaded ||
                    model.status == ModelStatus.error)
                  ElevatedButton(
                    onPressed: () async {
                      await modelManager.downloadModel(model.id);
                    },
                    child: const Text('Download'),
                  ),
                if (model.status == ModelStatus.downloading)
                  ElevatedButton(
                    onPressed: () async {
                      await modelManager.cancelDownload(model.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Cancel'),
                  ),
                if (model.status == ModelStatus.finalizing)
                  const ElevatedButton(
                    onPressed: null,
                    child: Text('Finalizing...'),
                  ),
                if (model.status == ModelStatus.activating)
                  const ElevatedButton(
                    onPressed: null,
                    child: Text('Activating...'),
                  ),
                if (model.status == ModelStatus.downloaded)
                  ElevatedButton(
                    onPressed: () async {
                      await modelManager.setActiveModel(model.id);
                    },
                    child: const Text('Activate'),
                  ),
                if (model.status == ModelStatus.active)
                  const ElevatedButton(onPressed: null, child: Text('Active')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getSizeString(int sizeInBytes) {
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else if (sizeInBytes < 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
