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

        let utterance = AVSpeechUtterance(string: fragment.text)

        utterance.voice = voice

        utterance.rate = Self.clampedRate(multiplier: fragment.rateMultiplier)

        currentUtterance = utterance

        currentFragment = fragment

        state = .speaking

        synthesizer.speak(utterance)
    }

    public func pause() {

        guard state == .speaking else { return }

        // 按词边界暂停而不是 .immediate：后者会把当前词切一半，
        // 继续时听感是重复或吞字。
        synthesizer.pauseSpeaking(at: .word)

        state = .paused
    }

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
}
