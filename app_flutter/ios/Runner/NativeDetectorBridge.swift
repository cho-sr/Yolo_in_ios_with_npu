import CoreGraphics
import ExecuTorch
import Flutter
import Foundation
import QuartzCore

enum NativeDetectorError: Error {
  case modelNotFound
  case invalidOutput
  case invalidFrame
}

final class NativeDetectorBridge: NSObject {
  private let queue = DispatchQueue(label: "app.pocketcoach.detector", qos: .userInitiated)
  private let framePreprocessor = NativeFramePreprocessor(inputWidth: 1024, inputHeight: 576)
  private let postProcessor = NativeDetectionPostProcessor(
    confidenceThreshold: 0.40,
    nmsIoUThreshold: 0.45,
    classNames: ["person"],
    rawModelClassCount: 80,
    sourceClassMap: [0: 0]
  )
  private var runner: NativeExecuTorchRunner?

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = NativeDetectorBridge()
    let channel = FlutterMethodChannel(
      name: "pocket_coach/detector",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      bridge.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startLiveSession":
      warmup(result: result)
    case "detectFrame":
      detectFrame(arguments: call.arguments, result: result)
    case "stopLiveSession":
      result(["ok": true, "status": "stopped"])
    case "lockTarget":
      result(["ok": true, "status": "lock_toggled"])
    case "runCalibration":
      result(["ok": true, "status": "calibration_stub"])
    case "servoTest":
      result(["ok": true, "status": "servo_test_stub"])
    case "getDetectorStatus":
      result(statusPayload())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func warmup(result: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }

      do {
        let runner = try self.getRunner()
        let inputShape = [1, 3, 576, 1024]
        let inputCount = inputShape.reduce(1, *)
        let input = [Float](repeating: 0.0, count: inputCount)
        let start = CACurrentMediaTime()
        let output = try runner.predict(input: input, shape: inputShape)
        let inferenceMs = (CACurrentMediaTime() - start) * 1000.0

        var payload = self.statusPayload()
        payload["ok"] = true
        payload["status"] = "model_warm"
        payload["inputShape"] = inputShape
        payload["inputCount"] = inputCount
        payload["outputCount"] = output.count
        payload["inferenceMs"] = inferenceMs

        DispatchQueue.main.async {
          result(payload)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "detector_warmup_failed",
              message: "\(error)",
              details: self.statusPayload()
            )
          )
        }
      }
    }
  }

  private func detectFrame(arguments: Any?, result: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }

      do {
        guard
          let arguments = arguments as? [String: Any],
          let typedData = arguments["bytes"] as? FlutterStandardTypedData,
          let width = arguments["width"] as? Int,
          let height = arguments["height"] as? Int,
          let bytesPerRow = arguments["bytesPerRow"] as? Int,
          let timestampMicros = arguments["timestampMicros"] as? Int
        else {
          throw NativeDetectorError.invalidFrame
        }

        let framePacket = try self.framePreprocessor.prepareBGRA(
          data: typedData.data,
          width: width,
          height: height,
          bytesPerRow: bytesPerRow,
          timestampSeconds: Double(timestampMicros) / 1_000_000.0
        )
        let runner = try self.getRunner()
        let start = CACurrentMediaTime()
        let output = try runner.predict(input: framePacket.tensorData, shape: framePacket.inputShape)
        let detections = self.postProcessor.parse(
          rawOutput: output,
          letterbox: framePacket.letterbox
        )
        let inferenceMs = (CACurrentMediaTime() - start) * 1000.0

        var payload = self.statusPayload()
        payload["ok"] = true
        payload["status"] = "frame_detected"
        payload["inputShape"] = framePacket.inputShape
        payload["outputCount"] = output.count
        payload["inferenceMs"] = inferenceMs
        payload["detectionsSource"] = "camera_frame"
        payload["detections"] = detections.prefix(20).enumerated().map { index, detection in
          detection.payload(locked: index == 0)
        }

        DispatchQueue.main.async {
          result(payload)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "detector_frame_failed",
              message: "\(error)",
              details: self.statusPayload()
            )
          )
        }
      }
    }
  }

  private func getRunner() throws -> NativeExecuTorchRunner {
    if let runner {
      return runner
    }

    let runner = try NativeExecuTorchRunner(modelName: "detector", fileExtension: "pte")
    self.runner = runner
    return runner
  }

  private func statusPayload() -> [String: Any] {
    let modelPath = Bundle.main.path(forResource: "detector", ofType: "pte")
    let metadataPath = Bundle.main.path(forResource: "metadata", ofType: "yaml")
    let modelSizeBytes = modelPath.flatMap { path in
      try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
    }

    return [
      "modelPresent": modelPath != nil,
      "metadataPresent": metadataPath != nil,
      "modelPath": modelPath ?? NSNull(),
      "metadataPath": metadataPath ?? NSNull(),
      "modelSizeBytes": modelSizeBytes?.intValue ?? 0,
      "backend": "executorch_coreml",
      "inputShape": [1, 3, 576, 1024],
    ]
  }
}

private struct NativeFramePacket {
  let tensorData: [Float]
  let inputShape: [Int]
  let letterbox: NativeLetterboxInfo
}

private struct NativeLetterboxInfo {
  let inputSize: CGSize
  let originalSize: CGSize
  let scale: CGFloat
  let padX: CGFloat
  let padY: CGFloat

  func normalizedOriginalRect(fromModelPixelRect modelRect: CGRect) -> CGRect {
    guard scale > 0, originalSize.width > 0, originalSize.height > 0 else {
      return .zero
    }

    let originalX1 = ((modelRect.minX - padX) / scale).clamped(to: 0.0...originalSize.width)
    let originalY1 = ((modelRect.minY - padY) / scale).clamped(to: 0.0...originalSize.height)
    let originalX2 = ((modelRect.maxX - padX) / scale).clamped(to: 0.0...originalSize.width)
    let originalY2 = ((modelRect.maxY - padY) / scale).clamped(to: 0.0...originalSize.height)

    let normalizedX1 = (originalX1 / originalSize.width).clamped(to: 0.0...1.0)
    let normalizedY1 = (originalY1 / originalSize.height).clamped(to: 0.0...1.0)
    let normalizedX2 = (originalX2 / originalSize.width).clamped(to: 0.0...1.0)
    let normalizedY2 = (originalY2 / originalSize.height).clamped(to: 0.0...1.0)

    return CGRect(
      x: Swift.min(normalizedX1, normalizedX2),
      y: Swift.min(normalizedY1, normalizedY2),
      width: abs(normalizedX2 - normalizedX1),
      height: abs(normalizedY2 - normalizedY1)
    ).clampedToUnit()
  }
}

private final class NativeFramePreprocessor {
  private let inputWidth: Int
  private let inputHeight: Int
  private let paddingValue = Float(114.0 / 255.0)

  init(inputWidth: Int, inputHeight: Int) {
    self.inputWidth = inputWidth
    self.inputHeight = inputHeight
  }

  func prepareBGRA(
    data: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    timestampSeconds: Double
  ) throws -> NativeFramePacket {
    guard width > 0, height > 0, bytesPerRow >= width * 4, !data.isEmpty else {
      throw NativeDetectorError.invalidFrame
    }

    let inputSize = CGSize(width: CGFloat(inputWidth), height: CGFloat(inputHeight))
    let sourceSize = CGSize(width: CGFloat(width), height: CGFloat(height))
    let scale = Swift.min(inputSize.width / sourceSize.width, inputSize.height / sourceSize.height)
    let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let padX = (inputSize.width - scaledSize.width) * 0.5
    let padY = (inputSize.height - scaledSize.height) * 0.5
    let planeSize = inputWidth * inputHeight
    var tensorData = [Float](repeating: paddingValue, count: planeSize * 3)
    var copiedPixels = false

    data.withUnsafeBytes { rawBuffer in
      guard let raw = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return
      }

      for y in 0..<inputHeight {
        let sourceYFloat = (CGFloat(y) - padY) / scale
        guard sourceYFloat >= 0, sourceYFloat < sourceSize.height else { continue }
        let sourceY = Swift.min(height - 1, Swift.max(0, Int(sourceYFloat)))

        for x in 0..<inputWidth {
          let sourceXFloat = (CGFloat(x) - padX) / scale
          guard sourceXFloat >= 0, sourceXFloat < sourceSize.width else { continue }
          let sourceX = Swift.min(width - 1, Swift.max(0, Int(sourceXFloat)))
          let byteOffset = sourceY * bytesPerRow + sourceX * 4
          guard byteOffset + 2 < data.count else { continue }

          let b = Float(raw[byteOffset]) / 255.0
          let g = Float(raw[byteOffset + 1]) / 255.0
          let r = Float(raw[byteOffset + 2]) / 255.0
          let index = y * inputWidth + x

          tensorData[index] = r
          tensorData[planeSize + index] = g
          tensorData[(2 * planeSize) + index] = b
          copiedPixels = true
        }
      }
    }

    guard copiedPixels else {
      throw NativeDetectorError.invalidFrame
    }

    return NativeFramePacket(
      tensorData: tensorData,
      inputShape: [1, 3, inputHeight, inputWidth],
      letterbox: NativeLetterboxInfo(
        inputSize: inputSize,
        originalSize: sourceSize,
        scale: scale,
        padX: padX,
        padY: padY
      )
    )
  }
}

private struct NativeDetection {
  let rect: CGRect
  let confidence: Float
  let classID: Int
  let className: String

  func payload(locked: Bool) -> [String: Any] {
    [
      "x": Double(rect.minX),
      "y": Double(rect.minY),
      "width": Double(rect.width),
      "height": Double(rect.height),
      "label": className,
      "confidence": Double(confidence),
      "classId": classID,
      "locked": locked,
    ]
  }
}

private final class NativeDetectionPostProcessor {
  private let confidenceThreshold: Float
  private let nmsIoUThreshold: CGFloat
  private let classNames: [String]
  private let rawModelClassCount: Int?
  private let sourceClassMap: [Int: Int]

  init(
    confidenceThreshold: Float,
    nmsIoUThreshold: CGFloat,
    classNames: [String],
    rawModelClassCount: Int?,
    sourceClassMap: [Int: Int]
  ) {
    self.confidenceThreshold = confidenceThreshold
    self.nmsIoUThreshold = nmsIoUThreshold
    self.classNames = classNames
    self.rawModelClassCount = rawModelClassCount
    self.sourceClassMap = sourceClassMap
  }

  func parse(rawOutput: [Float], letterbox: NativeLetterboxInfo) -> [NativeDetection] {
    guard rawOutput.count >= 6 else { return [] }

    if let rawModelClassCount {
      let channelCount = 4 + rawModelClassCount
      if rawOutput.count % channelCount == 0 && rawOutput.count >= channelCount {
        return parseUltralyticsChannelMajorOutput(
          rawOutput: rawOutput,
          letterbox: letterbox,
          rawModelClassCount: rawModelClassCount
        )
      }
    }

    return parseFlatOutput(rawOutput: rawOutput, letterbox: letterbox)
  }

  private func parseFlatOutput(
    rawOutput: [Float],
    letterbox: NativeLetterboxInfo
  ) -> [NativeDetection] {
    var detections: [NativeDetection] = []

    for start in stride(from: 0, to: rawOutput.count, by: 6) {
      guard start + 5 < rawOutput.count else { break }

      let score = rawOutput[start + 4]
      if score < confidenceThreshold { continue }

      let sourceClassID = Int(rawOutput[start + 5])
      guard let resolvedClass = resolvedClass(sourceClassID: sourceClassID) else {
        continue
      }

      let rawX1 = CGFloat(rawOutput[start])
      let rawY1 = CGFloat(rawOutput[start + 1])
      let rawX2 = CGFloat(rawOutput[start + 2])
      let rawY2 = CGFloat(rawOutput[start + 3])
      let usesAbsoluteInputPixels = Swift.max(
        Swift.max(abs(rawX1), abs(rawY1)),
        Swift.max(abs(rawX2), abs(rawY2))
      ) > 2.0

      let x1 = usesAbsoluteInputPixels ? rawX1 : rawX1 * letterbox.inputSize.width
      let y1 = usesAbsoluteInputPixels ? rawY1 : rawY1 * letterbox.inputSize.height
      let x2 = usesAbsoluteInputPixels ? rawX2 : rawX2 * letterbox.inputSize.width
      let y2 = usesAbsoluteInputPixels ? rawY2 : rawY2 * letterbox.inputSize.height
      let rect = letterbox.normalizedOriginalRect(
        fromModelPixelRect: CGRect(
          x: Swift.min(x1, x2),
          y: Swift.min(y1, y2),
          width: abs(x2 - x1),
          height: abs(y2 - y1)
        )
      )

      guard rect.width > 0.001, rect.height > 0.001 else { continue }
      detections.append(
        NativeDetection(
          rect: rect,
          confidence: score,
          classID: resolvedClass.localID,
          className: resolvedClass.name
        )
      )
    }

    return applyNMS(to: detections)
  }

  private func parseUltralyticsChannelMajorOutput(
    rawOutput: [Float],
    letterbox: NativeLetterboxInfo,
    rawModelClassCount: Int
  ) -> [NativeDetection] {
    let channelCount = 4 + rawModelClassCount
    let anchorCount = rawOutput.count / channelCount
    let classMap = resolvedSourceClassMap(rawModelClassCount: rawModelClassCount)
    var detections: [NativeDetection] = []

    guard anchorCount > 0, !classMap.isEmpty else { return [] }

    for anchorIndex in 0..<anchorCount {
      var bestScore: Float = 0.0
      var bestLocalClassID: Int?

      for (sourceClassID, localClassID) in classMap {
        let scoreIndex = (4 + sourceClassID) * anchorCount + anchorIndex
        guard scoreIndex < rawOutput.count else { continue }

        let score = rawOutput[scoreIndex]
        if score > bestScore {
          bestScore = score
          bestLocalClassID = localClassID
        }
      }

      guard
        let localClassID = bestLocalClassID,
        bestScore >= confidenceThreshold,
        localClassID >= 0,
        localClassID < classNames.count
      else {
        continue
      }

      let centerX = CGFloat(rawOutput[anchorIndex])
      let centerY = CGFloat(rawOutput[anchorCount + anchorIndex])
      let width = CGFloat(rawOutput[(2 * anchorCount) + anchorIndex])
      let height = CGFloat(rawOutput[(3 * anchorCount) + anchorIndex])
      let rect = normalizedRect(
        centerX: centerX,
        centerY: centerY,
        width: width,
        height: height,
        letterbox: letterbox
      )

      guard rect.width > 0.001, rect.height > 0.001 else { continue }
      detections.append(
        NativeDetection(
          rect: rect,
          confidence: bestScore,
          classID: localClassID,
          className: classNames[localClassID]
        )
      )
    }

    return applyNMS(to: detections)
  }

  private func normalizedRect(
    centerX: CGFloat,
    centerY: CGFloat,
    width: CGFloat,
    height: CGFloat,
    letterbox: NativeLetterboxInfo
  ) -> CGRect {
    let usesAbsoluteInputPixels = Swift.max(
      abs(centerX),
      abs(centerY),
      abs(width),
      abs(height)
    ) > 2.0

    let modelCenterX = usesAbsoluteInputPixels ? centerX : centerX * letterbox.inputSize.width
    let modelCenterY = usesAbsoluteInputPixels ? centerY : centerY * letterbox.inputSize.height
    let modelWidth = usesAbsoluteInputPixels ? width : width * letterbox.inputSize.width
    let modelHeight = usesAbsoluteInputPixels ? height : height * letterbox.inputSize.height

    return letterbox.normalizedOriginalRect(
      fromModelPixelRect: CGRect(
        x: modelCenterX - (modelWidth * 0.5),
        y: modelCenterY - (modelHeight * 0.5),
        width: modelWidth,
        height: modelHeight
      )
    )
  }

  private func resolvedSourceClassMap(rawModelClassCount: Int) -> [Int: Int] {
    if !sourceClassMap.isEmpty {
      return sourceClassMap
    }

    guard rawModelClassCount == classNames.count else { return [:] }
    return Dictionary(uniqueKeysWithValues: classNames.indices.map { ($0, $0) })
  }

  private func resolvedClass(sourceClassID: Int) -> (localID: Int, name: String)? {
    let localClassID = sourceClassMap[sourceClassID] ?? sourceClassID
    if localClassID >= 0 && localClassID < classNames.count {
      return (localClassID, classNames[localClassID])
    }
    if sourceClassMap.isEmpty {
      return (sourceClassID, "cls_\(sourceClassID)")
    }
    return nil
  }

  private func applyNMS(to detections: [NativeDetection]) -> [NativeDetection] {
    let sorted = detections.sorted { $0.confidence > $1.confidence }
    var kept: [NativeDetection] = []

    for candidate in sorted {
      let shouldSuppress = kept.contains { keptDetection in
        keptDetection.classID == candidate.classID &&
          iou(lhs: keptDetection.rect, rhs: candidate.rect) > nmsIoUThreshold
      }

      if !shouldSuppress {
        kept.append(candidate)
      }
    }

    return kept
  }

  private func iou(lhs: CGRect, rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    if intersection.isNull || intersection.isEmpty { return 0.0 }

    let intersectionArea = intersection.width * intersection.height
    let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
    guard unionArea > 0 else { return 0.0 }
    return intersectionArea / unionArea
  }
}

private extension CGRect {
  func clampedToUnit() -> CGRect {
    let x = Swift.min(Swift.max(origin.x, 0.0), 1.0)
    let y = Swift.min(Swift.max(origin.y, 0.0), 1.0)
    let maxWidth = 1.0 - x
    let maxHeight = 1.0 - y
    let width = Swift.min(Swift.max(size.width, 0.0), maxWidth)
    let height = Swift.min(Swift.max(size.height, 0.0), maxHeight)
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

final class NativeExecuTorchRunner {
  private let module: Module

  init(modelName: String, fileExtension: String) throws {
    guard let modelPath = Bundle.main.path(forResource: modelName, ofType: fileExtension) else {
      throw NativeDetectorError.modelNotFound
    }

    module = Module(filePath: modelPath)
    try module.load("forward")
  }

  func predict(input: [Float], shape: [Int]) throws -> [Float] {
    let inputTensor = Tensor<Float>(input, shape: shape)
    let outputs = try module.forward(inputTensor)

    guard let outputTensor: Tensor<Float> = outputs.first?.tensor() else {
      throw NativeDetectorError.invalidOutput
    }

    return outputTensor.scalars()
  }
}
