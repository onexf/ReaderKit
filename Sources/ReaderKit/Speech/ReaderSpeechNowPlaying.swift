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
//  2. 本类**不写播放时长与已播时间**。`AVSpeechSynthesizer` 不提供音频时长，
//     写进去的只能是按字数估算的假值：锁屏进度条会与实际听感对不上，
//     用户拖动后落点也不准。所以锁屏只给章节名、书名、封面与播放控制。
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

    /// 已注册的远程命令与其 target token。
    ///
    /// 必须成对保存：`removeTarget(nil)` 只能清掉「本进程所有」target，
    /// 在多播放源场景会误伤别人；按 token 精确摘除才安全。
    private var registeredCommands: [(command: MPRemoteCommand, token: Any)] = []

    /// 命令是否已注册，避免重复注册。
    private var isCommandCenterConfigured: Bool = false

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

        if let artwork {

            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }

        // 刻意不写 MPMediaItemPropertyPlaybackDuration 与
        // MPNowPlayingInfoPropertyElapsedPlaybackTime，理由见文件头第 2 条

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 远程命令

    private func configureCommandCenterIfNeeded() {

        guard !isCommandCenterConfigured else { return }

        isCommandCenterConfigured = true

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

                return .noActionableNowPlayingItem
            }

            action()

            return .success
        }

        registeredCommands.append((command, token))
    }

    /// 摘除全部已注册命令。
    private func releaseCommandCenter() {

        for entry in registeredCommands {

            entry.command.removeTarget(entry.token)
        }

        registeredCommands.removeAll()

        isCommandCenterConfigured = false
    }
}
