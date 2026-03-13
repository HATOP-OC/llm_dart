enum ModelStatus {
  notDownloaded,
  downloading,
  finalizing,
  downloaded,
  activating,
  active,
  error,
}

enum QuantizationType {
  bit4,
  bit8,
}

class LlmModel {
  final String id;
  final String name;
  final String description;
  final String url;
  final int size; // in bytes
  final ModelStatus status;
  final double downloadProgress;
  final QuantizationType quantization;
  final bool isUserAdded;

  LlmModel({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.size,
    this.status = ModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.quantization = QuantizationType.bit4,
    this.isUserAdded = false,
  });

  LlmModel copyWith({
    String? id,
    String? name,
    String? description,
    String? url,
    int? size,
    ModelStatus? status,
    double? downloadProgress,
    QuantizationType? quantization,
    bool? isUserAdded,
  }) {
    return LlmModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      url: url ?? this.url,
      size: size ?? this.size,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      quantization: quantization ?? this.quantization,
      isUserAdded: isUserAdded ?? this.isUserAdded,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'url': url,
      'size': size,
      'status': status.index,
      'quantization': quantization.index,
      'isUserAdded': isUserAdded,
    };
  }

  factory LlmModel.fromMap(Map<String, dynamic> map) {
    return LlmModel(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      url: map['url'],
      size: map['size'],
      status: ModelStatus.values[map['status']],
      quantization: QuantizationType.values[map['quantization']],
      isUserAdded: map['isUserAdded'] ?? false,
    );
  }
}