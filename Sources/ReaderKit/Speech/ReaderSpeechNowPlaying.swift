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
//  2. 播放时长与已播时间**必须写，而且已播时间必须连续**。这一条踩过两次坑，方向相反：
//
//     - 一开始不写，理由是「`AVSpeechSynthesizer` 拿不到真实时长，估算值与听感对不上」。
//       代价是控制中心的按钮状态对不上：系统先乐观改按钮，再读 `nowPlayingInfo` 复核，
//       复核不到时间锚点就弹回去。
//     - 于是补上了，但已播时间用的是「当前句句首的字符位置折算秒数」——
//       **那个值在整句朗读期间完全不变**。系统把它当锚点、配合 rate 自己往前推，
//       我们每次刷新又写回那个不动的值，时间轴反复被拽回原处。系统看到
//       「声称在播放、时间却不走」的矛盾信息，就不再采信我们声明的 rate。
//       结果是把原本正常的**锁屏页**也弄坏了（1.7.1 的回归，当时误判成修好了一处）。
//
//     现在已播时间取**实际经过的出声时间**（连续、单调不减），总时长按字符数估算。
//     这个组合是目前最准的，但**它并没有修好锁屏按钮的状态** —— 那个是架构限制，
//     见下方 `update(context:activity:artwork:)` 里的说明。
//     拖动进度仍不开放（`changePlaybackPositionCommand` 保持禁用）——
//     总时长仍是估算值，不足以支撑精确落点。
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

    /// 当前那套 handler 属于哪个实例。
    ///
    /// 用来区分「别人留下的残留」与「自己已经注册好的」：前者必须摘除，后者不该重复注册。
    /// 1.8.0 为了摘掉旧会话的残留 token 去掉了「已注册就跳过」的短路，但那样做过了头 ——
    /// 每次恢复朗读都会走一遍 `activate()`，于是命令表被反复全表摘除重注册（日志里表现为
    /// 恢复时出现「摘除远程命令 target，共 5 个」）。功能上还能响应，但属无谓抖动。
    nonisolated(unsafe) private static var registeredOwner: ObjectIdentifier?

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
        // 时间轴播放与暂停都写。
        //
        // **不要再试「暂停时不写」** —— 试过，无效：真机日志确认暂停时写出的是
        // `timeline=omitted`，锁屏按钮照旧显示播放中，唯一的变化是暂停时进度条整个消失，
        // 纯属体验退步。把已播时间改成连续值（实际出声时长）也无效。
        // 系统采纳时间轴、就是不采纳 `rate`，症结不在这个字段的有无与取值。
        // 完整的失败清单见 `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。
        if context.estimatedDuration > 0 {

            info[MPMediaItemPropertyPlaybackDuration] = context.estimatedDuration

            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = context.estimatedElapsed
        }

        // 播放队列信息（一项 = 一章）。**对齐参考实现加的** ——
        // FM 写了这两个字段且锁屏状态正常，我们此前完全没写。
        // 它们告诉系统「这是一个有 N 项的队列、当前在第 i 项」，可能影响系统
        // 对播放源的认定方式（也是「上一曲 / 下一曲」在锁屏上可用的语义依据）。
        if context.queueCount > 0 {

            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = context.queueCount

            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = context.queueIndex
        }

        if let artwork {

            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }

        // 命令可用性与播放信息一起更新，两路信号必须同步
        reviseTransportCommandAvailability(isPlaying: activity == .playing)

        // 时间轴一栏要能看出「这次到底写没写」——「暂停时不写」正是当前方案的关键，
        // 只打印数值的话无从确认它生效了
        let timeline = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil
            ? "omitted"
            : "\(Int(context.estimatedElapsed))/\(Int(context.estimatedDuration))s"

        ReaderEnvironment.log("[Speech] 写锁屏信息 activity=\(activity) rate=\(info[MPNowPlayingInfoPropertyPlaybackRate] ?? "nil") timeline=\(timeline) queue=\(context.queueIndex)/\(context.queueCount) artwork=\(artwork != nil)")

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 远程命令

    private func configureCommandCenterIfNeeded() {

        // 已经是**本实例**注册的那一套，直接复用。
        // 要保证的是「全局只有一套活跃 handler」，这一条已经满足，没必要重注册。
        guard Self.registeredOwner != ObjectIdentifier(self) || Self.registeredCommands.isEmpty else { return }

        // 注册前把上一套摘干净。可能是上一个会话残留的 —— 它没走完 deinit 时，
        // token 只能由这里代为摘除（`MPRemoteCommandCenter` 是进程级单例，
        // 而 token 只能通过它摘）。
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

        Self.registeredOwner = ObjectIdentifier(self)
    }

    /// 按当前是否在播放，开关「播放」与「暂停」两个命令。
    ///
    /// **这是除 `playbackRate` 之外的第二路状态信号，两路都给才可靠。**
    /// 实测 iOS 26 上只写 `MPNowPlayingInfoPropertyPlaybackRate = 0` 不足以让锁屏与
    /// 控制中心的按钮图标跟着变 —— 声音已经停了、我们写的 rate 也确实是 0，
    /// 那两处却仍显示为播放中。原因是没有真实播放器时系统不完全采信 `nowPlayingInfo`
    /// （`AVSpeechSynthesizer` 直接出声不是被系统认账的 Now Playing 源）。
    ///
    /// 命令可用性是一路更硬的信号：只有「暂停」可用时，系统无从渲染出播放按钮。
    ///
    /// `togglePlayPauseCommand` 始终保持可用 —— 耳机线控与部分车机只发这一个命令，
    /// 把它一起关掉会导致线控完全失效。
    private func reviseTransportCommandAvailability(isPlaying: Bool) {

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = !isPlaying

        center.pauseCommand.isEnabled = isPlaying

        center.togglePlayPauseCommand.isEnabled = true
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

        registeredOwner = nil
    }
}
