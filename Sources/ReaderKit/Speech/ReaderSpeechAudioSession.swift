//
//  ReaderSpeechAudioSession.swift
//  ReaderKit — Speech
//
//  朗读的音频会话管理与系统中断处理。
//
//  这一层要处理的都是听书场景最容易漏、且漏了必然被用户遇到的情况：
//  来电打断、拔耳机、音频服务重置。本项目在此之前完全没有音频基础设施，
//  三类通知的处理口径参考了扶摇 FM（Apache-2.0，只取做法结论，未复制代码）。
//
//  ⚠️ 两条硬约束，写在最前面免得被改掉：
//  1. `setCategory` / `setActive` **必须在主线程调用**。非主线程会触发
//     `paramErr`（OSStatus -50），且报错只出现在系统日志里，很难查。
//  2. 朗读停止时**必须反激活会话**。后台播放权限依赖活跃的会话，
//     不反激活 App 会一直驻留后台。
//

import AVFoundation
import Foundation

/// 音频会话向朗读编排层提出的请求。
protocol ReaderSpeechAudioSessionDelegate: AnyObject {

    /// 系统要求让出音频（来电打断开始、耳机被拔出）。
    func audioSessionRequestsPause()

    /// 中断结束且系统明示可以恢复。
    func audioSessionRequestsResume()

    /// 音频服务被重置，当前会话已不可信，需要整体停止。
    func audioSessionRequestsStop()
}

/// 朗读用的音频会话。
final class ReaderSpeechAudioSession {

    weak var delegate: ReaderSpeechAudioSessionDelegate?

    /// 由接入方接管会话时置 true，本类的所有 `AVAudioSession` 调用都会跳过。
    ///
    /// 中断通知仍然照常监听并转发 —— 接管会话不等于接管中断响应，
    /// 朗读该不该暂停始终是引擎的判断。
    var isManagedExternally: Bool = false

    /// 通知观察者 token。
    ///
    /// block 版观察者**不归 `removeObserver(self)` 管**，必须按 token 摘 ——
    /// 漏摘不报错，观察者会一直留在通知中心里。
    private var notificationTokens: [NSObjectProtocol] = []

    // MARK: - 生命周期

    init() {
        observeSystemNotifications()
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - 激活与反激活

    /// 会话当前是否处于激活状态（本类自己的记账）。
    ///
    /// `AVAudioSession` 没有可查询的「是否已激活」，只能自己记。
    ///
    /// **用途**：让调用方能区分「需要重新激活」与「已经是活的」。
    /// 对处于暂停态的 `AVSpeechSynthesizer` 重新 `setCategory` 会让它丢掉当前 utterance
    /// 且**不投递任何回调** —— 引擎从此僵死，界面却还显示「播放中」。
    /// 所以恢复朗读时必须先问这一句，不能无条件重配会话。
    private(set) var isActive = false

    /// 配置并激活会话。朗读开始前调用。
    func activate() {

        guard !isManagedExternally else { return }

        performOnMain { [weak self] in

            guard let self else { return }

            do {
                let session = AVAudioSession.sharedInstance()

                try session.setCategory(.playback, mode: .spokenAudio, options: self.categoryOptions)

                try session.setActive(true)

                self.isActive = true

            } catch {

                // 会话配置失败不该让阅读本身崩掉或卡住：朗读会因为没有音频输出
                // 而听不见，但正文浏览必须继续可用。
                self.isActive = false

                // **必须打日志。** 后台激活被系统拒（典型是 `CannotInterruptOthers`）
                // 时这里是唯一的现场。此前这个 catch 是完全静默的，而症状
                //「界面显示在播、却一点声音都没有」离根因非常远。
                ReaderEnvironment.log("[Speech] 音频会话激活失败 code=\((error as NSError).code) \(error.localizedDescription)")
            }
        }
    }

    /// 反激活会话。朗读停止、读完全书、退出阅读器时调用。
    func deactivate() {

        guard !isManagedExternally else { return }

        performOnMain { [weak self] in

            // notifyOthersOnDeactivation：让被我们打断（或压低）的其它 App 知道可以恢复了。
            // 不带这个选项，用户的背景音乐会一直停着不恢复。
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

            self?.isActive = false
        }
    }

    /// 朗读期间是否把其它 App 的音频**压低**而不是打断。默认 false。
    ///
    /// ⚠️ 开启它会让锁屏 / 控制中心的「正在播放」卡片消失，详见 `categoryOptions`。
    var ducksOtherAudio: Bool = false
    
    /// category 选项。
    ///
    /// `.duckOthers` **必须默认关闭**：它让会话变成「与其它音频共存」，系统就不再把朗读
    /// 当作主播放源，锁屏 / 控制中心连播放卡片都不显示。保留为可配置
    /// （`ducksOtherAudio`）—— 锁屏控制是硬需求，压低共存只是偏好。
    ///
    /// `.allowAirPlay` 与 `.allowBluetoothA2DP` 则是**对齐参考实现**加回来的。
    /// 1.6.1 曾把它们删掉，理由是「`.playback` 上带任何 option 都可能让系统不把朗读
    /// 当主播放源」—— 那个理由站不住：参考项目 FM 带着这两个 option，锁屏状态完全正常。
    /// 删掉它们既没解决问题，也让我们与一个已知能正常工作的实现无谓地产生了差异。
    ///
    /// 后台播放不受这些选项影响（只依赖 `.playback` 与 `UIBackgroundModes: audio`），
    /// 所以出问题时的现象往往是「后台播放正常、锁屏却不对」，容易误判成锁屏功能没做。
    private var categoryOptions: AVAudioSession.CategoryOptions {

        var options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]

        if ducksOtherAudio { options.insert(.duckOthers) }

        return options
    }

    // MARK: - 系统通知

    /// ⚠️ **`queue` 必须传 nil，不要图省事传 `.main`。**
    ///
    /// 中断与路由变更由系统在自己选的线程上发，传 nil 是「在发帖线程同步投递」——
    /// 和原先 selector 版完全同一时机。传 `.main` 会变成异步派发，于是
    /// `handleInterruption` 里对 `AVAudioSession` 的处置会晚于系统真正中断我们的那一刻，
    /// 本类的记账与会话实际状态就对不上了。这条路径的状态机横跨 `AVPlayer`、
    /// 系统 TTS 与远程命令（见 CHANGELOG 1.32.1），时序错位很难从现象反推回来。
    private func observeSystemNotifications() {

        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: nil,
                               queue: nil) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        )

        notificationTokens.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification,
                               object: nil,
                               queue: nil) { [weak self] notification in
                self?.handleRouteAlter(notification)
            }
        )

        notificationTokens.append(
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                               object: nil,
                               queue: nil) { [weak self] _ in
                self?.handleMediaServicesReset()
            }
        )
    }

    /// 中断处理（来电、闹钟、其它 App 抢占音频）。
    private func handleInterruption(_ notification: Notification) {

        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {

        case .began:

            // 中断开始时系统已把会话置为非激活，记账要跟上，
            // 否则之后恢复朗读时会误判为「还活着」而不重新激活
            isActive = false

            // 打日志是为了把「朗读自己停了」的原因分开：中断、拔耳机、
            // 播放器非预期停住三条路都会走到 `pause(origin: .system)`，
            // 不记一笔的话日志里看不出是哪一条。
            ReaderEnvironment.log("[Speech] 音频中断开始（来电 / 其它 App 抢占 / 系统 TTS）")

            performOnMain { [weak self] in self?.delegate?.audioSessionRequestsPause() }

        case .ended:

            // 只有系统明示 shouldResume 才恢复。缺这个判断会在用户主动切走音频
            // （比如接完电话自己打开了音乐）之后把朗读硬塞回去。
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0

            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)

            ReaderEnvironment.log("[Speech] 音频中断结束 shouldResume=\(options.contains(.shouldResume))")

            guard options.contains(.shouldResume) else { return }

            performOnMain { [weak self] in

                guard let self else { return }

                // 中断期间系统会把会话置为非激活，恢复前必须重新激活
                self.activate()

                self.delegate?.audioSessionRequestsResume()
            }

        @unknown default:

            break
        }
    }

    /// 路由变化处理。
    private func handleRouteAlter(_ notification: Notification) {

        guard let info = notification.userInfo,
              let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }

        // 只处理「原输出设备不可用」，也就是拔耳机 / 蓝牙断开。
        // 其它 reason（新设备接入、路由配置变化等）不该打断朗读 ——
        // 一律暂停会导致插上耳机的瞬间也停掉。
        guard reason == .oldDeviceUnavailable else { return }

        ReaderEnvironment.log("[Speech] 输出设备不可用（拔耳机 / 蓝牙断开），暂停")

        performOnMain { [weak self] in self?.delegate?.audioSessionRequestsPause() }
    }

    /// 媒体服务重置。
    ///
    /// 这是系统级的音频栈重启，此前建立的会话与合成器状态都不再可信，
    /// 稳妥做法是整体停止而不是尝试续播。
    private func handleMediaServicesReset() {

        performOnMain { [weak self] in

            guard let self else { return }

            self.delegate?.audioSessionRequestsStop()

            // 会话配置随服务重置一起丢了，重新配一遍，供用户再次发起朗读
            self.activate()
        }
    }

    // MARK: - 线程

    /// 确保在主线程执行。
    ///
    /// 系统通知的投递线程不保证是主线程，而 `AVAudioSession` 的配置调用与
    /// 后续的 UI 状态更新都要求主线程，所以统一在这里收口。
    private func performOnMain(_ work: @escaping () -> Void) {

        if Thread.isMainThread {

            work()

        }else{

            DispatchQueue.main.async(execute: work)
        }
    }
}
