# yolo_fix

This folder contains the standalone `yolo_fix` iOS app and the drop-in test UI files for `Cho/final/ios/RealtimeDetectionMVP`.

The current app is back on the original non-ReLU pretrained path:

```text
weights source: yolo26n.pt
dataset/classes: COCO 80-class
displayed class: person
activation override: none
input: [1, 3, 576, 1024]
backend: ExecuTorch CoreML delegate
CoreML compute unit: all
target: iOS18
precision: float16
```

`detector.pte` is generated locally and ignored by git. The tracked `metadata.yaml` documents the current export contract.

## What This Adds

- A new root screen with three buttons:
  - `Detect`: show the camera, then run one detection on the latest frame.
  - `Test Image`: run detection on bundled `test_1.jpg`, `test_2.jpg`, and `test_3.jpg`.
  - `Live`: run live model detection and show bbox, FPS, and inference time.
- Shared `DetectorPipeline` for:
  - letterbox preprocessing
  - ExecuTorch inference
  - letterbox-aware bbox restoration
- No tracker, deadzone, or USB MIDI in `Live`.

## Apply To The App

Copy these files into `Cho/final/ios/RealtimeDetectionMVP`:

- `DetectionMode.swift`
- `DetectionResultView.swift`
- `DetectorPipeline.swift`
- `LiveDetectionViewController.swift`
- `ModeSelectionView.swift`
- `StillDetectionViewController.swift`

Replace these existing app files with the versions from this folder:

- `Models.swift`
- `FramePreprocessor.swift`
- `DetectionPostProcessor.swift`
- `RealtimeDetectionMVPApp.swift`

Keep the existing app files below:

- `CameraService.swift`
- `ExecuTorchRunner.swift`
- `OverlayView.swift`
- `SimpleTracker.swift`
- `TrackingControl.swift`
- `USBMIDIServoOutput.swift`

`DetectionViewController.swift` can remain in the target. The new root screen does not route to it.

## Test Images

Create this folder in the app bundle source directory:

```text
Cho/yolo_fix/yolo_fix/yolo_fix/test_images/
```

Then add:

```text
test_1.jpg
test_2.jpg
test_3.jpg
```

The `Test Image` screen also checks for `test_1.jpg` through `test_3.jpg` at the bundle root.
If a file is missing, the app shows `test_1.jpg missing` instead of crashing.

## Export The Current Model

Run this from the repo root with the `study` environment:

```sh
conda run -n study python Cho/yolo_fix/tools/export_yolo_executorch.py \
  --weights yolo26n.pt \
  --imgsz 1024 576 \
  --activation original \
  --coreml-compute-unit all \
  --coreml-target iOS18 \
  --coreml-precision float16
```

The script writes:

```text
Cho/yolo_fix/yolo_fix/yolo_fix/detector.pte
Cho/yolo_fix/yolo_fix/yolo_fix/metadata.yaml
```

## Model Input Size

The app view controllers currently use the 16:9 model contract:

```swift
DetectorPipeline(configuration: .highResolution1024x576)
```

That means:

```text
input: [1, 3, 576, 1024]
```

The postprocessor expects the raw pretrained COCO output shape and filters person only:

```swift
classNames: ["person"]
rawModelClassCount: 80
sourceClassMap: [0: 0]
```

## Letterbox Behavior

The preprocessor keeps aspect ratio and pads with YOLO-style gray `114`.

Examples:

```text
1280x720 -> 640x640 model
scale 0.5
image 640x360
padX 0
padY 140
```

```text
1280x720 -> 1024x576 model
scale 0.8
image 1024x576
padX 0
padY 0
```

The postprocessor subtracts padding and divides by scale before returning normalized bbox rects.
