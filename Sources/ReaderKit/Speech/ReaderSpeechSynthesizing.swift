//
//  ReaderSpeechSynthesizing.swift
//  ReaderKit — Speech
//
//  语音合成的抽象契约。
//
//  为什么要这层抽象：一期用设备端 `AVSpeechSynthesizer`（免费、零延迟、无网络依赖），
//  二期若换云端音色，只替换实现即可，编排层（`ReaderSpeechController`）不动。
//
//  硬约束：本文件**不引用 AVFoundation**。一旦协议里出现 `AVSpeechUtterance`
//  或 `AVSpeechSynthesisVoice`，抽象就名存实亡了。
//

import Foundation

/// 合成引擎的显式状态。
///
/// 为什么必须显式维护而不是靠 `AVSpeechSynthesizer.isSpeaking` 之类的查询属性：
/// 上一条 utterance 的开始 / 结束回调尚未到达时提交新 utterance，会让引擎死锁
/// （该问题在 iOS 15 上出现，正是本库最低支持的版本）。要避开它，就得知道
/// 「上一条到底结束没有」，而这只能靠自己记状态机。
public enum ReaderSpeechState {

    /// 空闲。**只有这个状态下才允许提交新片段。**
    case idle

    /// 正在朗读。
    case speaking

    /// 已暂停，位置保留，可继续。
    case paused

    /// 已请求停止，但引擎的取消回调还没到。
    ///
    /// 这个中间态是状态机的关键：停止后不能立刻当成 `idle`，
    /// 否则紧接着提交的新片段就会撞上还没收尾的旧片段。
    case stopping
}

/// 一个待朗读的片段，对应一个句。
public struct ReaderSpeechFragment: Equatable {

    /// 待朗读文本。
    public let text: String

    /// 该片段在**章内绝对坐标**中的范围。
    ///
    /// 引擎本身不使用它，但回调时会原样带回，供编排层判断「回调对应哪一句」，
    /// 以及驱动高亮与翻页。
    public let range: NSRange

    /// 音色标识。正常情况下由编排层解析好后传入。
    ///
    /// 为 nil、或该标识在当前设备上已失效时，实现方应退到按 `language` 选取，
    /// 而**不是**交给系统默认音色 —— 系统默认音色跟随设备语言，
    /// 在英文设备上读中文正文会念成一串乱音。
    public let voiceIdentifier: String?

    /// 内容语言标签（BCP-47，如 `zh-Hans`）。音色标识失效时的兜底依据。
    public let language: String?

    /// 语速倍率，`1.0` 表示引擎默认语速。
    ///
    /// 用倍率而不是引擎的原始语速值：`AVSpeechUtteranceDefaultSpeechRate` 是
    /// AVFoundation 特有的量纲，写进协议就把契约绑到具体实现上了。
    public let rateMultiplier: Float

    public init(text: String,
                range: NSRange,
                voiceIdentifier: String?,
                language: String? = nil,
                rateMultiplier: Float = 1.0) {
        self.text = text
        self.range = range
        self.voiceIdentifier = voiceIdentifier
        self.language = language
        self.rateMultiplier = rateMultiplier
    }
}

/// 合成失败的原因。
public enum ReaderSpeechError: Error {

    /// 设备上没有可用于当前语言的音色。
    case voiceUnavailable

    /// 引擎拒绝了本次合成请求（状态不允许、文本为空等）。
    case engineRejected
}

/// 语音合成引擎。
public protocol ReaderSpeechSynthesizing: AnyObject {

    /// 当前状态。
    var state: ReaderSpeechState { get }

    /// 结果回调接收者。
    var delegate: ReaderSpeechSynthesizingDelegate? { get set }

    /// 提交一个片段开始朗读。
    ///
    /// 实现方**必须**在 `state != .idle` 时拒绝本次提交（回调 `didFailWith(.engineRejected)`），
    /// 而不是排队或强行插入 —— 排队会把状态机的意义抹掉。
    /// 调用方需要换句时应先 `stop()`，等 `didCancel` 到达后再提交。
    func speak(_ fragment: ReaderSpeechFragment)

    /// 暂停，保留当前位置。
    func pause()

    /// 从暂停位置继续。
    func resume()

    /// 停止并丢弃当前片段。
    ///
    /// 实现方应立即进入 `.stopping`，在收到引擎的取消回调后才转 `.idle`。
    func stop()
}

/// 合成引擎的结果回调。
///
/// 刻意**不提供默认实现**：这四个回调各自对应编排层的一个必要动作
/// （高亮、推进、换句收尾、报错），漏实现任何一个都会表现为
/// 「读一句就停」或「高亮不动」这类难查的问题，交给编译器拦住更划算。
public protocol ReaderSpeechSynthesizingDelegate: AnyObject {

    /// 片段开始出声。
    ///
    /// 高亮与翻页应挂在这里而不是 `speak(_:)` 调用处 —— 引擎从收到请求到真正
    /// 出声之间有延迟，提前高亮会让画面比声音快一截。
    func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didStart fragment: ReaderSpeechFragment)

    /// 片段正常读完。编排层据此推进到下一句。
    func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didFinish fragment: ReaderSpeechFragment)

    /// 片段被取消（`stop()` 的结果）。引擎此时已回到 `.idle`，可以安全提交新片段。
    func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didCancel fragment: ReaderSpeechFragment)

    /// 合成失败。
    func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didFailWith error: ReaderSpeechError)
}
