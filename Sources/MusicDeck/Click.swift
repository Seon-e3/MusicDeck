import AVFoundation
import AppKit

/// 다이얼 딸깍 소리와 버튼 소리. 녹음 파일 없이 짧은 파형을 직접 만든다.
enum Click {
    private static var engine = AVAudioEngine()
    private static var node = AVAudioPlayerNode()
    private static var deviceObserver: Any?
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    // 다이얼 한 칸: 높고 짧은 금속성 틱 / 버튼: 낮고 묵직한 톡
    private static let tick = tone(freq: 3400, ms: 7, decay: 900, noise: 0.45, gain: 0.30)
    private static let key = tone(freq: 520, ms: 28, decay: 220, noise: 0.20, gain: 0.55)
    private static var lastTick = Date.distantPast
    static var haptics = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(haptics, forKey: "haptics") }
    }

    // 진동 세기는 macOS가 정해서 바꿀 수 없다. 대신 횟수를 줄여 덜 느껴지게 한다:
    // 두 칸(볼륨 4)에 한 번, 최소 40ms 간격
    private static var detents = 0
    private static var lastHaptic = Date.distantPast

    static func detent() {
        // 너무 빠르게 돌리면 소리가 뭉개지므로 18ms에 한 번까지만
        guard Date().timeIntervalSince(lastTick) > 0.018 else { return }
        lastTick = Date()
        play(tick)
        detents += 1
        guard haptics, detents % 2 == 0, Date().timeIntervalSince(lastHaptic) > 0.04 else { return }
        lastHaptic = Date()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func press() { play(key) }

    private static func play(_ buffer: AVAudioPCMBuffer) {
        if node.engine == nil { setUpEngine() }
        if !engine.isRunning { try? engine.start() }
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// 출력 장치가 바뀌면(에어팟 연결 등) macOS가 엔진을 멈추고 내부 연결을 끊는다.
    /// 다시 켜기만 해서는 소리가 안 나므로 그때마다 엔진을 통째로 새로 만든다.
    private static func setUpEngine() {
        engine = AVAudioEngine()
        node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        deviceObserver.map(NotificationCenter.default.removeObserver)
        deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            setUpEngine()
        }
    }

    private static func tone(freq: Double, ms: Double, decay: Double, noise: Double, gain: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(format.sampleRate * ms / 1000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let out = buf.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / format.sampleRate
            let s = sin(2 * .pi * freq * t) * (1 - noise) + Double.random(in: -1...1) * noise
            out[i] = Float(s * exp(-t * decay) * gain)
        }
        return buf
    }
}
