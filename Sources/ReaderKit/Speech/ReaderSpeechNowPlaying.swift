//
//  ReaderSpeechNowPlaying.swift
//  ReaderKit — Speech
//
//  锁屏 / 控制中心 / 灵动岛的播放信息与远程控制。
//
//  灵动岛不需要 ActivityKit：`MPNowPlayingInfoCenter` 填好之后，系统会自动在锁屏、
//  控制中心与灵动岛呈现「正在播放」。只有要自定义卡片 UI 才需要 Live Activity，
//  那属 App 层能力（需要 Widget Extension target），不在库内。
//
//  ⚠️ 两条硬约束：
//
//  1. `MPRemoteCommandCenter` 是**进程级全局单例**。注册时拿到的 target token
//     必须在释放时逐个摘除，否则每个曾经存在过的实例都会永久占住锁屏控制的响应链，
//     表现为「反复进出阅读器后，锁屏按钮点了没反应或响应到了已销毁的会话」。
//
//  2. 播放时长与已播时间**必须写**，即便只能是按字符数折算的估算值。
//     曾经因为「`AVSpeechSynthesizer` 拿不到真实时长、估算值与听感对不上」而不写，
//     代价是控制中心的播放暂停按钮状态对不上：系统会先乐观改按钮，再读
//     `nowPlayingInfo` 复核，复核不到时间锚点就把按钮弹回去 ——
//     现象是「点了暂停，声音确实停了，图标却马上变回播放中」。
//     锁屏时 App 在后台，系统更多靠「有没有真的输出音频」判断，所以那边看不出来。
//     结论：进度条秒数不准可以接受，播放状态显示错误不能接受。
//     拖动进度仍不开放（`changePlaybackPositionCommand` 保持禁用），
//     因为估算值不足以支撑精确落点。
//

import Foundation
import MediaPlayer
import UIKit

/// 远程命令的响应者。
protocol ReaderSpeechRemoteCommandDelegate: AnyObject {

    /// 当前是否有可响应的朗读会话。为 false 时本类会告知系统「无可操作项」。
    var canRespondToRemoteCommand: Bool { get }

    func remoteCommandRequestsPlay()

    func remoteCommandRequestsPause()

    func remoteCommandRequestsToggle()

    /// 上一曲 → 上一章。
    func remoteCommandRequestsPreviousChapter()

    /// 下一曲 → 下一章。
    func remoteCommandRequestsNextChapter()
}

/// 锁屏播放信息与远程控制。
final class ReaderSpeechNowPlaying {

    weak var delegate: ReaderSpeechRemoteCommandDelegate?

    /// 由接入方接管时置 true，本类不写播放信息、也不注册远程命令。
    ///
    /// 存在理由：`MPNowPlayingInfoCenter` 与 `MPRemoteCommandCenter` 都是进程级单例，
    /// 一个 App 里若有多个播放源（如另有短剧播放器），必须由 App 统一裁决谁占用，
    /// 库不该擅自抢。
    var isManagedExternally: Bool = false

    /// 已注册的远程命令与其 target token。**进程级**。
    ///
    /// 必须成对保存：`removeTarget(nil)` 只能清掉「本进程所有」target，
    /// 在多播放源场景会误伤别人；按 token 精确摘除才安全。
    ///
    /// **必须是静态的**：`MPRemoteCommandCenter` 是全局单例，token 也只能通过它摘除。
    /// 曾经存在过的会话若没能走完 `deinit` / `deactivate()`（阅读器被销毁但朗读没进 idle、
    /// 异常退出路径等），它的 handler 会永久留在响应链上，而新实例**摘不掉别人的 token**。
    /// 此后点锁屏 / 控制中心按钮，系统会同时收到「已处理」与「无可操作项」两种结果，
    /// 可能据此判定命令失败并把按钮弹回原状 —— 现象是「声音确实停了、图标却马上变回
    /// 播放中」，而且**随进出阅读器的次数累积而变严重**（所以有时在锁屏页测不出来：
    /// 那一轮的响应链还干净）。
    ///
    /// 存成静态后，任何实例注册前都能把上一套摘干净，全局永远只有一套活跃 handler。
    nonisolated(unsafe) private static var registeredCommands: [(command: MPRemoteCommand, token: Any)] = []

    deinit {
        releaseCommandCenter()

        clearNowPlaying()
    }

    // MARK: - 启用与停用

    /// 朗读开始时调用：注册远程命令并开始接收远程控制事件。
    func activate() {

        guard !isManagedExternally else { return }

        configureCommandCenterIfNeeded()

        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    /// 朗读停止时调用：清空播放信息并摘除命令。
    func deactivate() {

        guard !isManagedExternally else { return }

        releaseCommandCenter()

        clearNowPlaying()

        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    // MARK: - 播放信息

    /// 刷新锁屏播放信息。
    ///
    /// - Parameters:
    ///   - context: 朗读上下文（书名、章节名等）
    ///   - activity: 当前活动状态，决定播放速率字段
    ///   - artwork: 封面图，由接入方提供；为 nil 时不显示封面
    func update(context: ReaderSpeechContext, activity: ReaderSpeechActivity, artwork: UIImage?) {

        guard !isManagedExternally else { return }

        guard activity != .idle else {

            clearNowPlaying()

            return
        }

        var info: [String: Any] = [:]

        // 标题给章节名、专辑给书名：锁屏上标题是最醒目的一行，
        // 听书时用户更需要知道「读到哪一章」而不是重复看书名
        info[MPMediaItemPropertyTitle] = context.chapterTitle

        info[MPMediaItemPropertyAlbumTitle] = context.bookTitle

        // 暂停时速率必须置 0，否则锁屏界面仍显示为播放中
        info[MPNowPlayingInfoPropertyPlaybackRate] = (activity == .playing) ? 1.0 : 0.0

        // **时间轴必须一起给。** 只改 playbackRate 不足以让系统确认状态变更：
        // 控制中心会先乐观地把按钮改掉，再读 nowPlayingInfo 复核，复核不到时间锚点
        // 就把按钮弹回原状 —— 表现为「点了暂停，声音确实停了，图标却马上变回播放中」。
        // 锁屏时 App 在后台，系统更多靠「有没有真的输出音频」判断，所以那边看不出问题。
        //
        // 值是按字符数折算的估算（见 `ReaderSpeechContext.estimatedDuration`）：
        // 比例正确，绝对秒数不准。`AVSpeechSynthesizer` 拿不到真实时长，
        // 而「有个比例对的时间轴」比「状态显示错误」可接受得多。
        if context.estimatedDuration > 0 {

            info[MPMediaItemPropertyPlaybackDuration] = context.estimatedDuration

            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = context.estimatedElapsed
        }

        if let artwork {

            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }

        ReaderEnvironment.log("[Speech] 写锁屏信息 activity=\(activity) rate=\(info[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil") elapsed=\(Int(context.estimatedElapsed))/\(Int(context.estimatedDuration))s artwork=\(artwork != nil)")

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 远程命令

    private func configureCommandCenterIfNeeded() {

        // 注册前先把上一套摘干净。**不做「已注册就跳过」的短路** ——
        // 需要保证的是「全局只有一套活跃 handler」，而不是「本实例只注册一次」。
        // 上一个会话可能没走完 deinit，它的 token 只能由这里代为摘除。
        Self.releaseRegisteredCommands()

        let center = MPRemoteCommandCenter.shared()

        register(center.playCommand) { [weak self] in self?.delegate?.remoteCommandRequestsPlay() }

        register(center.pauseCommand) { [weak self] in self?.delegate?.remoteCommandRequestsPause() }

        register(center.togglePlayPauseCommand) { [weak self] in self?.delegate?.remoteCommandRequestsToggle() }

        // 上一曲 / 下一曲映射为上一章 / 下一章。听书语境下「一章 = 一个 track」
        // 比「一句」更符合直觉，句级跳转粒度太细、在锁屏上几乎没法用
        register(center.previousTrackCommand) { [weak self] in self?.delegate?.remoteCommandRequestsPreviousChapter() }

        register(center.nextTrackCommand) { [weak self] in self?.delegate?.remoteCommandRequestsNextChapter() }

        // 刻意不注册 changePlaybackPositionCommand：没有真实时长，拖动进度无从落点
        center.changePlaybackPositionCommand.isEnabled = false
    }

    /// 注册单个命令。
    private func register(_ command: MPRemoteCommand, action: @escaping () -> Void) {

        command.isEnabled = true

        let token = command.addTarget { [weak self] _ in

            // 会话已不存在时报告「无可操作项」而不是 .commandFailed：
            // 前者会让系统把控制权交给仍存活的其它响应者，后者只是单纯失败
            guard let self, self.delegate?.canRespondToRemoteCommand == true else {

                ReaderEnvironment.log("[Speech] 远程命令到达但会话不可响应，回报 noActionableNowPlayingItem")

                return .noActionableNowPlayingItem
            }

            action()

            return .success
        }

        Self.registeredCommands.append((command, token))
    }

    /// 摘除全部已注册命令。
    private func releaseCommandCenter() {

        Self.releaseRegisteredCommands()
    }

    /// 摘除进程内全部已注册命令。
    private static func releaseRegisteredCommands() {

        guard !registeredCommands.isEmpty else { return }

        ReaderEnvironment.log("[Speech] 摘除远程命令 target，共 \(registeredCommands.count) 个")

        for entry in registeredCommands {

            entry.command.removeTarget(entry.token)
        }

        registeredCommands.removeAll()
    }
}
