import Flutter
import UIKit
import CloudKit
import Security
import AVFoundation
import os

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var cloudSyncHandler: CloudSyncHandler?
  private let voicePracticeAudio = VoicePracticeAudio()
  private static let installMarkerService = "com.yunxu.yunxulearn.install"
  private static let installMarkerAccount = "has_launched_before"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let voiceChannel = FlutterMethodChannel(
        name: "voice_practice", binaryMessenger: controller.binaryMessenger
      )
      voiceChannel.setMethodCallHandler { [weak self] call, result in
        self?.voicePracticeAudio.handle(call, result: result)
      }
      let microphoneChannel = FlutterEventChannel(
        name: "voice_practice/microphone", binaryMessenger: controller.binaryMessenger
      )
      microphoneChannel.setStreamHandler(voicePracticeAudio)

      let installChannel = FlutterMethodChannel(name: "install_state", binaryMessenger: controller.binaryMessenger)
      installChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "shouldAutoRestoreOnEmptyData":
          result(Self.shouldAutoRestoreOnEmptyData())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let channel = FlutterMethodChannel(name: "cloud_sync", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let args = call.arguments as? [String: Any],
              let containerId = args["containerId"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing containerId", details: nil))
          return
        }

        if self?.cloudSyncHandler == nil || self?.cloudSyncHandler?.containerId != containerId {
          self?.cloudSyncHandler = CloudSyncHandler(containerId: containerId)
        }

        guard let handler = self?.cloudSyncHandler else {
          result(FlutterError(code: "init_failed", message: "CloudSyncHandler unavailable", details: nil))
          return
        }

        switch call.method {
        case "pushChanges":
          let records = args["records"] as? [[String: Any]] ?? []
          handler.pushChanges(records: records) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success:
                result(true)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "push_failed"))
              }
            }
          }
        case "fetchChanges":
          let sinceMillis = args["since"] as? Int ?? 0
          let sinceDate = Date(timeIntervalSince1970: Double(sinceMillis) / 1000.0)
          handler.fetchChanges(since: sinceDate) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success(let records):
                result(records)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "fetch_failed"))
              }
            }
          }
        case "pushSettings":
          let settings = args["settings"] as? [String: Any] ?? [:]
          handler.pushSettings(settings: settings) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success:
                result(true)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "push_settings_failed"))
              }
            }
          }
        case "fetchSettings":
          handler.fetchSettings { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success(let settings):
                result(settings)
              case .failure(let error):
                result(Self.cloudFlutterError(error, fallbackCode: "fetch_settings_failed"))
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func cloudFlutterError(_ error: Error, fallbackCode: String) -> FlutterError {
    if let ckError = error as? CKError {
      let mappedCode: String
      switch ckError.code {
      case .notAuthenticated:
        mappedCode = "icloud_not_signed_in"
      case .permissionFailure, .missingEntitlement:
        mappedCode = "icloud_permission_denied"
      case .quotaExceeded:
        mappedCode = "quota_exceeded"
      case .networkUnavailable, .networkFailure:
        mappedCode = "network_unavailable"
      case .serviceUnavailable, .requestRateLimited, .zoneBusy:
        mappedCode = "server_error"
      default:
        mappedCode = "sync_failed"
      }
      return FlutterError(
        code: mappedCode,
        message: error.localizedDescription,
        details: ["fallbackCode": fallbackCode, "ckErrorCode": ckError.code.rawValue]
      )
    }

    return FlutterError(
      code: "sync_failed",
      message: error.localizedDescription,
      details: ["fallbackCode": fallbackCode]
    )
  }

  private static func shouldAutoRestoreOnEmptyData() -> Bool {
    if hasInstallMarker() {
      return true
    }
    _ = saveInstallMarker()
    return false
  }

  private static func installMarkerQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: installMarkerService,
      kSecAttrAccount as String: installMarkerAccount
    ]
  }

  private static func hasInstallMarker() -> Bool {
    var query = installMarkerQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return status == errSecSuccess
  }

  private static func saveInstallMarker() -> Bool {
    let valueData = Data("1".utf8)
    var addQuery = installMarkerQuery()
    addQuery[kSecValueData as String] = valueData

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return true
    }
    if addStatus == errSecDuplicateItem {
      let updateQuery = installMarkerQuery()
      let updateAttrs = [kSecValueData as String: valueData] as CFDictionary
      let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs)
      return updateStatus == errSecSuccess
    }
    return false
  }
}

private final class VoicePracticeAudio: NSObject, FlutterStreamHandler {
  private let logger = Logger(subsystem: "com.yunxu.yunxulearn", category: "VoicePracticeAudio")
  private let sampleRate = 24_000.0
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var microphone: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var startRequest: UUID?
  private var audioSessionId: UUID?
  private var engineId: UUID?
  private var voiceProcessing = true
  private var recovery: DispatchWorkItem?
  private var recoveryAttempts = 0
  private var lastRecovery = Date.distantPast
  private var pendingPlayback: [Data] = []
  private var pendingPlaybackBytes = 0
  private var muted = false
  private var inputTapInstalled = false
  private var previousAudioCategory: (
    AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions
  )?
  private var playbackFormat: AVAudioFormat?
  private var playbackSegments: [Range<AVAudioFramePosition>] = []
  private var completedPlaybackFrames: AVAudioFramePosition = 0

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    microphone = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    microphone = nil
    stop()
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      requestStart(result)
    case "play":
      guard let audio = call.arguments as? FlutterStandardTypedData,
        queuePlayback(audio.data)
      else {
        result(FlutterError(code: "playback_failed", message: nil, details: nil))
        return
      }
      result(nil)
    case "interrupt":
      result(interrupt())
    case "playbackRemaining":
      let frames = (playbackSegments.last?.upperBound ?? 0) - playbackPosition()
      result(milliseconds(max(0, frames)) + (recovery == nil ? 0 : 500))
    case "mute":
      guard let muted = call.arguments as? Bool else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      self.muted = muted
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestStart(_ result: @escaping FlutterResult) {
    stop()
    let request = UUID()
    startRequest = request
    let permission: (Bool) -> Void = { [weak self] allowed in
      DispatchQueue.main.async {
        guard let self, self.startRequest == request else {
          result(FlutterError(code: "cancelled", message: nil, details: nil))
          return
        }
        self.startRequest = nil
        guard allowed else {
          result(FlutterError(code: "microphone_denied", message: nil, details: nil))
          return
        }
        self.start(result)
      }
    }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: permission)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(permission)
    }
  }

  private func start(_ result: FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    previousAudioCategory = (session.category, session.mode, session.categoryOptions)
    do {
      let sessionId = UUID()
      audioSessionId = sessionId
      do {
        try configureAudioSession(voiceProcessing: true)
        try startEngine(sessionId)
      } catch {
        try startWithoutVoiceProcessing(sessionId, after: error)
      }
      result(nil)
    } catch {
      logAudioError("start", error)
      stop()
      result(FlutterError(code: "audio_start_failed", message: nil, details: nil))
    }
  }

  private func configureAudioSession(voiceProcessing: Bool) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord, mode: voiceProcessing ? .voiceChat : .default,
      options: [.defaultToSpeaker]
    )
    try session.setActive(true)
    self.voiceProcessing = voiceProcessing
  }

  private func startWithoutVoiceProcessing(_ sessionId: UUID, after error: Error) throws {
    logAudioError("voice processing", error)
    stopEngine()
    recoveryAttempts = 0
    try configureAudioSession(voiceProcessing: false)
    try startEngine(sessionId)
  }

  private func logAudioError(_ step: String, _ error: Error) {
    let failure = error as NSError
    logger.error("\(step, privacy: .public): \(failure.domain, privacy: .public) \(failure.code)")
  }

  private func startEngine(_ sessionId: UUID) throws {
    let session = AVAudioSession.sharedInstance()
    let engine = AVAudioEngine()
    self.engine = engine
    let engineId = UUID()
    self.engineId = engineId
    let input = engine.inputNode
    if voiceProcessing {
      try input.setVoiceProcessingEnabled(true)
    }

    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
      let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true
      ),
      let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
      let converter = AVAudioConverter(from: inputFormat, to: wireFormat)
    else {
      throw CocoaError(.featureUnsupported)
    }
    self.playbackFormat = playbackFormat
    let player = AVAudioPlayerNode()
    self.player = player
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

    let ratio = sampleRate / inputFormat.sampleRate
    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      let frameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
      guard let output = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: frameCapacity) else {
        return
      }
      var suppliedBuffer = false
      let status = converter.convert(to: output, error: nil) { _, inputStatus in
        guard !suppliedBuffer else {
          inputStatus.pointee = .noDataNow
          return nil
        }
        suppliedBuffer = true
        inputStatus.pointee = .haveData
        return buffer
      }
      guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData?[0] else {
        return
      }
      let bytes = Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.engineId == engineId,
          self.engine?.isRunning == true, self.recovery == nil, !self.muted
        else { return }
        self.microphone?(FlutterStandardTypedData(bytes: bytes))
      }
    }
    inputTapInstalled = true

    engine.prepare()
    try engine.start()
    observeInterruptions(engine: engine, session: session, sessionId: sessionId)
  }

  private func observeInterruptions(
    engine: AVAudioEngine, session: AVAudioSession, sessionId: UUID
  ) {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification, object: session, queue: .main
    ) { [weak self] notification in
      if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
          == AVAudioSession.InterruptionType.began.rawValue {
        // iOS can deliver a deferred suspension notification on activation.
        if notification.userInfo?[AVAudioSessionInterruptionWasSuspendedKey] as? Bool == true {
          return
        }
        if #available(iOS 17.0, *),
          notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            == AVAudioSession.InterruptionReason.routeDisconnected.rawValue
        {
          self?.recoverEngine(sessionId)
        } else {
          self?.audioInterrupted(sessionId)
        }
      }
    })
    observers.append(center.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self, weak engine] _ in
      if engine?.isRunning == false {
        self?.recoverEngine(sessionId)
      }
    })
  }

  private func recoverEngine(_ sessionId: UUID) {
    guard audioSessionId == sessionId, recovery == nil else { return }
    let now = Date()
    if now.timeIntervalSince(lastRecovery) > 3 { recoveryAttempts = 0 }
    lastRecovery = now
    recoveryAttempts += 1
    guard recoveryAttempts <= 2 else {
      audioRouteFailed()
      return
    }
    // Let iOS finish switching routes before rebuilding with its current formats.
    let task = DispatchWorkItem { [weak self] in
      guard let self, self.audioSessionId == sessionId else { return }
      self.stopEngine()
      do {
        do {
          if self.voiceProcessing && self.recoveryAttempts == 2 {
            throw CocoaError(.featureUnsupported)
          }
          try AVAudioSession.sharedInstance().setActive(true)
          try self.startEngine(sessionId)
        } catch {
          guard self.voiceProcessing else { throw error }
          try self.startWithoutVoiceProcessing(sessionId, after: error)
        }
        self.recovery = nil
        let pending = self.pendingPlayback
        self.clearPendingPlayback()
        for chunk in pending {
          guard self.queuePlayback(chunk) else { break }
        }
      } catch {
        self.logAudioError("route recovery", error)
        self.audioRouteFailed()
      }
    }
    recovery = task
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: task)
  }

  private func audioRouteFailed() {
    stop()
    microphone?(FlutterError(code: "audio_route_failed", message: nil, details: nil))
  }

  private func queuePlayback(_ data: Data) -> Bool {
    if let sessionId = audioSessionId, engine?.isRunning == false {
      recoverEngine(sessionId)
    }
    if recovery != nil {
      // Keep at most four seconds of audio while iOS switches devices.
      if pendingPlaybackBytes + data.count <= Int(sampleRate) * 2 * 4 {
        pendingPlayback.append(data)
        pendingPlaybackBytes += data.count
      }
      return true
    }
    return play(data)
  }

  private func clearPendingPlayback() {
    pendingPlayback.removeAll()
    pendingPlaybackBytes = 0
  }

  private func audioInterrupted(_ sessionId: UUID) {
    guard audioSessionId == sessionId else { return }
    stop()
    microphone?(FlutterError(code: "audio_interrupted", message: nil, details: nil))
  }

  private func play(_ data: Data) -> Bool {
    guard let player, let playbackFormat, engine?.isRunning == true,
      !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Int16>.size),
      let frameCount = AVAudioFrameCount(exactly: data.count / MemoryLayout<Int16>.size),
      let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
      let samples = buffer.floatChannelData?[0]
    else { return false }

    buffer.frameLength = frameCount
    data.withUnsafeBytes { bytes in
      for index in 0..<Int(frameCount) {
        let sample = bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
        samples[index] = Float(Int16(littleEndian: sample)) / 32_768
      }
    }

    let position = playbackPosition()
    let lastEnd = playbackSegments.last?.upperBound ?? position
    while let first = playbackSegments.first, first.upperBound <= position {
      completedPlaybackFrames += AVAudioFramePosition(first.count)
      playbackSegments.removeFirst()
    }
    // Schedule immediately after the previous chunk. If it has already drained,
    // give the render thread 20 ms to pick up this chunk.
    let start = player.isPlaying ? max(lastEnd, position + (lastEnd <= position ? 480 : 0)) : 0
    playbackSegments.append(start..<(start + AVAudioFramePosition(frameCount)))
    player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: sampleRate))
    if !player.isPlaying { player.play() }
    return true
  }

  private func playbackPosition() -> AVAudioFramePosition {
    guard let player, let renderTime = player.lastRenderTime,
      let time = player.playerTime(forNodeTime: renderTime)
    else { return 0 }
    return max(0, time.sampleTime)
  }

  private func milliseconds(_ frames: AVAudioFramePosition) -> Int {
    Int(Double(frames) * 1000 / sampleRate)
  }

  private func interrupt() -> Int {
    clearPendingPlayback()
    return stopPlayback()
  }

  private func stopPlayback() -> Int {
    let position = playbackPosition()
    let played = playbackSegments.reduce(completedPlaybackFrames) { total, segment in
      total + max(0, min(position, segment.upperBound) - segment.lowerBound)
    }
    player?.stop()
    playbackSegments.removeAll()
    completedPlaybackFrames = 0
    return milliseconds(played)
  }

  private func stop() {
    startRequest = nil
    audioSessionId = nil
    muted = false
    recovery?.cancel()
    recovery = nil
    recoveryAttempts = 0
    clearPendingPlayback()
    stopEngine()
    if let (category, mode, options) = previousAudioCategory {
      previousAudioCategory = nil
      let session = AVAudioSession.sharedInstance()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      try? session.setCategory(category, mode: mode, options: options)
    }
  }

  private func stopEngine() {
    engineId = nil
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    _ = stopPlayback()
    if inputTapInstalled {
      engine?.inputNode.removeTap(onBus: 0)
      inputTapInstalled = false
    }
    engine?.stop()
    engine = nil
    player = nil
    playbackFormat = nil
  }
}
