import 'package:flutter/services.dart';

class DetectionBoxData {
  const DetectionBoxData({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    required this.confidence,
    required this.classId,
    this.locked = false,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String label;
  final double confidence;
  final int classId;
  final bool locked;

  factory DetectionBoxData.fromMap(Map<Object?, Object?> map) {
    return DetectionBoxData(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 0,
      label: (map['label'] as String?) ?? 'object',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      classId: (map['classId'] as num?)?.toInt() ?? -1,
      locked: map['locked'] == true,
    );
  }
}

class DetectorStatus {
  const DetectorStatus({
    required this.ok,
    required this.nativeAvailable,
    required this.status,
    this.modelPresent = false,
    this.metadataPresent = false,
    this.backend,
    this.inferenceMs,
    this.outputCount,
    this.modelSizeBytes,
    this.detections = const [],
    this.detectionsSource,
    this.error,
  });

  final bool ok;
  final bool nativeAvailable;
  final String status;
  final bool modelPresent;
  final bool metadataPresent;
  final String? backend;
  final double? inferenceMs;
  final int? outputCount;
  final int? modelSizeBytes;
  final List<DetectionBoxData> detections;
  final String? detectionsSource;
  final String? error;

  bool get modelReady => nativeAvailable && modelPresent;
  bool get hasDetections => detections.isNotEmpty;

  String get shortLabel {
    if (!nativeAvailable) return 'Native: OFF';
    if (!modelPresent) return 'Model: Missing';
    if (inferenceMs != null) return '${inferenceMs!.toStringAsFixed(1)} ms';
    return 'Model: Ready';
  }

  factory DetectorStatus.fromMap(Map<Object?, Object?> map) {
    final rawDetections = map['detections'];
    final detections = rawDetections is List
        ? rawDetections
            .whereType<Map<Object?, Object?>>()
            .map(DetectionBoxData.fromMap)
            .toList(growable: false)
        : const <DetectionBoxData>[];

    return DetectorStatus(
      ok: map['ok'] == true,
      nativeAvailable: true,
      status: (map['status'] as String?) ?? 'ready',
      modelPresent: map['modelPresent'] == true,
      metadataPresent: map['metadataPresent'] == true,
      backend: map['backend'] as String?,
      inferenceMs: (map['inferenceMs'] as num?)?.toDouble(),
      outputCount: (map['outputCount'] as num?)?.toInt(),
      modelSizeBytes: (map['modelSizeBytes'] as num?)?.toInt(),
      detections: detections,
      detectionsSource: map['detectionsSource'] as String?,
    );
  }

  factory DetectorStatus.unavailable([String? error]) {
    return DetectorStatus(
      ok: false,
      nativeAvailable: false,
      status: 'native_unavailable',
      error: error,
    );
  }
}

class DetectorBridge {
  const DetectorBridge();

  static const MethodChannel _channel = MethodChannel('pocket_coach/detector');

  Future<DetectorStatus> startLiveSession() => _invoke('startLiveSession');
  Future<DetectorStatus> detectFrame({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int timestampMicros,
  }) {
    return _invoke(
      'detectFrame',
      {
        'bytes': bytes,
        'width': width,
        'height': height,
        'bytesPerRow': bytesPerRow,
        'timestampMicros': timestampMicros,
      },
    );
  }

  Future<DetectorStatus> stopLiveSession() => _invoke('stopLiveSession');
  Future<DetectorStatus> lockTarget() => _invoke('lockTarget');
  Future<DetectorStatus> runCalibration() => _invoke('runCalibration');
  Future<DetectorStatus> servoTest() => _invoke('servoTest');
  Future<DetectorStatus> getDetectorStatus() => _invoke('getDetectorStatus');

  Future<DetectorStatus> _invoke(
    String method, [
    Object? arguments,
  ]) async {
    try {
      final payload = await _channel.invokeMethod<Object?>(method, arguments);
      if (payload is Map<Object?, Object?>) {
        return DetectorStatus.fromMap(payload);
      }
      return const DetectorStatus(
        ok: true,
        nativeAvailable: true,
        status: 'ok',
      );
    } on MissingPluginException {
      return DetectorStatus.unavailable('Missing native detector plugin');
    } on PlatformException catch (error) {
      return DetectorStatus.unavailable(error.message ?? error.code);
    }
  }
}
