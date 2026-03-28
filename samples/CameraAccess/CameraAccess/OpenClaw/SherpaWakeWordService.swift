import AVFoundation
import Accelerate
import Foundation

// MARK: - Minimal ONNX Runtime Wrapper

/// A lightweight wrapper around the ONNX Runtime C API for running a single-input,
/// single-output float model. Designed for wake word inference with input shape
/// [1, 16, 96] and output shape [1, 1].
private final class OnnxRunner {
  private let api: UnsafePointer<OrtApi>
  private var env: OpaquePointer?         // OrtEnv*
  private var session: OpaquePointer?     // OrtSession*
  private var memoryInfo: OpaquePointer?  // OrtMemoryInfo*

  private let inputName: String
  private let outputName: String

  init?(modelPath: String, inputName: String = "input", outputName: String = "hey_alistair") {
    guard let apiBase = OrtGetApiBase() else {
      NSLog("[WakeWord] OnnxRunner: OrtGetApiBase returned nil")
      return nil
    }
    guard let apiPtr = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
      NSLog("[WakeWord] OnnxRunner: GetApi returned nil")
      return nil
    }
    self.api = apiPtr
    self.inputName = inputName
    self.outputName = outputName

    // Create environment
    var envPtr: OpaquePointer?
    var status = api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "wakeword", &envPtr)
    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: CreateEnv failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      return nil
    }
    self.env = envPtr

    // Create session options
    var sessionOptions: OpaquePointer?
    status = api.pointee.CreateSessionOptions(&sessionOptions)
    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: CreateSessionOptions failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      cleanup()
      return nil
    }

    // Set to single thread for efficiency on mobile
    _ = api.pointee.SetIntraOpNumThreads(sessionOptions, 1)
    _ = api.pointee.SetInterOpNumThreads(sessionOptions, 1)

    // Create session from model path
    var sessionPtr: OpaquePointer?
    status = api.pointee.CreateSession(envPtr, modelPath, sessionOptions, &sessionPtr)
    api.pointee.ReleaseSessionOptions(sessionOptions)

    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: CreateSession failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      cleanup()
      return nil
    }
    self.session = sessionPtr

    // Create CPU memory info
    var memInfoPtr: OpaquePointer?
    status = api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memInfoPtr)
    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: CreateCpuMemoryInfo failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      cleanup()
      return nil
    }
    self.memoryInfo = memInfoPtr

    NSLog("[WakeWord] OnnxRunner: Session created successfully for model: %@", modelPath)
  }

  deinit {
    cleanup()
  }

  /// Run inference with a flat float array of shape [1, 16, 96].
  /// Returns the single output float, or nil on failure.
  func run(inputData: inout [Float]) -> Float? {
    guard let session = session, let memoryInfo = memoryInfo else { return nil }

    // Input tensor shape: [1, 16, 96]
    var inputShape: [Int64] = [1, 16, 96]
    let inputDataSize = inputData.count * MemoryLayout<Float>.size

    var inputTensor: OpaquePointer?
    var status = inputData.withUnsafeMutableBufferPointer { bufferPtr -> OpaquePointer? in
      var tensor: OpaquePointer?
      let s = api.pointee.CreateTensorWithDataAsOrtValue(
        memoryInfo,
        bufferPtr.baseAddress,
        inputDataSize,
        &inputShape,
        inputShape.count,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &tensor
      )
      inputTensor = tensor
      return s
    }

    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: CreateTensor failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      return nil
    }

    defer {
      if let inputTensor = inputTensor {
        api.pointee.ReleaseValue(inputTensor)
      }
    }

    // Set up input/output names
    let inputNameCStr = inputName.withCString { strdup($0) }!
    let outputNameCStr = outputName.withCString { strdup($0) }!
    defer {
      free(inputNameCStr)
      free(outputNameCStr)
    }

    var inputNames: [UnsafePointer<CChar>?] = [UnsafePointer(inputNameCStr)]
    var outputNames: [UnsafePointer<CChar>?] = [UnsafePointer(outputNameCStr)]
    var inputValues: [OpaquePointer?] = [inputTensor]
    var outputValues: [OpaquePointer?] = [nil]

    // Run inference
    status = api.pointee.Run(
      session,
      nil,  // run options
      &inputNames,
      &inputValues,
      1,
      &outputNames,
      1,
      &outputValues
    )

    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: Run failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      return nil
    }

    defer {
      if let outputValue = outputValues[0] {
        api.pointee.ReleaseValue(outputValue)
      }
    }

    // Read output float
    guard let outputValue = outputValues[0] else {
      NSLog("[WakeWord] OnnxRunner: output value is nil")
      return nil
    }

    var outputDataPtr: UnsafeMutableRawPointer?
    status = api.pointee.GetTensorMutableData(outputValue, &outputDataPtr)
    if let status = status {
      let msg = api.pointee.GetErrorMessage(status).flatMap { String(cString: $0) } ?? "unknown"
      NSLog("[WakeWord] OnnxRunner: GetTensorMutableData failed: %@", msg)
      api.pointee.ReleaseStatus(status)
      return nil
    }

    guard let dataPtr = outputDataPtr else {
      NSLog("[WakeWord] OnnxRunner: output data pointer is nil")
      return nil
    }

    let resultPtr = dataPtr.assumingMemoryBound(to: Float.self)
    return resultPtr.pointee
  }

  private func cleanup() {
    if let memoryInfo = memoryInfo {
      api.pointee.ReleaseMemoryInfo(memoryInfo)
      self.memoryInfo = nil
    }
    if let session = session {
      api.pointee.ReleaseSession(session)
      self.session = nil
    }
    if let env = env {
      api.pointee.ReleaseEnv(env)
      self.env = nil
    }
  }
}

// MARK: - Mel Spectrogram Computer

/// Computes mel spectrograms from raw PCM audio using Apple's Accelerate framework.
/// Configuration matches openWakeWord requirements:
///   - 400-sample window (25ms at 16kHz)
///   - 160-sample hop (10ms at 16kHz)
///   - 512-point FFT
///   - 96 mel bands
///   - Log-scaled output
private final class MelSpectrogramComputer {
  let windowSize: Int = 400   // 25ms at 16kHz
  let hopSize: Int = 160      // 10ms at 16kHz
  let fftSize: Int = 512
  let numMelBands: Int = 96
  let sampleRate: Float = 16000.0

  private let fftSetup: vDSP.FFT<DSPSplitComplex>
  private var hanningWindow: [Float]
  private var melFilterbank: [[Float]]  // [numMelBands][fftSize/2 + 1]

  // Buffers reused across calls
  private var paddedBuffer: [Float]
  private var windowedBuffer: [Float]
  private var realPart: [Float]
  private var imagPart: [Float]
  private var magnitudes: [Float]

  init() {
    let log2n = vDSP_Length(log2(Float(fftSize)))
    guard let setup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
      fatalError("[WakeWord] MelSpectrogramComputer: Failed to create FFT setup")
    }
    self.fftSetup = setup

    // Hanning window of windowSize
    self.hanningWindow = [Float](repeating: 0, count: windowSize)
    vDSP_hann_window(&self.hanningWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

    // Allocate reusable buffers
    let halfFFT = fftSize / 2
    self.paddedBuffer = [Float](repeating: 0, count: fftSize)
    self.windowedBuffer = [Float](repeating: 0, count: windowSize)
    self.realPart = [Float](repeating: 0, count: halfFFT)
    self.imagPart = [Float](repeating: 0, count: halfFFT)
    self.magnitudes = [Float](repeating: 0, count: halfFFT)

    // Build mel filterbank
    self.melFilterbank = MelSpectrogramComputer.buildMelFilterbank(
      numBands: numMelBands,
      fftSize: fftSize,
      sampleRate: sampleRate
    )
  }

  /// Compute mel frames from raw PCM samples.
  /// Returns an array of mel frames, each containing `numMelBands` floats (log-scaled).
  func computeMelFrames(from samples: [Float]) -> [[Float]] {
    var frames: [[Float]] = []
    var offset = 0

    while offset + windowSize <= samples.count {
      let frame = computeSingleMelFrame(samples: samples, offset: offset)
      frames.append(frame)
      offset += hopSize
    }

    return frames
  }

  private func computeSingleMelFrame(samples: [Float], offset: Int) -> [Float] {
    let halfFFT = fftSize / 2

    // Apply window to the audio segment
    for i in 0..<windowSize {
      windowedBuffer[i] = samples[offset + i] * hanningWindow[i]
    }

    // Zero-pad to FFT size
    for i in 0..<fftSize {
      paddedBuffer[i] = i < windowSize ? windowedBuffer[i] : 0
    }

    // Perform FFT using vDSP
    // Pack real input into split complex format for real FFT
    realPart = [Float](repeating: 0, count: halfFFT)
    imagPart = [Float](repeating: 0, count: halfFFT)

    paddedBuffer.withUnsafeBufferPointer { inputPtr in
      realPart.withUnsafeMutableBufferPointer { realPtr in
        imagPart.withUnsafeMutableBufferPointer { imagPtr in
          var splitComplex = DSPSplitComplex(
            realp: realPtr.baseAddress!,
            imagp: imagPtr.baseAddress!
          )

          // Convert interleaved real data to split complex
          inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
          }

          // Forward FFT
          fftSetup.forward(input: splitComplex, output: &splitComplex)
        }
      }
    }

    // Compute power spectrum (magnitude squared)
    for i in 0..<halfFFT {
      magnitudes[i] = realPart[i] * realPart[i] + imagPart[i] * imagPart[i]
    }

    // Apply mel filterbank and log scaling
    var melFrame = [Float](repeating: 0, count: numMelBands)
    for band in 0..<numMelBands {
      var sum: Float = 0
      let filter = melFilterbank[band]
      // filter has halfFFT + 1 elements, but we only have halfFFT magnitudes
      // The DC and Nyquist bins are handled by using halfFFT elements
      for bin in 0..<halfFFT {
        sum += magnitudes[bin] * filter[bin]
      }
      // Log scale: log(max(value, 1e-10))
      melFrame[band] = logf(max(sum, 1e-10))
    }

    return melFrame
  }

  // MARK: - Mel Filterbank Construction

  /// Convert frequency in Hz to mel scale.
  private static func hzToMel(_ hz: Float) -> Float {
    return 2595.0 * log10f(1.0 + hz / 700.0)
  }

  /// Convert mel scale to frequency in Hz.
  private static func melToHz(_ mel: Float) -> Float {
    return 700.0 * (powf(10.0, mel / 2595.0) - 1.0)
  }

  /// Build a mel filterbank matrix.
  /// Returns an array of `numBands` filters, each with `fftSize/2 + 1` coefficients.
  private static func buildMelFilterbank(
    numBands: Int,
    fftSize: Int,
    sampleRate: Float
  ) -> [[Float]] {
    let halfFFT = fftSize / 2
    let numBins = halfFFT + 1

    let lowMel = hzToMel(0)
    let highMel = hzToMel(sampleRate / 2.0)

    // Create numBands + 2 equally spaced points in mel scale
    let numPoints = numBands + 2
    var melPoints = [Float](repeating: 0, count: numPoints)
    for i in 0..<numPoints {
      melPoints[i] = lowMel + Float(i) * (highMel - lowMel) / Float(numPoints - 1)
    }

    // Convert back to Hz and then to FFT bin indices
    var binIndices = [Int](repeating: 0, count: numPoints)
    for i in 0..<numPoints {
      let hz = melToHz(melPoints[i])
      binIndices[i] = Int(floorf(hz * Float(fftSize) / sampleRate + 0.5))
    }

    // Build triangular filters
    var filterbank = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numBands)

    for band in 0..<numBands {
      let left = binIndices[band]
      let center = binIndices[band + 1]
      let right = binIndices[band + 2]

      // Rising slope
      if center > left {
        for bin in left...center {
          if bin < numBins {
            filterbank[band][bin] = Float(bin - left) / Float(center - left)
          }
        }
      }

      // Falling slope
      if right > center {
        for bin in center...right {
          if bin < numBins {
            filterbank[band][bin] = Float(right - bin) / Float(right - center)
          }
        }
      }
    }

    return filterbank
  }
}

// MARK: - SherpaWakeWordService

/// Wake word detection service using an openWakeWord ONNX model (`hey_alistair.onnx`).
/// Uses ONNX Runtime (C API) for inference and Accelerate (vDSP) for mel spectrogram computation.
@MainActor
class SherpaWakeWordService: ObservableObject {

  @Published var isListening: Bool = false
  var onWakeWordDetected: (() -> Void)?
  var detectionThreshold: Float = 0.5

  // MARK: - Private State

  private var runner: OnnxRunner?
  private let melComputer = MelSpectrogramComputer()
  private let processingQueue = DispatchQueue(label: "wakeword.processing")
  private var lastDetectionTime: Date = .distantPast
  private let debounceInterval: TimeInterval = 3.0

  /// Sliding window of the last 16 mel frames, each with 96 bands.
  /// Access only from `processingQueue`.
  private var melWindow: [[Float]] = []
  private let requiredFrames = 16

  /// Leftover audio samples that didn't fill a complete window+hop.
  /// Access only from `processingQueue`.
  private var sampleBuffer: [Float] = []

  private let modelFilename = "hey_alistair"

  // MARK: - Public API

  func start() {
    guard runner == nil else {
      NSLog("[WakeWord] Already started, ignoring duplicate start()")
      return
    }

    NSLog("[WakeWord] Starting wake word detection...")

    guard let modelPath = Bundle.main.path(forResource: modelFilename, ofType: "onnx") else {
      NSLog("[WakeWord] ERROR: Could not find %@.onnx in app bundle", modelFilename)
      return
    }

    NSLog("[WakeWord] Model file found: %@", modelPath)

    processingQueue.async { [weak self] in
      guard let self = self else { return }

      let newRunner = OnnxRunner(modelPath: modelPath)

      DispatchQueue.main.async {
        if let newRunner = newRunner {
          self.runner = newRunner
          self.isListening = true
          NSLog("[WakeWord] Wake word detection started (threshold: %.2f)", self.detectionThreshold)
        } else {
          NSLog("[WakeWord] ERROR: Failed to create ONNX session")
        }
      }
    }

    // Reset state
    processingQueue.async { [weak self] in
      self?.melWindow = []
      self?.sampleBuffer = []
    }
    lastDetectionTime = .distantPast
  }

  func stop() {
    NSLog("[WakeWord] Stopping wake word detection")
    isListening = false

    let runnerRef = runner
    runner = nil
    processingQueue.async {
      // OnnxRunner deinit handles cleanup
      _ = runnerRef
      NSLog("[WakeWord] ONNX session released")
    }
  }

  func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard isListening, runner != nil else { return }

    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return }

    // Copy samples so we can safely use them off the audio/main thread
    var samples = [Float](repeating: 0, count: frameCount)
    memcpy(&samples, floatData[0], frameCount * MemoryLayout<Float>.size)

    let runnerRef = runner

    processingQueue.async { [weak self] in
      guard let self = self, let runner = runnerRef else { return }

      // Append new samples to the carry-over buffer
      self.sampleBuffer.append(contentsOf: samples)

      // Compute mel frames from all available samples
      let melFrames = self.melComputer.computeMelFrames(from: self.sampleBuffer)

      if melFrames.isEmpty { return }

      // Keep leftover samples that didn't form a complete frame
      let samplesConsumed = melFrames.count * self.melComputer.hopSize
      if samplesConsumed < self.sampleBuffer.count {
        self.sampleBuffer = Array(self.sampleBuffer[samplesConsumed...])
      } else {
        self.sampleBuffer = []
      }

      // Process each new mel frame through the sliding window
      for melFrame in melFrames {
        // Add to sliding window
        self.melWindow.append(melFrame)

        // Keep only the last `requiredFrames` frames
        if self.melWindow.count > self.requiredFrames {
          self.melWindow.removeFirst(self.melWindow.count - self.requiredFrames)
        }

        // Need exactly 16 frames to run inference
        guard self.melWindow.count == self.requiredFrames else { continue }

        // Flatten [16][96] into [1536] floats for the model input
        var inputData = [Float](repeating: 0, count: self.requiredFrames * self.melComputer.numMelBands)
        for i in 0..<self.requiredFrames {
          let base = i * self.melComputer.numMelBands
          for j in 0..<self.melComputer.numMelBands {
            inputData[base + j] = self.melWindow[i][j]
          }
        }

        // Run ONNX inference
        guard let probability = runner.run(inputData: &inputData) else { continue }

        // Check against threshold
        if probability > self.detectionThreshold {
          let now = Date()
          let timeSinceLast = now.timeIntervalSince(self.lastDetectionTime)

          if timeSinceLast < self.debounceInterval {
            NSLog("[WakeWord] Ignored detection (debounce: %.1fs since last, prob=%.3f)",
                  timeSinceLast, probability)
            continue
          }

          self.lastDetectionTime = now
          NSLog("[WakeWord] Wake word detected! probability=%.3f (threshold=%.2f)",
                probability, self.detectionThreshold)

          DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isListening else { return }
            NSLog("[WakeWord] Firing onWakeWordDetected callback")
            self.onWakeWordDetected?()
          }
        }
      }
    }
  }
}
