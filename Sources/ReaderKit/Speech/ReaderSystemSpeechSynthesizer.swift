//
//  ReaderSystemSpeechSynthesizer.swift
//  ReaderKit — Speech
//
//  基于系统 `AVSpeechSynthesizer` 的设备端合成实现。
//
//  ---------------------------------------------------------------------------
//  本文件的合成状态机设计衍生自 Readium swift-toolkit 的 `AVTTSEngine`，
//  按其许可保留版权声明：
//
//  Copyright 2024 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the LICENSE file present in the Github repository of the project.
//  ---------------------------------------------------------------------------
//
//  为什么需要一个显式状态机，而不是直接调 speak / stop：
//  上一条 utterance 的开始或结束回调还没到达时提交新的 utterance，会让
//  `AVSpeechSynthesizer` 内部死锁 —— 表现为朗读整体卡住、后续所有 speak 都无声，
//  且不报错。该问题在 iOS 15 上出现，正是本库最低支持的版本，所以必须规避。
//
//  规避手段就是本类的核心：**只在 idle 状态提交新片段**，其余状态一律拒绝，
//  由调用方先 stop() 并等取消回调到达后再提交。
//

import AVFoundation
import Foundation

/// 设备端语音合成。
public final class ReaderSystemSpeechSynthesizer: NSObject, ReaderSpeechSynthesizing {

    // MARK: - 对外状态

    public private(set) var state: ReaderSpeechState = .idle

    /// 当前片段内已开始朗读的字符数。由 `willSpeakRangeOfSpeechString` 维护。
    ///
    /// 只做一次整数赋值、不触发任何重绘，所以开启逐词回调的开销可以忽略 ——
    /// 当初拒绝**词级高亮**是因为要重算矩形并重绘 CoreText，与这里不是一回事。
    public private(set) var spokenPrefixLength: Int = 0

    public weak var delegate: ReaderSpeechSynthesizingDelegate?

    // MARK: - 内部持有

    /// 合成器实例。
    ///
    /// 复用同一个实例而不是每句新建：`AVSpeechSynthesizer` 多实例并发工作时会互相
    /// 干扰（后启动的会让先前的提前收尾），单实例 + 状态机是可控的做法。
    private let synthesizer = AVSpeechSynthesizer()

    /// 当前提交给系统的 utterance。用于在回调里辨认「这是不是我现在关心的那一条」。
    private var currentUtterance: AVSpeechUtterance?

    /// 当前片段。回调时原样带回给编排层。
    private var currentFragment: ReaderSpeechFragment?

    // MARK: - 构造

    public override init() {

        super.init()

        synthesizer.delegate = self

        // 关于 usesApplicationAudioSession：
        //
        // 试过置 false（让合成器用自己独立的会话），结果是锁屏 / 控制中心**完全不显示**
        // 播放信息 —— 音频从合成器私有会话流出，而我们激活的 App 会话没有音频，系统
        // 无法把 Now Playing 归给任何一方。比「有信息但按钮弹回」更糟，已回退。
        //
        // 所以保持默认 true：合成器用 App 会话，音频从我们激活的 .playback 会话流出，
        // 我们才是明确的 Now Playing 主源。控制中心暂停按钮弹回是另一回事，另行解决。
    }

    // MARK: - 朗读控制

    public func speak(_ fragment: ReaderSpeechFragment) {

        // 状态机的唯一入口条件。放宽这里等于放弃整套死锁规避。
        guard state == .idle else {

            delegate?.speechSynthesizer(self, didFailWith: .engineRejected)

            return
        }

        guard !fragment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {

            delegate?.speechSynthesizer(self, didFailWith: .engineRejected)

            return
        }

        guard let voice = resolveVoice(for: fragment) else {

            delegate?.speechSynthesizer(self, didFailWith: .voiceUnavailable)

            return
        }

        // 新片段，逐词进度归零
        spokenPrefixLength = 0

        let utterance = AVSpeechUtterance(string: fragment.text)

        utterance.voice = voice

        utterance.rate = Self.clampedRate(multiplier: fragment.rateMultiplier)

        currentUtterance = utterance

        currentFragment = fragment

        state = .speaking

        synthesizer.speak(utterance)
    }

    /// ⚠️ **`ReaderSpeechController` 已不再调用本方法。**
    ///
    /// 它把「暂停」实现为 `stop()` + 记录已读进度，恢复时重新提交剩余部分。原因是
    /// `pauseSpeaking` / `continueSpeaking` 这一对 API 不可靠：`continueSpeaking()`
    /// 可能不出声也不投递任何回调，而暂停态下的 `stop()` 又必须先调一次
    /// `continueSpeaking()` 才能保证取消回调到达（见下方 `stop()`）——
    /// 两者叠加会让引擎永久停在 `.stopping`，此后所有提交被拒，朗读彻底哑掉。
    ///
    /// 方法保留在协议里，是为了让能保证这对 API 可靠的自定义实现仍可使用。
    public func pause() {

        guard state == .speaking else { return }

        // 按词边界暂停而不是 .immediate：后者会把当前词切一半，
        // 继续时听感是重复或吞字。
        synthesizer.pauseSpeaking(at: .word)

        state = .paused
    }

    /// ⚠️ **`ReaderSpeechController` 已不再调用本方法**，原因见 `pause()`。
    public func resume() {

        guard state == .paused else { return }

        synthesizer.continueSpeaking()

        state = .speaking
    }

    public func stop() {

        guard state == .speaking || state == .paused else { return }

        let wasPaused = (state == .paused)

        state = .stopping

        // 暂停态下直接 stopSpeaking，在部分系统版本上不会投递取消回调，
        // 于是状态永远停在 .stopping、后续 speak 全被拒绝，朗读彻底哑掉。
        // 先 continueSpeaking 让它回到出声状态，再 stop，可确保回调到达。
        if wasPaused { synthesizer.continueSpeaking() }

        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - 音色解析

    /// 解析片段要用的系统音色。
    ///
    /// 两级：先用编排层给的标识，失效则按语言重选。
    /// **不退到系统默认音色**（`utterance.voice = nil`）—— 那个跟随设备语言，
    /// 在英文设备上读中文正文会念成一串乱音，不如明确报错让上层提示用户。
    private func resolveVoice(for fragment: ReaderSpeechFragment) -> AVSpeechSynthesisVoice? {

        if let identifier = fragment.voiceIdentifier,
           let voice = ReaderSpeechVoiceCatalog.systemVoice(identifier: identifier) {

            return voice
        }

        // 标识失效的常见原因：换了设备、系统升级、用户删掉了下载的增强音色
        if let language = fragment.language,
           let fallback = ReaderSpeechVoiceCatalog.defaultVoice(forLanguage: language),
           let voice = ReaderSpeechVoiceCatalog.systemVoice(identifier: fallback.identifier) {

            return voice
        }

        return nil
    }

    /// 把语速倍率换算成引擎语速并夹到合法区间。
    private static func clampedRate(multiplier: Float) -> Float {

        let raw = AVSpeechUtteranceDefaultSpeechRate * multiplier

        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, raw))
    }

    // MARK: - 收尾

    private func clearCurrent() {

        currentUtterance = nil

        currentFragment = nil
    }

    /// 系统回调的投递线程不保证是主线程，而状态机与编排层都按主线程假设工作，
    /// 统一在这里收口。
    private func performOnMain(_ work: @escaping () -> Void) {

        if Thread.isMainThread {

            work()

        }else{

            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ReaderSystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self,
                  utterance === self.currentUtterance,
                  let fragment = self.currentFragment else { return }

            self.delegate?.speechSynthesizer(self, didStart: fragment)
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self,
                  utterance === self.currentUtterance,
                  let fragment = self.currentFragment else { return }

            self.clearCurrent()

            // stop() 已经发出、这条 didFinish 只是旧片段的收尾时，绝不能当成
            // 「正常读完」上报 —— 编排层收到 didFinish 会推进到下一句，
            // 于是刚被用户停掉的朗读又自己接着读下去了。
            if self.state == .stopping {

                self.state = .idle

                self.delegate?.speechSynthesizer(self, didCancel: fragment)

                return
            }

            self.state = .idle

            self.delegate?.speechSynthesizer(self, didFinish: fragment)
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self,
                  utterance === self.currentUtterance,
                  let fragment = self.currentFragment else { return }

            self.clearCurrent()

            self.state = .idle

            self.delegate?.speechSynthesizer(self, didCancel: fragment)
        }
    }

    /// 逐词进度。**只用来记录读到哪里**，供「暂停后从原处继续」使用，不做任何绘制。
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  willSpeakRangeOfSpeechString characterRange: NSRange,
                                  utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self, utterance === self.currentUtterance else { return }

            self.spokenPrefixLength = characterRange.location
        }
    }

    /// 引擎确认已暂停。
    ///
    /// `pause()` 里那次 `state = .paused` 只是**预期**；本回调才是事实。
    /// 接上它是为了让 `state` 可信 —— 编排层的 `resume()` 会拿 `state` 判断
    /// 「引擎还在暂停态吗」，据此决定是继续还是重读当前句。那个判断建立在
    /// 预期值上就没有意义。
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self, utterance === self.currentUtterance else { return }

            // 正在停止的过程中收到 didPause 不要覆盖 .stopping，
            // 否则 stop() 的收尾判断会错乱
            guard self.state != .stopping else { return }

            self.state = .paused
        }
    }

    /// 引擎确认已恢复出声。
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {

        performOnMain { [weak self] in

            guard let self, utterance === self.currentUtterance else { return }

            guard self.state != .stopping else { return }

            self.state = .speaking
        }
    }
}
