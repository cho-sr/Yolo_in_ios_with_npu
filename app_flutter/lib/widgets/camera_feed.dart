import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CameraFrameSample {
  const CameraFrameSample({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.timestampMicros,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int timestampMicros;
}

class CameraFeed extends StatefulWidget {
  const CameraFeed({
    super.key,
    this.onFrame,
  });

  final ValueChanged<CameraFrameSample>? onFrame;

  @override
  State<CameraFeed> createState() => _CameraFeedState();
}

class _CameraFeedState extends State<CameraFeed> {
  static const _frameInterval = Duration(milliseconds: 250);

  CameraController? _controller;
  String? _error;
  DateTime? _lastFrameSentAt;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onFrame != widget.onFrame) {
      _syncImageStream();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Camera unavailable');
        return;
      }

      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() => _controller = controller);
      await _syncImageStream();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Camera permission needed');
      }
    }
  }

  Future<void> _syncImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final shouldStream = widget.onFrame != null;
    final isStreaming = controller.value.isStreamingImages;

    if (shouldStream && !isStreaming) {
      try {
        await controller.startImageStream(_handleCameraImage);
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'Camera stream unavailable');
        }
      }
    } else if (!shouldStream && isStreaming) {
      await controller.stopImageStream();
      _lastFrameSentAt = null;
    }
  }

  void _handleCameraImage(CameraImage image) {
    final onFrame = widget.onFrame;
    if (onFrame == null || image.planes.isEmpty) return;
    if (image.format.group != ImageFormatGroup.bgra8888) return;

    final now = DateTime.now();
    final lastFrameSentAt = _lastFrameSentAt;
    if (lastFrameSentAt != null &&
        now.difference(lastFrameSentAt) < _frameInterval) {
      return;
    }

    _lastFrameSentAt = now;
    final plane = image.planes.first;
    onFrame(
      CameraFrameSample(
        bytes: Uint8List.fromList(plane.bytes),
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        timestampMicros: now.microsecondsSinceEpoch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _CameraPlaceholder(error: _error);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) {
          return CameraPreview(controller);
        }

        final previewAspectRatio = previewSize.height / previewSize.width;
        final widgetAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final scale = previewAspectRatio / widgetAspectRatio;

        return ClipRect(
          child: Transform.scale(
            scale: scale < 1 ? 1 / scale : scale,
            child: Center(
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.black),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_camera_outlined,
              color: AppColors.muted,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              error ?? 'Starting camera',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
