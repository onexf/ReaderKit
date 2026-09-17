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

    // MARK: - 生命周期

    init() {
        observeSystemNotifications()
    }

    deinit {
        // 通知中心的自动摘除只在 iOS 9+ 对 block-based 之外的观察者生效，
        // 这里显式摘一次，语义更明确
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 激活与反激活

    /// 配置并激活会话。朗读开始前调用。
    func activate() {

        guard !isManagedExternally else { return }

        performOnMain {

            do {
                let session = AVAudioSession.sharedInstance()

                try session.setCategory(.playback, mode: .spokenAudio, options: self.categoryOptions)

                try session.setActive(true)

            } catch {

                // 会话配置失败不该让阅读本身崩掉或卡住：朗读会因为没有音频输出
                // 而听不见，但正文浏览必须继续可用。
            }
        }
    }

    /// 反激活会话。朗读停止、读完全书、退出阅读器时调用。
    func deactivate() {

        guard !isManagedExternally else { return }

        performOnMain {

            // notifyOthersOnDeactivation：让被我们打断（或压低）的其它 App 知道可以恢复了。
            // 不带这个选项，用户的背景音乐会一直停着不恢复。
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// 朗读期间是否把其它 App 的音频**压低**而不是打断。默认 false。
    ///
    /// ⚠️ 开启它会让锁屏 / 控制中心的「正在播放」卡片消失，详见 `categoryOptions`。
    var ducksOtherAudio: Bool = false
    
    /// category 选项。
    ///
    /// **默认一个都不传，这是刻意的。** `AVSpeechSynthesizer` 配 `MPNowPlayingInfoCenter`
    /// 时，`.playback` 上带任何 option 都可能让系统不把朗读当作「主播放源」，
    /// 后果是锁屏 / 控制中心要么不显示播放信息、要么显示了但播放/暂停按钮的状态
    /// **不跟着 App 变**（点了暂停，App 内暂停了，锁屏按钮却还是暂停图标）。
    ///
    /// 曾经带过三个，逐个说明为什么去掉：
    /// - `.duckOthers`：让会话变成「与其它音频共存」，是上述问题最主要的来源。
    ///   保留为可配置（`ducksOtherAudio`），默认关 —— 锁屏控制是硬需求，压低共存是偏好。
    /// - `.allowBluetoothA2DP` / `.allowAirPlay`：对 `.playback` 而言本就是隐含行为，
    ///   传了是冗余，去掉不影响蓝牙耳机与 AirPlay 出声。
    ///
    /// 后台播放不受这些选项影响（只依赖 `.playback` 与 `UIBackgroundModes: audio`），
    /// 所以出问题时的现象往往是「后台播放正常、锁屏却不对」，容易误判成锁屏功能没做。
    private var categoryOptions: AVAudioSession.CategoryOptions {
        
        ducksOtherAudio ? [.duckOthers] : []
    }

    // MARK: - 系统通知

    private func observeSystemNotifications() {

        let center = NotificationCenter.default

        center.addObserver(self,
                           selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: nil)

        center.addObserver(self,
                           selector: #selector(handleRouteAlter(_:)),
                           name: AVAudioSession.routeChangeNotification,
                           object: nil)

        center.addObserver(self,
                           selector: #selector(handleMediaServicesReset),
                           name: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil)
    }

    /// 中断处理（来电、闹钟、其它 App 抢占音频）。
    @objc private func handleInterruption(_ notification: Notification) {

        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {

        case .began:

            performOnMain { [weak self] in self?.delegate?.audioSessionRequestsPause() }

        case .ended:

            // 只有系统明示 shouldResume 才恢复。缺这个判断会在用户主动切走音频
            // （比如接完电话自己打开了音乐）之后把朗读硬塞回去。
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0

            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)

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
    @objc private func handleRouteAlter(_ notification: Notification) {

        guard let info = notification.userInfo,
              let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }

        // 只处理「原输出设备不可用」，也就是拔耳机 / 蓝牙断开。
        // 其它 reason（新设备接入、路由配置变化等）不该打断朗读 ——
        // 一律暂停会导致插上耳机的瞬间也停掉。
        guard reason == .oldDeviceUnavailable else { return }

        performOnMain { [weak self] in self?.delegate?.audioSessionRequestsPause() }
    }

    /// 媒体服务重置。
    ///
    /// 这是系统级的音频栈重启，此前建立的会话与合成器状态都不再可信，
    /// 稳妥做法是整体停止而不是尝试续播。
    @objc private func handleMediaServicesReset() {

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
