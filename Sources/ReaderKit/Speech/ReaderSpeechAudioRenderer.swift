//
//  ReaderSpeechAudioRenderer.swift
//  ReaderKit — Speech
//
//  基于 `AVSpeechSynthesizer.write(_:toBufferCallback:)` 的音频渲染实现。**不出声。**
//
//  ---------------------------------------------------------------------------
//  本文件的踩坑点全部来自参考实现（扶摇 FM，Apache-2.0）的实测经验，逐条记在对应位置：
//  串行闸门、空 buffer 语义、三种 PCM 格式归一、`withExtendedLifetime`、WAV 容器头、超时。
//  这些坑没有一条能从文档看出来，删任何一条之前请先读它上面的注释。
//  ---------------------------------------------------------------------------
//

import AVFoundation
import Foundation

/// 设备端音频渲染。
///
/// 不继承 `NSObject` —— 与 `ReaderSystemSpeechSynthesizer` 不同，本类不需要接
/// `AVSpeechSynthesizerDelegate`（`write` 用的是 buffer 回调闭包），
/// 也就没有走 ObjC 运行时的必要。
public final class ReaderSpeechAudioRenderer: ReaderSpeechAudioRendering {

    public init() {}

    // MARK: - 内部持有

    /// 渲染串行队列。
    ///
    /// **不能并发。** 多个 `AVSpeechSynthesizer` 同时 `write` 会互相干扰：
    /// 后启动的会让先前的提前收到空 buffer（也就是「结束」信号），
    /// 于是先前那个产出一段**截断音频**。而截断音频的内容哈希是有效文件名，
    /// 会被缓存当成正常结果长期复用 —— 表现为「某几句总是只读一半」，
    /// 且清缓存前不会自愈。
    private let renderQueue = DispatchQueue(label: "com.readerkit.speech.audio-renderer")

    /// 合成器实例。**复用同一个，不每次新建。**
    ///
    /// 崩溃修复：原先每渲染一句就 `AVSpeechSynthesizer()` 新建、函数返回即释放。
    /// 连续听书会在短时间内创建销毁成百上千个系统对象，而 `TextToSpeech.framework`
    /// 内部（`AXSpeech` 线程）仍可能持有回调，最终在系统框架里
    /// `EXC_BAD_ACCESS` —— 现象正是「播着播着崩溃」，累积到一定次数才发作。
    ///
    /// 库内既有的 `ReaderSystemSpeechSynthesizer` 早就写明了这条经验
    /// （「复用同一个实例而不是每句新建」），当初写本类时没有沿用。
    ///
    /// 复用同时也让「超时后放弃、但系统仍在写回调」这个窗口变得安全：
    /// 实例是属性，不会在函数返回时被释放。
    private let synthesizer = AVSpeechSynthesizer()

    /// 已取消的世代号。
    ///
    /// `write` 没有取消接口，已经开始的那一次无法中断，只能让它的结果作废。
    /// `cancelAll()` 递增世代号，回调里比对世代号决定是否丢弃。
    private var generation: Int = 0

    /// 保护 `generation`。渲染在队列上跑，`cancelAll()` 可能来自主线程。
    private let generationLock = NSLock()

    // MARK: - ReaderSpeechAudioRendering

    public func render(_ fragment: ReaderSpeechFragment,
                       timeout: TimeInterval,
                       completion: @escaping (Result<Data, ReaderSpeechRenderError>) -> Void) {

        let submitted = currentGeneration()

        renderQueue.async { [weak self] in

            guard let self else { return }

            // 排队期间被取消（换句 / 换章 / 停止朗读），不必再渲染
            guard self.currentGeneration() == submitted else { return }

            let result = self.renderSynchronously(fragment, timeout: timeout)

            // 渲染期间被取消，结果作废
            guard self.currentGeneration() == submitted else { return }

            DispatchQueue.main.async { completion(result) }
        }
    }

    public func cancelAll() {

        generationLock.lock()

        generation += 1

        generationLock.unlock()
    }

    // MARK: - 渲染

    /// 同步渲染。只在 `renderQueue` 上调用。
    private func renderSynchronously(_ fragment: ReaderSpeechFragment,
                                     timeout: TimeInterval) -> Result<Data, ReaderSpeechRenderError> {

        let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return .failure(.emptyText) }

        guard let voice = resolveVoice(for: fragment) else { return .failure(.voiceUnavailable) }

        let utterance = AVSpeechUtterance(string: fragment.text)

        utterance.voice = voice

        utterance.rate = Self.clampedRate(multiplier: fragment.rateMultiplier)

        let collector = BufferCollector()

        let done = DispatchSemaphore(value: 0)

        synthesizer.write(utterance) { buffer in

            guard let pcm = buffer as? AVAudioPCMBuffer else {

                if collector.finish(failed: true) { done.signal() }

                return
            }

            // **空 buffer 是 `AVSpeechSynthesizer` 约定的「渲染结束」信号**，不是错误。
            // 不识别它就只能靠超时收尾，每句都要白等一个超时周期。
            guard pcm.frameLength > 0 else {

                if collector.finish(failed: false) { done.signal() }

                return
            }

            collector.append(Self.int16LittleEndianBytes(from: pcm), sampleRate: pcm.format.sampleRate)
        }

        // 超时是必需的兜底：系统侧异常时 `write` 可能**永不回调**，
        // 没有它会静默卡死整条朗读链（连日志都不会有）。
        //
        // 不需要 `withExtendedLifetime`：合成器是本类的属性，生命周期与本类一致，
        // 不会在这里被释放。这正是改成复用实例的原因之一。
        let waited = done.wait(timeout: .now() + timeout)

        guard waited == .success else {

            collector.abandon()

            // 必须显式中断在途的 `write`。
            //
            // 复用实例后，超时只是「本次不等了」，系统侧仍在往这个合成器上写回调。
            // 不中断的话，下一句的 `write` 会和上一句未结束的 `write` 撞在同一个实例上，
            // 触发本文件开头 `renderQueue` 注释里那条坑：先前那次提前收到空 buffer，
            // 产出截断音频并被缓存长期复用。
            synthesizer.stopSpeaking(at: .immediate)

            return .failure(.timedOut)
        }

        guard !collector.failed, let pcmData = collector.take(), !pcmData.isEmpty,
              let sampleRate = collector.sampleRate else {

            return .failure(.renderFailed)
        }

        return .success(Self.wavContainer(pcm: pcmData, sampleRate: sampleRate))
    }

    // MARK: - 音色

    /// 解析片段要用的系统音色。口径与 `ReaderSystemSpeechSynthesizer` 保持一致。
    ///
    /// **不退到系统默认音色**（`utterance.voice = nil`）—— 那个跟随设备语言，
    /// 在英文设备上读中文正文会念成一串乱音，不如明确失败让上层降级或提示。
    private func resolveVoice(for fragment: ReaderSpeechFragment) -> AVSpeechSynthesisVoice? {

        if let identifier = fragment.voiceIdentifier,
           let voice = ReaderSpeechVoiceCatalog.systemVoice(identifier: identifier) {

            return voice
        }

        if let language = fragment.language,
           let fallback = ReaderSpeechVoiceCatalog.defaultVoice(forLanguage: language),
           let voice = ReaderSpeechVoiceCatalog.systemVoice(identifier: fallback.identifier) {

            return voice
        }

        return nil
    }

    private static func clampedRate(multiplier: Float) -> Float {

        let raw = AVSpeechUtteranceDefaultSpeechRate * multiplier

        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, raw))
    }

    // MARK: - 世代号

    private func currentGeneration() -> Int {

        generationLock.lock()

        defer { generationLock.unlock() }

        return generation
    }
}

// MARK: - PCM 收集

/// 累积渲染过程中投递的 PCM 分片。
///
/// 独立成类是为了把「只结束一次」这件事管死：超时与结束信号会竞争，
/// 两边都可能试图收尾，重复 signal 会让上层拿到不一致的结果。
private final class BufferCollector {

    private let lock = NSLock()

    private var chunks: [Data] = []

    private var finished = false

    private var abandoned = false

    private(set) var failed = false

    private(set) var sampleRate: Double?

    func append(_ data: Data, sampleRate rate: Double) {

        lock.lock()

        defer { lock.unlock() }

        guard !finished, !abandoned else { return }

        if sampleRate == nil { sampleRate = rate }

        chunks.append(data)
    }

    /// 标记结束。返回 true 表示这一次才是真正的收尾（应当唤醒等待方）。
    func finish(failed didFail: Bool) -> Bool {

        lock.lock()

        defer { lock.unlock() }

        guard !finished else { return false }

        finished = true

        failed = didFail

        return true
    }

    /// 超时后放弃：此后到达的分片一律丢弃。
    ///
    /// 不能只靠调用方不读结果 —— 渲染仍在后台跑，继续累积只是白占内存。
    func abandon() {

        lock.lock()

        defer { lock.unlock() }

        abandoned = true

        chunks.removeAll()
    }

    func take() -> Data? {

        lock.lock()

        defer { lock.unlock() }

        guard !abandoned else { return nil }

        return chunks.reduce(into: Data()) { $0.append($1) }
    }
}

// MARK: - PCM 格式归一与 WAV 封装

private extension ReaderSpeechAudioRenderer {

    /// 把任意 `AVAudioPCMBuffer` 取成 16-bit 小端单声道字节流。
    ///
    /// **三种格式都要处理**：`commonFormat` 在系统版本之间并不固定，
    /// 只处理 `.pcmFormatInt16` 会在某些系统上拿到空音频。
    static func int16LittleEndianBytes(from buffer: AVAudioPCMBuffer) -> Data {

        let frames = Int(buffer.frameLength)

        guard frames > 0 else { return Data() }

        var samples = [Int16]()

        samples.reserveCapacity(frames)

        switch buffer.format.commonFormat {

        case .pcmFormatInt16:

            guard let channel = buffer.int16ChannelData?[0] else { return Data() }

            let stride = buffer.stride

            for frame in 0..<frames { samples.append(channel[frame * stride]) }

        case .pcmFormatFloat32:

            guard let channel = buffer.floatChannelData?[0] else { return Data() }

            let stride = buffer.stride

            for frame in 0..<frames {

                // 先夹到 [-1, 1] 再放大：浮点样本偶尔会略微越界，
                // 不夹的话转换时会溢出成反向的爆音
                let clamped = max(-1.0, min(1.0, channel[frame * stride]))

                samples.append(Int16(clamped * 32767))
            }

        case .pcmFormatInt32:

            guard let channel = buffer.int32ChannelData?[0] else { return Data() }

            let stride = buffer.stride

            for frame in 0..<frames { samples.append(Int16(truncatingIfNeeded: channel[frame * stride] >> 16)) }

        default:

            return Data()
        }

        return samples.withUnsafeBufferPointer { pointer in

            Data(buffer: pointer)
        }
    }

    /// 给裸 PCM 补 44 字节 RIFF/WAVE 头。
    ///
    /// **不能省。** 裸 PCM 没有容器信息，`AVPlayer` 读不出时长（`duration` 为
    /// `indefinite`），锁屏时间轴与播放结束判断都会失效。
    static func wavContainer(pcm: Data, sampleRate: Double) -> Data {

        let channels: UInt16 = 1

        let bitsPerSample: UInt16 = 16

        let rate = UInt32(sampleRate)

        let byteRate = rate * UInt32(channels) * UInt32(bitsPerSample / 8)

        let blockAlign = channels * (bitsPerSample / 8)

        var header = Data()

        func appendASCII(_ text: String) { header.append(contentsOf: Array(text.utf8)) }

        func appendUInt32(_ value: UInt32) { header.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }

        func appendUInt16(_ value: UInt16) { header.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }

        appendASCII("RIFF")

        appendUInt32(UInt32(36 + pcm.count))

        appendASCII("WAVE")

        appendASCII("fmt ")

        appendUInt32(16)

        appendUInt16(1)                 // 1 = 线性 PCM，无压缩

        appendUInt16(channels)

        appendUInt32(rate)

        appendUInt32(byteRate)

        appendUInt16(blockAlign)

        appendUInt16(bitsPerSample)

        appendASCII("data")

        appendUInt32(UInt32(pcm.count))

        return header + pcm
    }
}
