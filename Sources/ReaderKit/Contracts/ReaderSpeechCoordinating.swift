//
//  ReaderSpeechCoordinating.swift
//  Reader Engine — Contracts
//
//  朗读能力的宿主扩展点。
//
//  设计口径：**不注入也完整可用**。库内自带音频会话管理、后台播放与锁屏控制，
//  接入方什么都不实现，朗读功能就已经是成品。本协议存在的意义是三件事：
//
//  1. 让接入方在必要时**接管**库的默认行为（自己管音频会话、自己管锁屏）
//  2. 让接入方**拦截**朗读开始（典型场景：激励视频广告正在占用音频）
//  3. 把朗读状态与上下文**抛出去**，供接入方实现库内做不到的能力
//
//  第 3 点是 Live Activity 的落点。ActivityKit 需要 Widget Extension target 与
//  App Group，属 App 层能力，库内不可能承载（也刻意不引用 ActivityKit），
//  所以只把状态与中立上下文抛出，由接入方决定要不要驱动灵动岛卡片。
//
//  注意灵动岛的「正在播放」呈现本身**不需要** Live Activity —— 库填好
//  `MPNowPlayingInfoCenter` 后系统就会自动呈现。只有要自定义卡片 UI 才需要 ActivityKit。
//

import Foundation
import UIKit

/// 朗读的对外活动状态。
///
/// 与 `ReaderSpeechState` 的区别：后者是**合成引擎**的内部状态机（含 `stopping`
/// 这类过渡态），只服务于避免引擎死锁；本枚举是**用户视角**的状态，
/// 用于驱动界面与对外通报，不暴露过渡态。
public enum ReaderSpeechActivity {

    /// 未在朗读。
    case idle

    /// 正在朗读。
    case playing

    /// 已暂停，位置保留。
    case paused
}

/// 朗读上下文快照。
///
/// 字段刻意只用 Foundation 类型，不引用任何业务模型 —— 接入方拿它去填
/// 锁屏元数据、Live Activity 或埋点，不该因此被迫依赖引擎的内部模型。
public struct ReaderSpeechContext {

    /// 书名。
    public let bookTitle: String

    /// 当前章节名。
    public let chapterTitle: String

    /// 当前朗读的句子文本。空串表示当前没有正在朗读的句。
    public let sentenceText: String

    /// 当前句在本章内的位置比例，取值 0...1。
    ///
    /// 这是**章内**进度而非全书进度，也不是时间进度 ——
    /// `AVSpeechSynthesizer` 不提供音频时长，任何时间维度的进度都只能是估算。
    public let chapterProgress: Double

    public init(bookTitle: String, chapterTitle: String, sentenceText: String, chapterProgress: Double) {
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        self.sentenceText = sentenceText
        self.chapterProgress = chapterProgress
    }
}

/// 朗读的宿主协调扩展点。
///
/// 全部成员都有默认实现，接入方只实现关心的部分即可。
public protocol ReaderSpeechCoordinating: AnyObject {

    /// 由接入方接管 `AVAudioSession`。
    ///
    /// 返回 true 时库内不再调用 `setCategory` / `setActive` / `setActive(false)`。
    /// 适用场景：App 内已有统一的音频路由管理（例如同时存在短剧播放器）。
    var managesAudioSessionExternally: Bool { get }

    /// 由接入方接管 `MPNowPlayingInfoCenter` 与 `MPRemoteCommandCenter`。
    ///
    /// 返回 true 时库内不写播放信息、也不注册远程命令。
    /// 适用场景：App 内有多个播放源需要竞争同一个进程级单例，须由 App 统一裁决。
    var managesNowPlayingExternally: Bool { get }

    /// 朗读期间是否把其它 App 的音频**压低**而不是打断。
    ///
    /// ⚠️ **与锁屏播放信息互斥，默认 false。** 压低靠的是 `AVAudioSession` 的
    /// `.duckOthers`，它会把会话性质变成「与其它音频共存」，系统于是不再把朗读当作
    /// 主播放源，锁屏 / 控制中心的「正在播放」卡片就不出现了。
    ///
    /// 后台播放不受影响（那只依赖 `.playback` 与 `UIBackgroundModes: audio`），
    /// 所以开启后的现象是「后台播放正常、锁屏没信息」。
    ///
    /// 需要边听书边留着背景音乐、且不要锁屏卡片时才置 true。
    var speechDucksOtherAudio: Bool { get }

    /// 朗读即将开始，接入方可否决。
    ///
    /// 返回 false 则本次朗读不启动。典型用途：激励视频广告正在播放，
    /// 此时启动朗读会与广告抢音频。
    func speechShouldBegin() -> Bool

    /// 提供锁屏 / 控制中心显示的封面图。
    ///
    /// 由接入方提供而非库内加载：书封是网络图，缓存策略与解码属接入方的基础设施，
    /// 库保持零网络依赖。返回 nil 时锁屏不显示封面，其余信息照常展示。
    func nowPlayingArtwork() -> UIImage?

    /// 朗读活动状态发生变化。
    ///
    /// - Parameters:
    ///   - activity: 变化后的状态
    ///   - context: 变化时刻的上下文快照
    func speechDidChangeActivity(_ activity: ReaderSpeechActivity, context: ReaderSpeechContext)
}

// MARK: - 默认实现

/// 全默认实现，使本协议的每一项都是可选的。
public extension ReaderSpeechCoordinating {

    var managesAudioSessionExternally: Bool { false }

    var managesNowPlayingExternally: Bool { false }

    var speechDucksOtherAudio: Bool { false }

    func speechShouldBegin() -> Bool { true }

    func nowPlayingArtwork() -> UIImage? { nil }

    func speechDidChangeActivity(_ activity: ReaderSpeechActivity, context: ReaderSpeechContext) {}
}
