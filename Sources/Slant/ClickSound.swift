import AVFoundation

/// A short, soft click synthesised at launch: a damped tap plus a whisper of filtered
/// noise, the kind of sound a lid makes when it settles open.
final class ClickSound {
    private var player: AVAudioPlayer?

    init() {
        player = try? AVAudioPlayer(data: ClickSound.wave())
        player?.volume = 0.5
        player?.prepareToPlay()
    }

    func play() {
        player?.currentTime = 0
        player?.play()
    }

    private static func wave() -> Data {
        let rate = 44_100.0
        let count = Int(rate * 0.09)
        var samples = [Int16](repeating: 0, count: count)
        var noiseState: Float = 0
        var seed: UInt32 = 0x9E37_79B9
        for i in 0..<count {
            let t = Double(i) / rate
            let tap = sin(2 * .pi * 1_650 * t) * exp(-t * 90) * 0.55
                    + sin(2 * .pi * 620 * t) * exp(-t * 45) * 0.35
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(seed >> 8) / Float(1 << 24) * 2 - 1
            noiseState += (white - noiseState) * 0.25
            let hiss = Double(noiseState) * exp(-t * 140) * 0.35
            let attack = min(t / 0.0015, 1)
            samples[i] = Int16(max(-1, min(1, (tap + hiss) * attack)) * 32_000)
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        samples.withUnsafeBufferPointer { data.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: Int(byteCount))) }
        return data
    }
}
