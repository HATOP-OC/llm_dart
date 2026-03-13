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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showAddCustomModelDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Custom Model'),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: modelManager.models.length,
                itemBuilder: (context, index) {
                  final model = modelManager.models[index];
                  return ModelCard(model: model);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddCustomModelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddCustomModelDialog(),
    );
  }
}

class AddCustomModelDialog extends StatefulWidget {
  const AddCustomModelDialog({super.key});

  @override
  State<AddCustomModelDialog> createState() => _AddCustomModelDialogState();
}

class _AddCustomModelDialogState extends State<AddCustomModelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sizeController = TextEditingController();
  QuantizationType _quantization = QuantizationType.bit4;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Custom Model'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Model Name',
                  hintText: 'e.g. My Custom Model',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'GGUF Download URL',
                  hintText: 'https://huggingface.co/.../model.gguf',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final uri = Uri.tryParse(v);
                  if (uri == null || !uri.hasScheme) {
                    return 'Enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Short description of the model',
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _sizeController,
                decoration: const InputDecoration(
                  labelText: 'File Size (MB)',
                  hintText: 'e.g. 2400',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = int.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<QuantizationType>(
                value: _quantization,
                decoration: const InputDecoration(
                  labelText: 'Quantization',
                ),
                items: const [
                  DropdownMenuItem(
                    value: QuantizationType.bit4,
                    child: Text('4-bit'),
                  ),
                  DropdownMenuItem(
                    value: QuantizationType.bit8,
                    child: Text('8-bit'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _quantization = v);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            
            final modelManager =
                Provider.of<ModelManager>(context, listen: false);
            final sizeMb = int.parse(_sizeController.text);
            
            await modelManager.addCustomModel(
              name: _nameController.text.trim(),
              url: _urlController.text.trim(),
              description: _descriptionController.text.trim(),
              size: sizeMb * 1000000,
              quantization: _quantization,
            );
            
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class ModelCard extends StatelessWidget {
  final LlmModel model;

  const ModelCard({super.key, required this.model});

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
                  Icons.model_training,
                  color: model.status == ModelStatus.active
                      ? Colors.green
                      : Colors.blue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (model.isUserAdded) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Custom',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _getSizeString(model.size),
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
                if (model.isUserAdded &&
                    model.status == ModelStatus.notDownloaded)
                  OutlinedButton(
                    onPressed: () async {
                      await modelManager.removeCustomModel(model.id);
                    },
                    child: const Text('Remove'),
                  ),
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
