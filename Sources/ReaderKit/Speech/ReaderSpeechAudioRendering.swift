//
//  ReaderSpeechAudioRendering.swift
//  ReaderKit — Speech
//
//  「文本 → 音频数据」的抽象契约。**不出声。**
//
//  与 `ReaderSpeechSynthesizing` 的分工：
//
//  - 本协议负责**产出音频**，出声由 `ReaderSpeechPlayer`（`AVPlayer`）负责。
//    这是正常路径。之所以要绕这一圈，是因为 `AVSpeechSynthesizer` 直接出声时
//    系统不把它当作可观测的播放源 —— 从 App 内暂停时锁屏状态不会跟着变，
//    而 `AVPlayer` 的状态变化系统能直接看到。原委见
//    `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。
//  - `ReaderSpeechSynthesizing`（直接出声）保留作**降级路径**：`write` 本身没有
//    `speak` 稳（某些音色不允许导出、系统异常时可能永不回调），失败时必须还能听书。
//
//  硬约束同 `ReaderSpeechSynthesizing`：本文件**不引用 AVFoundation**。
//

import Foundation

/// 音频渲染失败的原因。
///
/// 刻意与 `ReaderSpeechError` 分开，不复用：两者的处理策略完全不同 ——
/// 渲染失败要走降级继续朗读，而出声失败（降级路径自己也失败）才是真的读不了。
public enum ReaderSpeechRenderError: Error {

    /// 设备上没有可用于当前语言的音色。
    case voiceUnavailable

    /// 文本为空或只有空白。
    case emptyText

    /// 超时。
    ///
    /// 必须与 `renderFailed` 区分：系统侧异常时 `AVSpeechSynthesizer.write` 可能
    /// **永不回调**，没有超时兜底会静默卡死整条朗读链。超时是预期内的失败，
    /// 不代表实现有 bug。
    case timedOut

    /// 其它渲染失败（音频格式异常、数据为空等）。
    case renderFailed
}

public extension ReaderSpeechRenderError {

    /// 是否属于「再试一次可能就好了」的瞬时性失败。
    ///
    /// 超时与渲染失败多半是系统侧 TTS 服务一时抽风（`write` 偶发不回调、返回空数据），
    /// 同一句重提一次通常就成了。
    ///
    /// 音色不可用与空文本不在此列：重试一万次结果都一样，只会白等一个超时周期。
    var isTransient: Bool {

        switch self {

        case .timedOut, .renderFailed: return true

        case .voiceUnavailable, .emptyText: return false
        }
    }
}

/// 把文本渲染成音频数据。
public protocol ReaderSpeechAudioRendering: AnyObject {

    /// 渲染一个片段。
    ///
    /// - Parameters:
    ///   - fragment: 待渲染片段
    ///   - timeout: 超时上限。超时以 `.timedOut` 回调，且实现方须保证**回调只发生一次**
    ///     （超时与渲染完成会竞争）
    ///   - completion: 结果回调，**在主线程**投递
    ///
    /// 实现方须保证：多次调用之间**串行**执行。`AVSpeechSynthesizer.write` 并发跑时
    /// 会互相干扰，后启动的会让先前的提前收到空 buffer，产出**截断音频** ——
    /// 而截断音频的文件名（内容哈希）看起来是有效的，会被缓存当成正常结果复用。
    func render(_ fragment: ReaderSpeechFragment,
                timeout: TimeInterval,
                completion: @escaping (Result<Data, ReaderSpeechRenderError>) -> Void)

    /// 取消所有未完成的渲染。
    ///
    /// 用于换句 / 换章 / 停止朗读时丢弃在途的预渲染任务。
    /// 已经开始的那一个无法真正中断（`write` 没有取消接口），实现方应保证它的结果被丢弃。
    func cancelAll()
}
