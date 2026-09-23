//
//  ReaderSpeechPlayer.swift
//  ReaderKit — Speech
//
//  朗读音频的播放器。`AVPlayer` 的薄封装。
//
//  ---------------------------------------------------------------------------
//  **为什么朗读要绕道音频文件 + `AVPlayer`，而不是让 `AVSpeechSynthesizer` 直接出声：**
//
//  系统只在自己发起的远程命令得到响应时才刷新 Now Playing UI，单纯写
//  `MPNowPlayingInfoCenter.nowPlayingInfo` 驱动不了它。所以用 `AVSpeechSynthesizer`
//  直接出声时，从 App 内暂停 → 锁屏与控制中心的按钮状态不跟着变（从锁屏暂停则正常）。
//  `AVPlayer` 的状态变化系统能**直接观测**，不需要 app 通知。
//
//  这个结论是排除法确证的，不是推断：与一个已知正常的参考实现之间所有可枚举的
//  非架构差异都消除过（音频会话 mode 与 options、`nowPlayingInfo` 字段集、写入时机
//  与线程），问题依旧。十条已排除路径与完整过程见
//  `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。
//  **不要基于「少写了某个字段」之类的猜测退回直接出声的方案。**
//  ---------------------------------------------------------------------------
//
//  附带收益（现有实现里为绕开 `AVSpeechSynthesizer` 而生的复杂度可以整块删掉）：
//
//  - 播放与暂停在任意状态下都可调用，不存在「只能在 idle 提交」的约束，
//    因此不再需要「记下待办 → 停止 → 等取消回调 → 执行待办」那套机制
//  - 暂停时原地保留 `currentTime`，续播天然不回退，不必按字符数记录已读位置
//  - 快速连点退化为幂等调用，没有异步往返窗口
//

import AVFoundation
import Foundation

/// 播放器的结果回调。
protocol ReaderSpeechPlayerDelegate: AnyObject {

    /// 真正开始出声。
    ///
    /// 高亮与正文跟随应挂在这里，而不是 `play(url:)` 调用处 —— 从提交到出声之间
    /// 有就绪与缓冲的耗时，提前高亮会让画面比声音快一截。
    func speechPlayerDidStart(_ player: ReaderSpeechPlayer)

    /// 播完当前音频。
    func speechPlayerDidFinish(_ player: ReaderSpeechPlayer)

    /// 播放失败。
    func speechPlayerDidFail(_ player: ReaderSpeechPlayer, error: Error?)

    /// 当前音频的时长已可读取。
    ///
    /// `AVPlayerItem.duration` 要等播放项就绪才解析出来，而**就绪可能晚于开始出声** ——
    /// 实测 `didStart` 那一刻读到的还是 0，几十毫秒后才变成真实值。
    /// 需要精确时间轴的一方（锁屏信息）据此补写一次。
    func speechPlayerDidLoadDuration(_ player: ReaderSpeechPlayer)

    /// 播放器在**没人要求**的情况下停住了。
    ///
    /// 会话被别的 App 抢走、中断通知在进程挂起期间没送达、音频栈出状况都会走到这里。
    /// 不认下来的话编排层会永久停在「播放中」：声音早没了、界面和锁屏还各说各话。
    func speechPlayerDidStallUnexpectedly(_ player: ReaderSpeechPlayer)
}

extension ReaderSpeechPlayerDelegate {

    /// 时长就绪不是所有接入方都关心，给个空实现。
    func speechPlayerDidLoadDuration(_ player: ReaderSpeechPlayer) {}
}

/// 朗读音频播放器。
///
/// 线程约定：全部方法在**主线程**调用，状态同步改变，不依赖异步回调确认。
/// 这是「快速连点不错乱」的基础 —— 状态迁移没有中间态，就不存在竞态窗口。
final class ReaderSpeechPlayer {

    // MARK: - 状态

    enum State {

        /// 没有播放项。
        case idle

        /// 已提交音频，还没开始出声（就绪 / 缓冲中）。
        case preparing

        /// 正在出声。
        case playing

        /// 已暂停，位置保留。
        case paused
    }

    private(set) var state: State = .idle

    weak var delegate: ReaderSpeechPlayerDelegate?

    // MARK: - 内部持有

    /// 播放器实例。
    ///
    /// **复用同一个实例**（换音频走 `replaceCurrentItem(with:)`），不每次新建：
    /// `AVPlayer` 的创建有开销，而朗读是逐句换音频、切换非常频繁。
    /// 复用也让 Now Playing 的归属保持稳定 —— 反复新建播放器会让系统反复
    /// 重新认定当前播放源。
    private let player = AVPlayer()

    /// 当前播放项。用来辨认回调属于哪一次播放。
    private var currentItem: AVPlayerItem?

    /// `timeControlStatus` 观察令牌。
    private var timeControlObservation: NSKeyValueObservation?

    /// 当前播放项的 `status` 观察令牌。用来知道时长什么时候解析出来。
    private var itemStatusObservation: NSKeyValueObservation?

    /// 已解析出的时长（秒）。0 表示还没就绪。
    ///
    /// 缓存下来而不是每次读 `currentItem?.duration`：后者在就绪前返回 `indefinite`，
    /// 而调用方（写锁屏时间轴）拿到 0 与拿到旧值的处理方式不同，
    /// 让「什么时候有值」这件事只由 `status` 决定，比每次现读更好推理。
    private var loadedDuration: TimeInterval = 0

    /// 当前项的结束 / 失败通知观察者。
    private var itemObservers: [NSObjectProtocol] = []

    /// 判定「非预期停住」前的复核间隔。
    ///
    /// 取 1.5 秒是为了把所有正常的短暂停顿都让过去：命中缓存的句间间隙是几十毫秒，
    /// 未命中时 `state` 会先变成 `.idle` / `.preparing`（那条分支根本不看），
    /// 剩下唯一会持续超过这个时长的就是真的被停掉了。
    private static let stallConfirmDelay: TimeInterval = 1.5

    /// 是否已为本次播放报过 `didStart`。
    ///
    /// `timeControlStatus` 在一次播放里可能多次变成 `.playing`（如中断恢复后），
    /// 但「开始出声」对编排层只该发生一次 —— 它驱动高亮与翻页，重复触发会让
    /// 正文重新跟随一次。
    private var hasReportedStart = false

    // MARK: - 构造

    init() {

        // 朗读音频是本地文件，不需要缓冲策略上的让步；关掉自动等待可以让
        // 「提交 → 出声」的延迟尽可能小
        player.automaticallyWaitsToMinimizeStalling = false

        observeTimeControlStatus()
    }

    deinit {

        timeControlObservation?.invalidate()

        itemStatusObservation?.invalidate()

        removeItemObservers()
    }

    // MARK: - 播放控制

    /// 播放指定音频文件。会替换掉当前正在播的内容。
    func play(url: URL) {

        removeItemObservers()

        let item = AVPlayerItem(url: url)

        currentItem = item

        hasReportedStart = false

        loadedDuration = 0

        observeItem(item)

        observeItemStatus(item)

        player.replaceCurrentItem(with: item)

        state = .preparing

        player.play()

        ReaderEnvironment.log("[Speech] 播放器提交音频 \(url.lastPathComponent)")
    }

    /// 暂停。
    ///
    /// **不销毁播放器、不 seek、不重建播放项** —— 这三件事任何一件都会让续播回退。
    /// `AVPlayer` 自己保留 `currentTime`，继续就是接着播。
    func pause() {

        guard state == .playing || state == .preparing else { return }

        player.pause()

        state = .paused
    }

    /// 继续。
    func resume() {

        guard state == .paused else { return }

        player.play()

        // 已经出过声的音频恢复后不再重报 didStart（见 `hasReportedStart`），
        // 所以这里直接置 playing，不等 timeControlStatus。
        //
        // 1.32.0 曾改成一律 `.preparing`（想让 `.playing` 只来自实测），但那一版
        // 连着别的改动一起造成了「暂停后不能继续」，无法归因。先回到 1.31.0 的写法。
        state = hasReportedStart ? .playing : .preparing
    }

    /// 停止并丢弃当前播放项。
    func stop() {

        player.pause()

        player.replaceCurrentItem(with: nil)

        removeItemObservers()

        itemStatusObservation?.invalidate()

        itemStatusObservation = nil

        currentItem = nil

        hasReportedStart = false

        loadedDuration = 0

        state = .idle
    }

    // MARK: - 时间

    /// 当前播放位置（秒）。取不到时为 0。
    var currentTime: TimeInterval {

        let time = player.currentTime()

        guard time.isValid, !time.isIndefinite, !time.seconds.isNaN else { return 0 }

        return max(0, time.seconds)
    }

    /// 当前音频总时长（秒）。**尚未就绪时为 0**，就绪时机见 `speechPlayerDidLoadDuration`。
    ///
    /// 之所以能拿到真实值，是因为渲染时给裸 PCM 补了 WAV 容器头 ——
    /// 没有容器信息的话播放项永远解析不出时长。
    var duration: TimeInterval { loadedDuration }

    /// 播放位置是否已经到（或极接近）当前音频的末尾。
    ///
    /// 用来把「自然播完」与「非预期停住」区分开：两者都会让 `timeControlStatus`
    /// 变成 `.paused`。不按通知到达的先后判断 —— 结束通知与状态观察是两条独立的
    /// 异步路径，谁先到不确定；位置与时长的比较跟顺序无关。
    private var isAtItemEnd: Bool {

        guard loadedDuration > 0 else { return false }

        return currentTime >= loadedDuration - 0.3
    }

    // MARK: - 观察

    /// 观察「是否真的在出声」。
    ///
    /// 用 `timeControlStatus` 而不是「调了 `play()` 就算开始」：后者在音频尚未就绪时
    /// 会提前报，导致高亮比声音快一截。
    private func observeTimeControlStatus() {

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in

            // KVO 的投递线程不保证是主线程，而状态机与编排层都按主线程假设工作
            DispatchQueue.main.async { [weak self] in

                guard let self else { return }

                if player.timeControlStatus == .playing {

                    // `state` 每次都同步：它是「现在是不是真的在出声」的唯一事实来源，
                    // 下面那条分支的判据全靠它可信。
                    self.state = .playing

                    // 但 `didStart` 只报一次 —— 它驱动高亮与正文跟随，重复触发会让
                    // 正文重新跟随一次。
                    guard !self.hasReportedStart else { return }

                    self.hasReportedStart = true

                    self.delegate?.speechPlayerDidStart(self)

                    return
                }

                // 停住了，而且**不是我们要求的** —— 自己调 `pause()` / `stop()` 时
                // `state` 会先被改掉，所以这里还看到 `.playing` 就意味着
                // 会话被别的 App 抢走、或中断通知在进程挂起期间没送达。
                //
                // 这条分支是 1.32.0 补的：此前只认 `.playing`，任何系统侧发起的停止
                // 都无人接管，编排层永久停在播放中（声音没了、界面还显示在播）。
                guard player.timeControlStatus == .paused,
                      self.state == .playing,
                      !self.isAtItemEnd else { return }

                ReaderEnvironment.log("[Speech] 播放器读到停住（位置 \(Int(self.currentTime))/\(Int(self.loadedDuration))s），\(Self.stallConfirmDelay)s 后复核")

                // **不要立刻下结论。**
                //
                // 启动、换曲、渲染下一句时抢会话、被短暂中断又恢复，这些时刻都会读到
                // 「停着」，立刻按暂停收敛就会把正常的播放掐掉 —— 1.32.0 的
                // 「暂停后不能继续」「读着读着自动暂停」都是这么来的。
                //
                // 真的被抢走会一直停着，多等一秒多没有代价；而正常的句间间隙
                // （命中缓存时几十毫秒）远远短于它。
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.stallConfirmDelay) { [weak self] in

                    guard let self,
                          self.state == .playing,
                          self.player.timeControlStatus == .paused,
                          !self.isAtItemEnd else { return }

                    // **不改 `state`、不动播放**：现在这条分支是纯观察。
                    // 改 `state` 会影响 `pause()` / `resume()` 的分支选择，属于行为改动，
                    // 而这一整块的判据还没被现场日志验证过。
                    self.delegate?.speechPlayerDidStallUnexpectedly(self)
                }
            }
        }
    }

    /// 观察播放项就绪，就绪后时长才可读。
    private func observeItemStatus(_ item: AVPlayerItem) {

        itemStatusObservation?.invalidate()

        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in

            DispatchQueue.main.async { [weak self] in

                guard let self, self.currentItem === item else { return }

                guard item.status == .readyToPlay else { return }

                let duration = item.duration

                guard duration.isValid, !duration.isIndefinite, !duration.seconds.isNaN,
                      duration.seconds > 0 else { return }

                // 同一个播放项只报一次
                guard self.loadedDuration == 0 else { return }

                self.loadedDuration = duration.seconds

                self.delegate?.speechPlayerDidLoadDuration(self)
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {

        let center = NotificationCenter.default

        let finished = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                          object: item,
                                          queue: .main) { [weak self] _ in

            guard let self, self.currentItem === item else { return }

            self.state = .idle

            self.delegate?.speechPlayerDidFinish(self)
        }

        // 失败也要接：只接结束通知的话，音频损坏（比如上次写盘被中断留下的截断文件）
        // 会表现为「朗读卡在某一句不动」，且没有任何报错
        let failed = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                        object: item,
                                        queue: .main) { [weak self] notification in

            guard let self, self.currentItem === item else { return }

            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error

            self.state = .idle

            ReaderEnvironment.log("[Speech] 播放失败：\(error?.localizedDescription ?? "未知原因")")

            self.delegate?.speechPlayerDidFail(self, error: error)
        }

        itemObservers = [finished, failed]
    }

    private func removeItemObservers() {

        for observer in itemObservers {

            NotificationCenter.default.removeObserver(observer)
        }

        itemObservers.removeAll()
    }
}
