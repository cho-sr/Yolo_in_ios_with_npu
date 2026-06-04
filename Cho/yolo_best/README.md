# yolo_best

This folder is a copy of `Cho/yolo_fix` prepared for the repo-root `best.pt` model.
The iOS app loads `detector.pte` through ExecuTorch with the CoreML delegate, targeting CPU plus Apple Neural Engine.

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
Cho/yolo_best/best_pt/best_pt/test_images/
```

Then add:

```text
test_1.jpg
test_2.jpg
test_3.jpg
```

The `Test Image` screen also checks for `test_1.jpg` through `test_3.jpg` at the bundle root.
If a file is missing, the app shows `test_1.jpg missing` instead of crashing.

## Export best.pt For iPhone

Run this from the repo root after installing the export dependencies:

```sh
python3 Cho/yolo_best/tools/export_yolo_executorch.py
```

The default export contract is:

```text
weights: best.pt
backend: ExecuTorch CoreML delegate
CoreML compute unit: cpu_and_ne
target: iOS18
precision: float16
input: [1, 3, 576, 1024]
bundle output: Cho/yolo_best/best_pt/best_pt/detector.pte
```

Only use `--activation relu` if the `.pt` file was specifically fine-tuned after replacing SiLU with ReLU.
If the Neural Engine path fails for a specific model op, retry with `--coreml-compute-unit all`.

## Model Input Size

The app view controllers currently use the 16:9 model contract:

```swift
DetectorPipeline(configuration: .highResolution1024x576)
```

That means:

```text
input: [1, 3, 576, 1024]
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
