import 'package:flutter/material.dart';

import '../detection/detector_bridge.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/camera_feed.dart';
import 'camera_screen.dart';
import 'device_status_screen.dart';
import 'home_screen.dart';
import 'recent_videos_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _bridge = const DetectorBridge();
  int _currentIndex = 0;
  bool _trackingActive = false;
  bool _trackingBusy = false;
  bool _frameBusy = false;
  DetectorStatus _detectorStatus = DetectorStatus.unavailable();

  Future<void> _startModelTracking() async {
    if (_trackingBusy) return;

    setState(() {
      _trackingActive = true;
      _trackingBusy = true;
      _currentIndex = 3;
    });
    final status = await _bridge.startLiveSession();
    if (!mounted) return;

    setState(() {
      _trackingBusy = false;
      _detectorStatus = status;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status.modelReady
              ? 'Model executed: ${status.shortLabel}'
              : status.shortLabel,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleCameraFrame(CameraFrameSample frame) async {
    if (!_trackingActive || _frameBusy) return;

    _frameBusy = true;
    final status = await _bridge.detectFrame(
      bytes: frame.bytes,
      width: frame.width,
      height: frame.height,
      bytesPerRow: frame.bytesPerRow,
      timestampMicros: frame.timestampMicros,
    );

    if (mounted) {
      setState(() => _detectorStatus = status);
    }
    _frameBusy = false;
  }

  void _setTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index != 3) {
        _trackingActive = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onStartTracking: _startModelTracking,
        onOpenDevices: () => _setTab(1),
        onOpenRecords: () => _setTab(2),
        onOpenCamera: () => _setTab(3),
        trackingBusy: _trackingBusy,
        detectorStatus: _detectorStatus,
      ),
      DeviceStatusScreen(onBack: () => _setTab(0)),
      RecentVideosScreen(onBack: () => _setTab(0)),
      CameraScreen(
        onStartTracking: _startModelTracking,
        onCameraFrame: _handleCameraFrame,
        trackingActive: _trackingActive,
        trackingBusy: _trackingBusy,
        detectorStatus: _detectorStatus,
      ),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onChanged: _setTab,
      ),
    );
  }
}
