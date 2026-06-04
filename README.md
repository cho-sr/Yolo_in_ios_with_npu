# Yolo in iOS with NPU

This repo contains the iOS and Flutter experiments for running YOLO through ExecuTorch/CoreML on-device.

## Folders

- `Cho/yolo_fix`: standalone iOS app using the original non-ReLU `yolo26n.pt` COCO export, filtered to `person`.
- `Cho/yolo_best`: standalone iOS app prepared for repo-root `best.pt`, exported as a one-class `player` model with CoreML `cpu_and_ne`.
- `Cho/yolo_bytetrack`: ByteTrack-oriented iOS experiment.
- `app_flutter`: shared Pocket Coach Flutter UI with an iOS native ExecuTorch detector bridge.
- `trained_models`: tracked training metadata and selected `.pt` weights.

Generated ExecuTorch `.pte` files are ignored by git. Re-export the required model locally before building an app that depends on a missing `detector.pte`.

## Quick Commands

Open the pretrained `yolo_fix` iOS app:

```sh
open Cho/yolo_fix/yolo_fix/yolo_fix.xcodeproj
```

Open the `best.pt` iOS app:

```sh
open Cho/yolo_best/best_pt/best_pt.xcodeproj
```

Run Flutter tests:

```sh
cd app_flutter
flutter test
```
