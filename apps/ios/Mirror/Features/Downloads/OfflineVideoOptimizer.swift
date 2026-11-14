import AVFoundation
import VideoToolbox

/// Local-only conversion. The caller owns the original until the manifest commits
/// the returned file. nil means the source is already efficient or unsupported.
@MainActor
enum OfflineVideoOptimizer {
  static func optimize(_ source: URL) async throws -> URL? {
    try Task.checkCancellation()
    let asset = AVURLAsset(url: source)
    guard try await asset.load(.isPlayable) else { throw Failure.invalidVideo }
    let videos = try await asset.loadTracks(withMediaType: .video)
    guard videos.count == 1, let video = videos.first else { throw Failure.invalidVideo }
    let formats = try await video.load(.formatDescriptions)
    let characteristics = try await video.load(.mediaCharacteristics)
    // Avoid repeated lossy conversions, HDR tone mapping, and software-only
    // encoding on older Macs. Unsupported sources remain valid offline files.
    guard formats.count == 1, let format = formats.first,
      CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264,
      hardwareHEVCAvailable(),
      !characteristics.contains(.containsHDRVideo)
    else { return nil }
    let size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    let free =
      try source.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage ?? 0
    guard free > size + 64 * 1024 * 1024 else { throw Failure.storage }
    let audio = try await asset.loadTracks(withMediaType: .audio)
    for track in audio {
      let descriptions = try await track.load(.formatDescriptions)
      guard
        descriptions.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC })
      else { return nil }
    }
    let dimensions = try await video.load(.naturalSize)
    let bitrate = try await video.load(.estimatedDataRate)
    guard bitrate > 0, dimensions.width > 0, dimensions.height > 0 else { return nil }
    let destination = source.deletingLastPathComponent().appendingPathComponent(
      UUID().uuidString + ".mp4")
    var keep = false
    defer { if !keep { try? FileManager.default.removeItem(at: destination) } }
    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let output = AVAssetReaderTrackOutput(
      track: video,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
      ])
    output.alwaysCopiesSampleData = false
    var videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.hevc,
      AVVideoWidthKey: Int(dimensions.width), AVVideoHeightKey: Int(dimensions.height),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Int(bitrate * 0.7),
        AVVideoMaxKeyFrameIntervalDurationKey: 2,
      ],
    ]
    let extensions = (CMFormatDescriptionGetExtensions(format) as NSDictionary?) ?? [:]
    var colors: [String: Any] = [:]
    for (sourceKey, outputKey) in [
      (kCMFormatDescriptionExtension_ColorPrimaries, AVVideoColorPrimariesKey),
      (kCMFormatDescriptionExtension_TransferFunction, AVVideoTransferFunctionKey),
      (kCMFormatDescriptionExtension_YCbCrMatrix, AVVideoYCbCrMatrixKey),
    ] {
      if let value = extensions[sourceKey] { colors[outputKey] = value }
    }
    if !colors.isEmpty { videoSettings[AVVideoColorPropertiesKey] = colors }
    #if os(macOS)
      videoSettings[AVVideoEncoderSpecificationKey] = [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
      ]
    #endif
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.transform = try await video.load(.preferredTransform)
    guard reader.canAdd(output), writer.canAdd(input) else { return nil }
    reader.add(output)
    writer.add(input)
    var streams = [(output, input)]
    for track in audio {
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      let hint = try await track.load(.formatDescriptions).first
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
      guard reader.canAdd(output), writer.canAdd(input) else { return nil }
      reader.add(output)
      writer.add(input)
      streams.append((output, input))
    }
    let encoder = LocalVideoEncoder(reader: reader, writer: writer, streams: streams)
    let task = Task.detached(priority: .utility) { try await encoder.run() }
    try await withTaskCancellationHandler {
      try await task.value
      try Task.checkCancellation()
    } onCancel: {
      task.cancel()
      encoder.cancel()
    }
    let result = AVURLAsset(url: destination)
    guard try await result.load(.isPlayable) else { throw Failure.invalidVideo }
    let outputVideos = try await result.loadTracks(withMediaType: .video)
    guard let outputVideo = outputVideos.first, outputVideos.count == videos.count else {
      throw Failure.invalidVideo
    }
    let inputDuration = try await asset.load(.duration).seconds
    let outputDuration = try await result.load(.duration).seconds
    let originalSize = try await video.load(.naturalSize)
    let outputSize = try await outputVideo.load(.naturalSize)
    let inputRate = try await video.load(.nominalFrameRate)
    let outputRate = try await outputVideo.load(.nominalFrameRate)
    let originalAudio = try await asset.loadTracks(withMediaType: .audio)
    let outputAudio = try await result.loadTracks(withMediaType: .audio)
    let outputFormats = try await outputVideo.load(.formatDescriptions)
    guard inputDuration.isFinite, inputDuration > 0, outputDuration.isFinite,
      abs(inputDuration - outputDuration) < 0.25,
      originalSize == outputSize, abs(inputRate - outputRate) < 0.1,
      originalAudio.count == outputAudio.count,
      outputFormats.first.map({ CMFormatDescriptionGetMediaSubType($0) }) == kCMVideoCodecType_HEVC
    else { throw Failure.invalidVideo }
    // Exercise decoding at the beginning, middle, and end before committing.
    let images = AVAssetImageGenerator(asset: result)
    for fraction in [0.0, 0.5, 0.95] {
      try Task.checkCancellation()
      _ = try await images.image(
        at: CMTime(seconds: inputDuration * fraction, preferredTimescale: 600))
    }
    let outputBytes = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    guard outputBytes > 0, outputBytes < size * 95 / 100 else { return nil }
    try Task.checkCancellation()
    keep = true
    return destination
  }

  static func hardwareHEVCAvailable() -> Bool {
    guard #available(iOS 17.4, *) else { return false }
    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      width: 1920, height: 1080, codecType: kCMVideoCodecType_HEVC,
      encoderSpecification: [
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
      ] as CFDictionary,
      imageBufferAttributes: nil, compressedDataAllocator: nil,
      outputCallback: nil, refcon: nil, compressionSessionOut: &session)
    if let session { VTCompressionSessionInvalidate(session) }
    return status == noErr
  }

  enum Failure: LocalizedError {
    case invalidVideo, storage
    var errorDescription: String? {
      switch self {
      case .invalidVideo: return "Couldn’t process this download. Tap Retry to try again."
      case .storage:
        return "Not enough free space to process this download. Free some space and retry."
      }
    }
  }
}

/// Keeps sample pumping off the UI thread and memory bounded to a few frames.
private final class LocalVideoEncoder: @unchecked Sendable {
  let reader: AVAssetReader
  let writer: AVAssetWriter
  let streams: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]
  init(
    reader: AVAssetReader, writer: AVAssetWriter,
    streams: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]
  ) {
    self.reader = reader
    self.writer = writer
    self.streams = streams
  }
  func cancel() {
    reader.cancelReading()
    writer.cancelWriting()
  }
  func run() async throws {
    do {
      try Task.checkCancellation()
      guard writer.startWriting(), reader.startReading() else {
        throw writer.error ?? reader.error ?? OfflineVideoOptimizer.Failure.invalidVideo
      }
      writer.startSession(atSourceTime: .zero)
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (output, input) in streams {
          group.addTask { [self] in
            while true {
              try Task.checkCancellation()
              guard writer.status == .writing else {
                throw writer.error ?? OfflineVideoOptimizer.Failure.invalidVideo
              }
              if !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
                continue
              }
              guard let sample = output.copyNextSampleBuffer() else {
                if let error = reader.error { throw error }
                input.markAsFinished()
                return
              }
              guard input.append(sample) else {
                throw writer.error ?? OfflineVideoOptimizer.Failure.invalidVideo
              }
            }
          }
        }
        for try await _ in group {}
      }
      try Task.checkCancellation()
      await writer.finishWriting()
      guard writer.status == .completed else {
        throw writer.error ?? OfflineVideoOptimizer.Failure.invalidVideo
      }
    } catch {
      cancel()
      throw error
    }
  }
}
