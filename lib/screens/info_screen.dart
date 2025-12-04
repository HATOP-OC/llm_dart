import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/llm_model.dart';
import '../services/model_manager.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super. key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade900,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.psychology,
                    size: 60,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Local LLM Chat',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight. bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Version 1.0. 0',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors. grey.shade400,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius. circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize. min,
                    children: [
                      Icon(Icons.code, size: 18, color: Colors. blue. shade300),
                      const SizedBox(width: 8),
                      const Text(
                        'Developed by HATOP-OC',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight. w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Card(
            child: Padding(
              padding: EdgeInsets. all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About the App',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Local LLM Chat is an application for communicating with large language models (LLMs) locally on your device, without sending data to the internet.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The application uses optimized models that run entirely on your device, ensuring privacy and the ability to use it without an internet connection.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How It Works',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTile(
                    Icons.memory,
                    'On-Device Processing',
                    'All AI computations happen locally on your phone\'s CPU',
                  ),
                  _buildInfoTile(
                    Icons. compress,
                    'Quantization',
                    'Models are compressed 4-8x smaller while maintaining quality',
                  ),
                  _buildInfoTile(
                    Icons.storage,
                    'Local Storage',
                    'Chats stored in SQLite, models in app documents',
                  ),
                  _buildInfoTile(
                    Icons.speed,
                    'Optimized Inference',
                    'Using llama.cpp for efficient token generation',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Models',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<ModelManager>(
                    builder: (context, modelManager, child) {
                      return Column(
                        children: modelManager.models.map((model) {
                          return ListTile(
                            leading: const Icon(Icons.model_training),
                            title: Text(model.name),
                            subtitle: Text(
                              model.description,
                              style: TextStyle(color: Colors.grey. shade400),
                            ),
                            trailing: _getModelStatusIcon(model.status),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets. all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment. start,
                children: [
                  const Text(
                    'Technologies',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTile(
                    Icons.flutter_dash,
                    'Flutter',
                    'Cross-platform framework for mobile apps',
                  ),
                  _buildInfoTile(
                    Icons.code,
                    'llama.cpp',
                    'C++ library for running LLMs on limited resources',
                  ),
                  _buildInfoTile(
                    Icons. developer_board,
                    'Dart FFI',
                    'Foreign Function Interface for native code',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: InkWell(
              onTap: () {
                Clipboard.setData(
                  const ClipboardData(text: 'https://github.com/HATOP-OC/llm_dart'),
                );
                ScaffoldMessenger. of(context).showSnackBar(
                  const SnackBar(content: Text('GitHub link copied to clipboard')),
                );
              },
              borderRadius: BorderRadius. circular(12),
              child: Padding(
                padding: const EdgeInsets. all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.open_in_new, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GitHub Repository',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight. bold,
                            ),
                          ),
                          Text(
                            'Tap to copy link',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy, color: Colors. grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'License',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'This application is distributed under the MIT license.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    '© 2024 HATOP-OC. All rights reserved.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _buildInfoTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets. all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius. circular(10),
            ),
            child: Icon(icon, color: Colors.blue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight. w600),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _getModelStatusIcon(ModelStatus status) {
    switch (status) {
      case ModelStatus.active:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ModelStatus. downloaded:
        return const Icon(Icons.download_done, color: Colors. blue);
      case ModelStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ModelStatus.activating:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
        );
      case ModelStatus. finalizing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
        );
      case ModelStatus. notDownloaded:
        return const Icon(Icons.download, color: Colors.grey);
      case ModelStatus.error:
        return const Icon(Icons.error, color: Colors.red);
    }
  }
}