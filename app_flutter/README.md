# Pocket Coach Flutter UI

Shared Flutter UI for the Pocket Coach tracking app. The current iOS path is wired to an on-device ExecuTorch YOLO model, while non-iOS targets still use the same Flutter screens with the native bridge unavailable.

## Screens

- Home dashboard with detector readiness and session entry
- Camera preview screen with optional live bounding-box overlay
- Landscape live tracking view with camera preview, detector status, and controls
- Device status and calibration controls
- Recent videos list

## Native Detector Bridge

Flutter calls the native detector through:

```text
pocket_coach/detector
```

Current method channel API:

```text
startLiveSession
detectFrame
stopLiveSession
lockTarget
runCalibration
servoTest
getDetectorStatus
```

`startLiveSession` warms the model with a zero tensor. `detectFrame` sends throttled BGRA camera frames from Flutter to the iOS native bridge and returns normalized detections for the overlay. If the native plugin is missing, the UI stays usable and reports `Native: OFF`.

## iOS ExecuTorch Model

The iOS Runner bundles:

```text
ios/Runner/detector.pte
ios/Runner/metadata.yaml
```

Current iOS model contract:

```text
backend: ExecuTorch CoreML delegate
input: [1, 3, 576, 1024]
raw output: YOLO 80-class COCO format
displayed class: person
confidence threshold: 0.40
NMS IoU threshold: 0.45
```

The bundled metadata currently describes a YOLO26n COCO export with ReLU activation override. The Flutter overlay only displays class `0` (`person`) even though the raw model output has 80 COCO classes.

## Camera Flow

`CameraFeed` uses the `camera` package and selects the back camera when available. Frames are streamed only when tracking is active, limited to roughly one frame every 250 ms, and sent to native code as BGRA data:

```text
bytes
width
height
bytesPerRow
timestampMicros
```

The iOS bridge letterboxes each frame to `1024x576`, runs ExecuTorch inference, restores boxes back to the original frame coordinates, and returns normalized rectangles to Flutter.

## Run

Flutter SDK is configured at:

```text
/Users/joseoglae/flutter
```

Install dependencies and run tests:

```bash
cd app_flutter
flutter pub get
flutter test
```

Run a quick UI preview in Chrome:

```bash
cd app_flutter
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5500
```

Run on iOS after a simulator or device is available:

```bash
cd app_flutter
flutter devices
flutter run -d <ios-device-id>
```

For a build that can be opened from the iPhone home screen without Flutter tooling attached:

```bash
cd app_flutter
flutter run --release -d <ios-device-id>
```

Android can implement the same method channel API later while keeping the Flutter UI unchanged.
