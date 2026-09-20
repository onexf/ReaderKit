//
//  ReaderSpeechController.swift
//  ReaderKit — Speech
//
//  朗读编排层：把「章节文本」「分页」「合成引擎」「音频会话」串成一条可控的朗读流程。
//
//  职责边界：
//  - 引擎（`ReaderSpeechSynthesizing`）只管把一句话读出来，不知道章节与页的存在
//  - 本类知道章节、句、页，负责决定「下一句是哪句」「要不要翻页」「章末怎么接」
//  - 具体怎么翻页、怎么画高亮由本类调用视图层，视图层不反向依赖本类
//
//  两个贯穿全局的坐标约定（弄错会表现为高亮错位与翻页跳错）：
//  - 句范围、页范围、`page(location:)` 统一以 `ReaderChapterModel.fullContent`
//    （章节标题 + 正文）为基准，称「章内绝对坐标」
//  - 分句输入必须是 `fullContent.string`；语言判定输入必须是 `content`（不含标题）
//

import Foundation
import UIKit

/// 朗读编排器。
public final class ReaderSpeechController {

    // MARK: - 依赖

    /// 音频渲染器：把句子合成为音频文件，**不出声**。
    ///
    /// 默认是设备端实现，二期可换成云端实现而不改本类。
    private let renderer: ReaderSpeechAudioRendering

    /// 音频播放器。出声的唯一途径。
    ///
    /// 之所以不让 `AVSpeechSynthesizer` 直接出声：系统只在自己发起的远程命令得到响应时
    /// 才刷新 Now Playing UI，写 `nowPlayingInfo` 驱动不了它，于是从 App 内暂停时
    /// 锁屏状态不跟着变。`AVPlayer` 的状态变化系统能直接观测。
    /// 详见 `ReaderSpeechPlayer` 的文件头与
    /// `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。
    private let player = ReaderSpeechPlayer()

    /// 合成音频的磁盘缓存。命中时可以立即出声，省掉合成等待。
    private let audioCache = ReaderSpeechAudioCache()

    /// 单次渲染的超时上限。
    ///
    /// 超时是必需的兜底：系统异常时 `AVSpeechSynthesizer.write` 可能永不回调。
    /// 取 10 秒是折中 —— 实测一段 60 词英文约 1.4 秒，长句与慢设备会更久，
    /// 定太短会频繁误判成失败。
    private static let renderTimeout: TimeInterval = 10

    /// 音频会话与系统中断。
    private let audioSession: ReaderSpeechAudioSession

    /// 锁屏播放信息与远程控制。
    private let nowPlaying: ReaderSpeechNowPlaying

    /// 宿主协调扩展点。未注入时全部走默认行为。
    public weak var coordinator: ReaderSpeechCoordinating? {

        didSet {

            audioSession.isManagedExternally = coordinator?.managesAudioSessionExternally ?? false

            audioSession.ducksOtherAudio = coordinator?.speechDucksOtherAudio ?? false

            nowPlaying.isManagedExternally = coordinator?.managesNowPlayingExternally ?? false
        }
    }

    /// 所属阅读器。
    ///
    /// weak：阅读器持有本类，反向必须弱引用。
    private weak var reader: ReaderViewController?

    // MARK: - 对外状态

    /// 当前朗读活动状态。
    public private(set) var activity: ReaderSpeechActivity = .idle {

        didSet {

            guard activity != oldValue else { return }

            ReaderEnvironment.log("[Speech] activity \(oldValue) → \(activity)")

            notifyActivityAlter()
        }
    }

    /// 当前正在朗读的句。未朗读时为 nil。
    private var currentSentence: ReaderSentence? {

        guard let currentIndex, sentences.indices.contains(currentIndex) else { return nil }

        return sentences[currentIndex]
    }

    /// 当前正在朗读的句在章内绝对坐标中的范围。未朗读时为 nil。
    ///
    /// 供界面判断「朗读位置是否在当前展示页」，三态控制按钮据此决定显示
    /// 「从这里开始读」还是「暂停 / 继续」。
    public var speakingRange: NSRange? { currentSentence?.range }

    /// 当前朗读所属的章节 ID。跨章判断用。
    public private(set) var speakingChapterID: NSNumber?

    /// 朗读中章节的全文纯文本（标题 + 正文）。未在朗读时为 nil。
    ///
    /// 只给纯文本而不是富文本：取用方（朗读播放器页）要用**自己的固定字号**重新排版，
    /// 拿到带阅读器属性的富文本反而要先剥属性。章节名另有 `speakingChapterTitle`。
    public var speakingChapterText: String? { speakingChapter?.fullContent?.string }

    /// 朗读中章节的章节名。未在朗读时为 nil。
    public var speakingChapterTitle: String? { speakingChapter?.name }

    /// 当前章节的朗读进度，取值 0...1。
    ///
    /// 口径是「已读字符数 / 本章全文长度」—— 当前句**句首**在本章全文（标题 + 正文）里的
    /// 偏移除以全文长度。刻意不用时间比例：时长是按字符数估算的（见 `makeContext()`），
    /// 拿估算值去算进度等于绕一圈还是字符比例，中间还多一层误差。
    ///
    /// 因此这个值**按句跳变**而非连续增长。用它画进度环时不必追求逐帧平滑，
    /// 语义上「读到第几个字」本身就是离散的。
    public var chapterProgress: Double {

        guard let total = speakingChapter?.fullContent?.length, total > 0,
              let sentence = currentSentence else { return 0 }

        let spoken = min(total, max(0, sentence.range.location))

        return Double(spoken) / Double(total)
    }

    /// 朗读控制胶囊该显示成哪一态。
    ///
    /// 把「活动状态」与「朗读位置是否在当前展示页」两件事收敛成一个枚举，
    /// 界面直接照它渲染即可，不必自己判断位置关系。
    public var actionState: ReaderSpeechActionState {

        switch activity {

        case .idle:

            return .idle

        // 准备中按「播放中」呈现：用户点了播放，意图已经生效，显示成播放中不算假状态，
        // 而且不需要额外的加载态图标。需要区分出加载动画的接入方可以自己读 `activity`。
        case .preparing, .playing:

            return isSpeakingOnDisplayedPage ? .playing : .offPage

        case .paused:

            return isSpeakingOnDisplayedPage ? .paused : .offPage
        }
    }

    /// 朗读位置是否落在用户当前**看得见**的范围里。
    ///
    /// 决定胶囊显示「暂停 / 继续」还是「从这里开始读」，所以口径必须是「看得见」，
    /// 而不是「在当前页」—— 后者在滚动模式下会得出「在当前页却看不见」的结论，
    /// 表现为胶囊显示暂停、正文里却找不到高亮。
    private var isSpeakingOnDisplayedPage: Bool {

        // 滚动模式：一页不等于一屏，可视区通常横跨两页，且「当前页」的大半内容
        // 可能在可视区上方。必须问滚动容器要句子的实际可见性。
        if ReaderConfiguration.shared().effectType == .scroll {

            guard let scrollController = reader?.scrollController else { return false }

            return scrollController.isSpeechSentenceVisible
        }

        // 左右翻页：一页恰好一屏，「在当前页」等价于「看得见」
        return isSpeakingSentenceOnDisplayedPage
    }

    /// 左右翻页模式下，当前朗读句是否落在当前展示页上。
    ///
    /// 用 `highlightRange(inPage:chapterID:)` 而不是比较「句首所在页 == 当前页」：
    /// 句子可能跨页，句首在上一页、句尾在本页时它同样是可见的。按句首页码比较会把这种
    /// 情况判成不可见，界面上表现为读到跨页句就切「从这里开始读」、并且触发多余的翻页。
    ///
    /// `highlightRange` 内部已经校验了「非空闲」与「同一章」，这里不必重复。
    private var isSpeakingSentenceOnDisplayedPage: Bool {

        guard let record = reader?.readModel?.recordModel,
              let displayedChapter = record.chapterModel,
              let pageModel = record.pageModel else { return false }

        return highlightRange(inPage: pageModel, chapterID: displayedChapter.id) != nil
    }

    /// 把正文跳回朗读位置。控制胶囊上的返回箭头调这个。
    ///
    /// 与 `alignPage(to:)` 的区别：那个只在自然顺序推进时跟随、且只前进一页；
    /// 本方法是用户主动要求对齐，任意距离、任意方向都跳。
    public func returnToSpeakingPosition() {

        alignViewToSpeakingSentence()
    }

    /// 当前朗读所属的章节模型。
    ///
    /// 必须单独持有，不能用 `readModel.recordModel.chapterModel` 代替 —— 后者是
    /// **正在展示**的章节。朗读跨章后正文视图并不跟着走（见 `alignPage(to:)` 的说明），
    /// 此时两者指向不同章节：用展示章节去算句所在页、或去填锁屏的章节名，都会错。
    private var speakingChapter: ReaderChapterModel?

    // MARK: - 内部状态

    /// 当前章节切好的句。
    private var sentences: [ReaderSentence] = []

    /// 预合成深度：当前句出声后，再往后预渲染几句。
    ///
    /// 取 2 而不是 1：一句通常播几秒、一次渲染 0.2~1 秒，理论上 1 句的余量就够，
    /// 但短句（「他笑了。」）播完只要一秒多，余量太薄容易被追上。2 句的代价只是缓存里
    /// 多一个文件（百来 KB），而缓存本来就有 LRU 上限兜着。
    private static let prefetchDepth = 2

    /// 已提交过预合成的句下标。
    ///
    /// 只用来防重复提交 —— 光看缓存判断不了「正在渲染但还没落盘」那段窗口，
    /// 会导致同一句被反复提交。换章时随 `sentences` 一起清空。
    private var prefetchedIndices: Set<Int> = []

    /// 已为哪一句重试过渲染。每句只重试一次。
    private var renderRetriedIndex: Int?

    /// 当前句下标。
    private var currentIndex: Int?

    /// 当前章节的内容语言（BCP-47）。
    private var language: String?

    /// 当前使用的音色标识。
    private var voiceIdentifier: String?

    /// 会话标识。
    ///
    /// 用途是丢弃过期的**异步**回调 —— 章节正文加载是异步的（`ReaderChapterLoading`），
    /// 用户完全可能在加载途中停止朗读或换到别的位置。加载完成时若标识已变，
    /// 说明这次结果属于上一次会话，必须丢掉，否则会把用户已经放弃的朗读又启动起来。
    private var sessionID = UUID()

    /// 当前交给播放器的片段。
    ///
    /// 播放器的回调不带片段（它只认音频文件），需要在这里记住「现在播的是哪一句」。
    private var currentFragment: ReaderSpeechFragment?

    // MARK: - 构造

    /// - Parameters:
    ///   - reader: 所属阅读器
    ///   - synthesizer: 合成引擎，默认设备端实现
    public init(reader: ReaderViewController,
                renderer: ReaderSpeechAudioRendering = ReaderSpeechAudioRenderer()) {

        self.reader = reader

        self.renderer = renderer

        self.audioSession = ReaderSpeechAudioSession()

        self.nowPlaying = ReaderSpeechNowPlaying()

        self.player.delegate = self

        self.audioSession.delegate = self

        self.nowPlaying.delegate = self

        observeAppLifecycle()
    }

    deinit {

        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 前后台

    /// 监听前后台切换。
    ///
    /// **刻意不监听「进入后台就暂停」** —— 本期做后台播放，锁屏后要继续读。
    /// 这里只处理回前台时把正文对齐到朗读位置。
    private func observeAppLifecycle() {

        // **用 didBecomeActive 而不是 willEnterForeground。**
        //
        // 后者的时机太早：那一刻 app 只是「即将」回到前台，窗口尚未完成布局，
        // 容器尺寸不可信。在那时跳页会重建整条章节数据链，`UIPageViewController`
        // 会停在两页之间 —— 真机上表现为正文整体横向偏移半屏、被截断，
        // 页码与时间电量挤在一起。用户手动翻一页触发一次正常布局后就恢复正常，
        // 这也说明分页数据本身是对的，坏的只是那一次的容器状态。
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handleDidBecomeActive),
                                              name: UIApplication.didBecomeActiveNotification,
                                              object: nil)
    }

    /// 回到前台并激活：把正文对齐到当前朗读位置。
    ///
    /// 后台听书期间正文视图不跟着走（没必要，也做不了动画），所以回来时可能已经
    /// 隔了好几页甚至好几章。不对齐的话用户看到的是自己离开时那一页，
    /// 与耳朵里听到的内容对不上。
    @objc private func handleDidBecomeActive() {

        guard activity != .idle else { return }

        // 退两拍再对齐。
        //
        // **从锁屏回来与从控制中心回来不是一回事**：后者 app 只是 `.inactive`、
        // 从未进 background，窗口布局始终有效，对齐没问题；前者 app 真的进过
        // background，窗口与容器视图带着一堆待处理的布局回来，此时跳页
        // （要重建整条章节数据链）会让 `UIPageViewController` 停在两页之间 ——
        // 表现为两页内容同屏、各自向反方向偏出，且此后每次跟随翻页都在这个坏状态上叠加。
        //
        // 一拍不够（上一版试过），所以退两拍，并在真正跳页前强制把布局跑完。
        DispatchQueue.main.async { [weak self] in

            DispatchQueue.main.async { [weak self] in

                guard let self, self.activity != .idle else { return }

                self.alignAfterLayoutSettled()
            }
        }
    }

    /// 强制完成布局后再对齐，并把关键尺寸打进日志。
    ///
    /// 尺寸取证是刻意的：分页（`ReaderTypesetter.pageing`）与正文渲染
    /// （`ReaderPageView` 的排版尺寸）都依赖 `READER_VIEW_RECT`，而它由安全区推导。
    /// 若解锁瞬间安全区取到过渡值，分页与排版会一起错且缓存被污染、此后不自愈。
    /// 这条日志能区分「排版尺寸错」与「容器位置偏移」两种猜测，不必再靠现象推断。
    private func alignAfterLayoutSettled() {

        guard let reader else { return }

        // 主动跑完待处理的布局，而不是等它自己发生 —— 等的时机无从判断，
        // 强制完成是确定的。
        reader.view.layoutIfNeeded()

        ReaderEnvironment.log("[Speech] 回前台对齐 bounds=\(reader.view.bounds.size) viewRect=\(READER_VIEW_RECT?.size ?? .zero) safeTop=\(ReaderScreenMetrics.safeAreaTop) safeBottom=\(ReaderScreenMetrics.safeAreaBottom)")

        alignViewToSpeakingSentence()
    }

    /// 把正文对齐到当前朗读句。
    ///
    /// 两个调用方：胶囊上的返回箭头（用户主动要求）、以及回到前台时的补齐。
    /// 与 `alignPage(to:)` 的区别是那个只在朗读自然推进时跟随、且左右翻页下只前进一页；
    /// 本方法是「无论隔多远都对齐过去」。
    private func alignViewToSpeakingSentence() {

        guard let reader,
              let speakingChapter,
              let chapterID = speakingChapter.id,
              let sentence = currentSentence else { return }

        if ReaderConfiguration.shared().effectType == .scroll,
           let scrollController = reader.scrollController,
           scrollController.containsSpeechChapter(chapterID) {

            // 优先按句滚而不是走 `presentPosition`（接入方注入的**按页**跳转）：
            // 滚动模式下滚到页首之后句子仍可能在可视区之外，等于没回来。
            // 容器内部会判断「已在可视区内就不动」，这里不必预判。
            requestPositionAlter {

                scrollController.revealSpeechSentence(animated: true)
            }

        }else if isSpeakingSentenceOnDisplayedPage {

            // 已经对齐就不要跳：跳转会重建正文视图，无谓的重建既闪屏也丢滚动位置

        }else{

            requestPositionAlter {

                reader.presentPosition(chapterID: chapterID, location: sentence.range.location)
            }
        }

        // 用户主动要求对齐，挂起随之解除
        isFollowSuspended = false

        // 跳转后视图可能是新建的，高亮要重新写一遍
        reviseSpeechPresentation(for: sentence)
    }



    // MARK: - 对外控制

    /// 从用户当前**看得见**的位置开始朗读。
    ///
    /// 起点最终会落到所属句的**句首**（见 `beginSpeaking(fromLocation:)`）：
    /// 起点通常落在句子中间，从中间读起听感是漏了前半句。
    ///
    /// 两种阅读模式取起点的方式不同，这个差异是必须的：
    ///
    /// - **左右翻页**：一页恰好一屏，页首就是屏幕第一行，取 `record.locationFirst` 即可。
    /// - **上下滚动**：一页不等于一屏。页码口径是「顶端像素所属的页」，屏幕上通常同时
    ///   显示上一页的尾与下一页的头，所以「当前页」的页首多半已滚到可视区上方。
    ///   此时取页首会从屏幕外的内容读起 —— 必须问滚动容器要真正可见的第一行。
    public func startFromCurrentPage() {

        // 起点取自用户眼前的内容，之前的挂起随之解除
        isFollowSuspended = false

        // 滚动模式：按可见首行定位，拿不到（书籍首页、布局未就绪）时退回按页
        if ReaderConfiguration.shared().effectType == .scroll,
           let scrollController = reader?.scrollController,
           let position = scrollController.visibleStartPosition() {

            guard prepare(chapter: position.chapter) else { return }

            start(fromLocation: position.location)

            return
        }

        guard let record = reader?.readModel?.recordModel,
              let chapter = record.chapterModel else { return }

        guard prepare(chapter: chapter) else { return }

        start(fromLocation: record.locationFirst.intValue)
    }

    /// 从指定章内绝对坐标开始朗读。
    ///
    /// 可以在任何状态下调用。`AVPlayer` 允许随时替换正在播放的内容，
    /// 不像 `AVSpeechSynthesizer` 那样「只在空闲时接受提交」——
    /// 所以这里不再需要「记下待办 → 停止 → 等取消回调 → 执行待办」那一套。
    public func start(fromLocation location: NSInteger) {

        beginSpeaking(fromLocation: location)
    }

    /// 暂停。
    ///
    /// 就是 `AVPlayer.pause()` —— 同步、幂等、不销毁播放器、不 seek。
    /// 因此可以放心快速连点，不存在异步往返窗口。
    ///
    /// 曾经这里有一整套复杂机制（记录已读字符数、未决意图、防迟到回调的标记），
    /// 那些都是为了绕开 `AVSpeechSynthesizer` 的限制 ——「只在空闲时接受提交」
    /// 与「暂停/继续这对 API 可能永不回调」。换成播放器之后限制消失，机制随之删除。
    /// 详见 `.kiro/learnings/quality/2026-09-16_unreliable-api-behind-async-roundtrip.md`。
    public func pause() {

        ReaderEnvironment.log("[Speech] pause() 进入 activity=\(activity) player=\(player.state)")

        guard activity == .playing || activity == .preparing else { return }

        // 先结算再写锁屏，顺序不能反 —— 下面的 `publishNowPlaying()` 要用结算后的值
        settleSpeakingSegment()

        // 还在准备阶段（音频没渲染完）就被暂停：撤掉在途的渲染任务。
        // 已经开始的那一个无法真正中断，但它的结果会被丢弃 ——
        // 不撤的话渲染回来会自己播起来，用户点的这次暂停就丢了。
        if activity == .preparing { renderer.cancelAll() }

        player.pause()

        activity = .paused

        publishNowPlaying()
    }

    /// 结算当前这一段出声时长。停止出声的每条路径都要调。
    private func settleSpeakingSegment() {

        guard let start = speakingSegmentStart else { return }

        accumulatedSpeakingTime += Date().timeIntervalSince(start)

        speakingSegmentStart = nil
    }

    /// 从暂停位置继续。
    public func resume() {

        ReaderEnvironment.log("[Speech] resume() 进入 activity=\(activity) player=\(player.state) sessionActive=\(audioSession.isActive)")

        guard activity == .paused else { return }

        if !audioSession.isActive { audioSession.activate() }

        // 播放器手里还有内容（暂停在播放中途）：直接继续。
        //
        // **位置由 `AVPlayer` 自己保留** —— 暂停既不销毁播放器也不 seek，所以续播
        // 天然接在原处。此前用 `AVSpeechSynthesizer` 时做不到这一点，只能记录已读字符数、
        // 恢复时重新提交剩余文本，那套机制（连同它引入的时序问题）已随之删除。
        if player.state == .paused {

            player.resume()

            activity = .playing

            publishNowPlaying()

            return
        }

        // 播放器是空的：暂停发生在音频还没渲染完的阶段，需要重新走一遍提交。
        // 音频通常已经落盘（渲染完成后无论是否还要播都会入缓存），所以这次会命中缓存、
        // 立即出声。
        guard let sentence = currentSentence else { return }

        start(fromLocation: sentence.range.location)
    }

    /// 本章已累计的**实际出声时长**（秒），不含当前正在出声的这一段。
    ///
    /// 锁屏时间轴必须**连续**，这是它存在的唯一理由。
    ///
    /// 曾经用「当前句句首的字符位置折算秒数」当已播时间，那个值在**整句朗读期间完全不变**。
    /// 系统拿到 `MPNowPlayingInfoPropertyElapsedPlaybackTime` 会把它当锚点、配合 `rate`
    /// 自己往前推，而我们每次刷新又写回那个不动的值 —— 时间轴反复被拽回原处。
    /// 系统看到「声称在播放、时间却不走」的自相矛盾信息，就不再采信我们声明的 `rate`，
    /// 改用自己的判断，于是暂停后按钮仍显示播放中。
    ///
    /// （这就是 1.7.1 的回归：那一版补时间轴修好了控制中心，却把原本正常的锁屏页弄坏了，
    ///   当时误判成「修好了一处」。）
    private var accumulatedSpeakingTime: TimeInterval = 0

    /// 当前这一段出声的起始时刻。未在出声时为 nil。
    ///
    /// 暂停 / 停止时结算进 `accumulatedSpeakingTime`。
    private var speakingSegmentStart: Date?

    /// 此刻是否还有上一章可跳。
    ///
    /// 与锁屏「上一曲」按钮的可用性、播放器页上一章按钮的置灰读**同一个**判断，
    /// 保证「按钮可用」与「点了真的会跳」不发散。
    public var hasPreviousChapterForSkip: Bool { precedingChapterIDForSkip != nil }

    /// 此刻是否还有下一章可跳。口径同上。
    public var hasNextChapterForSkip: Bool { followingChapterIDForSkip != nil }

    /// 下一章的跳转目标。为 nil 表示此刻跳不过去。
    ///
    /// nil 有两种成因，对「能不能跳」而言等价，所以刻意不区分：
    /// 全书真末章，或下一章尚未加载进目录。后者会随目录补齐自行恢复，
    /// 而锁屏按钮的可用性每句都会重算一次，所以不需要为它单独处理。
    ///
    /// 抽成属性是为了让 `skipToNextChapter()` 与锁屏「下一曲」按钮的可用性读**同一个**
    /// 判断 —— 两处各写一遍迟早发散成「按钮是亮的但点了没反应」或反之。
    private var followingChapterIDForSkip: NSNumber? {

        guard let book = reader?.readModel else { return nil }

        return book.resolvedFollowingChapterID(forChapterID: speakingChapterID)
    }

    /// 上一章的跳转目标。为 nil 表示已是首章。口径同上。
    private var precedingChapterIDForSkip: NSNumber? {

        guard let book = reader?.readModel else { return nil }

        return precedingChapterID(of: speakingChapterID, in: book)
    }

    /// 切到下一章并从头朗读。锁屏「下一曲」与界面跳章都走这里。
    ///
    /// 已是末章时静默忽略 —— 锁屏按钮点了没反应比读出错误内容好。
    /// （该按钮现已按 `hasNextChapter` 置灰，正常情况下点不到这里。）
    public func skipToNextChapter() {

        guard let target = followingChapterIDForSkip else { return }

        requestChapterSwitch(to: target)
    }

    /// 切到上一章并从头朗读。已是首章时静默忽略。
    public func skipToPreviousChapter() {

        guard let target = precedingChapterIDForSkip else { return }

        requestChapterSwitch(to: target)
    }

    /// 停止朗读并释放音频会话。
    ///
    /// 同步完成，不需要等任何回调 —— 这也是换掉合成器之后消掉的一处复杂度：
    /// 此前停止要经过「发出停止 → 等取消回调 → 收尾」，而取消回调在某些路径上
    /// 可能不投递，得额外判断引擎状态兜底。
    public func stop() {

        guard activity != .idle else { return }

        renderer.cancelAll()

        player.stop()

        finishStop()
    }

    // MARK: - 章节准备

    /// 为指定章节准备分句、语言与音色。已准备过同一章则复用。
    ///
    /// - Returns: 准备失败（缺正文、无可用音色）时返回 false，并已向用户提示。
    private func prepare(chapter: ReaderChapterModel) -> Bool {

        if let speakingChapterID, speakingChapterID == chapter.id, !sentences.isEmpty { return true }

        // 换章了，出声计时归零。锁屏时间轴的总时长按**本章**字符数外推，
        // 计时不归零会让已播时间越章累加、很快超过总时长。
        settleSpeakingSegment()

        accumulatedSpeakingTime = 0

        // **先校验正文。** `fullContent` 是「标题 + 正文」，正文为空时它仍然非空
        // （只剩标题），只看它会把「有归档但没正文」的空壳章节当成可读 ——
        // 分句只得到标题一句，读完立刻跨章，连锁下去就是雪崩式跨章
        // （详见 `proceed(toChapterID:in:)` 里的说明）。
        guard Self.hasReadableBody(chapter) else {

            ReaderEnvironment.log("[Speech] 章节 \(chapter.id ?? 0) 无正文，不可朗读")

            presentNotice(ReaderEnvironment.strings.speechFailed)

            return false
        }

        // fullContent 由 reviseFont() 生成，同时也是 pageModels 的排版来源。
        // 它为空说明这一章还没排版，此时分页范围也不存在，无法建立坐标映射。
        guard let fullText = chapter.fullContent?.string, !fullText.isEmpty else {

            presentNotice(ReaderEnvironment.strings.speechFailed)

            return false
        }

        // 语言只从正文判定：标题短、且常含「第 12 章」这类数字编号，会把识别带偏
        let detected = ReaderSentenceTokenizer.detectLanguage(inBody: chapter.content ?? "")

        // 分句必须基于 fullContent：用 content 会让所有句坐标整体偏移一个标题长度
        let parsed = ReaderSentenceTokenizer.sentences(inFullText: fullText, language: detected)

        guard !parsed.isEmpty else {

            presentNotice(ReaderEnvironment.strings.speechFailed)

            return false
        }

        guard let voice = ReaderSpeechVoiceCatalog.defaultVoice(forLanguage: detected) else {

            presentNotice(ReaderEnvironment.strings.speechVoiceUnavailable)

            return false
        }

        sentences = parsed

        // 下标的含义随 `sentences` 整体失效，两份按下标记事的状态必须一起清
        prefetchedIndices.removeAll()

        renderRetriedIndex = nil

        language = detected

        voiceIdentifier = voice.identifier

        speakingChapterID = chapter.id

        speakingChapter = chapter

        return true
    }

    // MARK: - 朗读推进

    /// 真正开始朗读。调用前须确保引擎处于 idle。
    private func beginSpeaking(fromLocation location: NSInteger) {

        guard let index = ReaderSentenceTokenizer.sentenceIndex(forLocation: location, in: sentences) else {

            // 坐标越过最后一句：正常发生在从章末位置起播，按本章已读完处理
            concludeChapter()

            return
        }

        // 宿主否决（典型场景：激励视频广告正在占用音频）
        guard coordinator?.speechShouldBegin() ?? true else { return }

        sessionID = UUID()

        // 撤掉在途的预合成。渲染是**串行**的，不撤的话这一句要排在最多两个
        // 预合成任务之后，起播白等一两秒 —— 而用户刚点的这一句才是最急的。
        // 已落盘的预合成音频不受影响（`cancelAll` 只作废在途结果）。
        renderer.cancelAll()

        renderRetriedIndex = nil

        currentIndex = index

        // 音频会话与锁屏**不在这里激活**，挪到真正要出声的时刻（`playFragment`）。
        //
        // 未命中缓存时这里到出声之间隔着一到两秒的渲染，提前激活会让用户
        // 「点了播放，背景音乐立刻停，却要等两秒才听到朗读」。
        submitCurrentSentence()
    }

    /// 把当前句变成声音：命中缓存直接播，否则先渲染再播。
    private func submitCurrentSentence() {

        guard let index = currentIndex, sentences.indices.contains(index) else { return }

        let sentence = sentences[index]

        // 翻页放在出声之前：翻页有动画耗时，等出声了再翻会出现「声音已经在读下一页、
        // 画面还停在上一页」。高亮则相反，挂在播放开始（见 `speechPlayerDidStart`）。
        alignPage(to: sentence)

        let fragment = ReaderSpeechFragment(text: sentence.text,
                                            range: sentence.range,
                                            voiceIdentifier: voiceIdentifier,
                                            language: language)

        // 命中缓存：无需等待，直接出声。第二次听同一段就走这条路。
        if let cached = audioCache.url(for: fragment) {

            playFragment(fragment, url: cached)

            return
        }

        // 未命中：进入「准备中」并开始渲染。
        //
        // 状态必须立刻置位 —— 渲染要一到两秒，这期间界面没有反馈的话用户会以为
        // 没点上、反复点击。
        activity = .preparing

        let session = sessionID

        let started = Date()

        renderer.render(fragment, timeout: Self.renderTimeout) { [weak self] result in

            guard let self else { return }

            // 会话已作废（用户停止了朗读、或换了章）：结果丢弃。
            // `sessionID` 是既有机制，本来就用于让在途的异步结果失效。
            guard self.sessionID == session else { return }

            switch result {

            case .success(let data):

                ReaderEnvironment.log("[Speech] 渲染完成 \(data.count / 1024)KB 耗时 \(String(format: "%.1f", Date().timeIntervalSince(started)))s")

                // 无论接下来是否要播，音频都先入缓存 —— 用户在渲染期间暂停了的话，
                // 这份音频等他继续时正好命中，不必重新渲染
                let stored = self.audioCache.store(data, for: fragment)

                // 渲染期间用户暂停或停止了：不要自己播起来。
                // 暂停的话音频已落盘，`resume()` 会命中缓存。
                guard self.activity == .preparing else { return }

                guard let url = stored else {

                    // 落盘失败（磁盘满等）。音频数据还在手里但播放器只收 URL，
                    // 这一句只能放弃 —— 阶段三接降级后会改为直接出声。
                    self.handleRenderFailure(.renderFailed)

                    return
                }

                self.playFragment(fragment, url: url)

            case .failure(let error):

                ReaderEnvironment.log("[Speech] 渲染失败 \(error) 耗时 \(String(format: "%.1f", Date().timeIntervalSince(started)))s")

                guard self.activity == .preparing else { return }

                // 瞬时性失败重试一次再放弃。系统侧 TTS 偶发不回调 / 返回空数据，
                // 同一句重提通常就成了；直接放弃会让用户看到一次莫名的「朗读失败」。
                // 每句只重试一次，避免在真的坏了的时候反复白等超时周期。
                if error.isTransient, self.renderRetriedIndex != index {

                    self.renderRetriedIndex = index

                    ReaderEnvironment.log("[Speech] 渲染失败重试一次 句序=\(index)")

                    self.submitCurrentSentence()

                    return
                }

                self.handleRenderFailure(error)
            }
        }
    }

    /// 把已经渲染好的音频交给播放器。
    private func playFragment(_ fragment: ReaderSpeechFragment, url: URL) {

        currentFragment = fragment

        // 会话与锁屏在**即将出声**时才激活，不在起播时 —— 渲染阶段不出声，
        // 提前激活会过早打断其它 App 的音频
        audioSession.activate()

        nowPlaying.activate()

        player.play(url: url)

        // 当前句已经在播了，渲染队列此刻空闲，正好拿来预合成后面几句。
        // 这是消掉句间停顿的关键：不预合成的话每句之间都要等一次渲染。
        prefetchUpcoming()
    }

    /// 预渲染当前句之后的若干句，只入缓存、不播放。
    ///
    /// 为什么放在「当前句开始播」之后而不是更早：渲染是串行的，提前提交只会跟当前句
    /// 抢队列，把起播拖慢。等当前句进了播放器再排预合成，队列必然是空的。
    ///
    /// 结果只写缓存，靠 `submitCurrentSentence()` 的缓存命中分支自然生效 ——
    /// 不需要把预合成的产物交接给播放链路，少一条容易出错的路径。
    private func prefetchUpcoming() {

        guard let currentIndex else { return }

        let session = sessionID

        for offset in 1...Self.prefetchDepth {

            let index = currentIndex + offset

            guard sentences.indices.contains(index) else { break }

            guard !prefetchedIndices.contains(index) else { continue }

            let sentence = sentences[index]

            let fragment = ReaderSpeechFragment(text: sentence.text,
                                                range: sentence.range,
                                                voiceIdentifier: voiceIdentifier,
                                                language: language)

            // 已经渲染过（听第二遍、或往回跳又读回来）：记下来别再提交
            if audioCache.url(for: fragment) != nil {

                prefetchedIndices.insert(index)

                continue
            }

            prefetchedIndices.insert(index)

            renderer.render(fragment, timeout: Self.renderTimeout) { [weak self] result in

                guard let self else { return }

                // 会话已变（停止 / 换章 / 用户另起一处朗读）：结果无用
                guard self.sessionID == session else { return }

                switch result {

                case .success(let data):

                    _ = self.audioCache.store(data, for: fragment)

                case .failure:

                    // 预合成失败不提示、不打断朗读 —— 用户根本不知道有这件事。
                    // 只把标记撤掉，真正播到这一句时会走正常渲染路径（那时才该报错）。
                    self.prefetchedIndices.remove(index)
                }
            }
        }
    }

    /// 渲染失败的处理。
    ///
    /// 阶段三会在这里接降级路径（退回 `AVSpeechSynthesizer` 直接出声，
    /// 保证「还能听书」）。当前先提示并停止。
    private func handleRenderFailure(_ error: ReaderSpeechRenderError) {

        switch error {

        case .voiceUnavailable:

            presentNotice(ReaderEnvironment.strings.speechVoiceUnavailable)

        case .emptyText, .timedOut, .renderFailed:

            presentNotice(ReaderEnvironment.strings.speechFailed)
        }

        stop()
    }

    /// 推进到下一句；本章读完则交给章节衔接。
    private func advanceToNextSentence() {

        guard let currentIndex else { return }

        let next = currentIndex + 1

        guard sentences.indices.contains(next) else {

            concludeChapter()

            return
        }

        self.currentIndex = next

        submitCurrentSentence()
    }

    /// 本章读完，交给章节衔接。加一条日志，便于发现异常的跨章节奏
    /// （正常一章要读几分钟；若日志里出现一秒一章，说明章节正文没真正加载，
    ///   见 `proceed(toChapterID:in:)`）。
    private func logChapterConclusion() {

        ReaderEnvironment.log("[Speech] 本章读完 句数=\(sentences.count) chapter=\(speakingChapterID ?? 0)")
    }

    /// 停止收尾。
    private func finishStop() {

        currentIndex = nil

        currentFragment = nil

        prefetchedIndices.removeAll()

        renderRetriedIndex = nil

        speakingSegmentStart = nil

        accumulatedSpeakingTime = 0

        isFollowSuspended = false

        awaitsRequestedPositionAlter = false

        // 换一个会话标识，让所有在途的异步结果（章节加载回调）作废。
        // 不做这一步的话，用户停止朗读后，之前发出的章节请求回来时会把朗读又启动起来。
        sessionID = UUID()

        clearHighlight()

        audioSession.deactivate()

        nowPlaying.deactivate()

        activity = .idle
    }

    // MARK: - 正文跟随

    /// 让正文跟上朗读位置。
    ///
    /// 两种阅读模式的跟随粒度不同，因为「一页」的含义不同：
    ///
    /// - **左右翻页**：一页 == 一屏，跟随只能按页，且**只在自然顺序推进
    ///   （目标页正好是当前页的下一页）时才翻**。
    /// - **上下滚动**：一页 != 一屏，可视区通常横跨两页，页内推进也需要滚动，
    ///   所以按**句的实际位置**跟随，由滚动容器自行判断要不要滚、滚多少。
    private func alignPage(to sentence: ReaderSentence) {

        // 第一条规则（两种模式共用）：**看得见就不动**，同时解除挂起。
        //
        // 这一句同时承担了「挂起的自动解除」：用户翻到后面的内容后跟随被挂起，
        // 视图停在他翻到的地方；朗读自然推进到那一页时句子重新可见，跟随就在这里恢复，
        // 不需要他再点任何按钮。
        if isSpeakingOnDisplayedPage {

            isFollowSuspended = false

            return
        }

        // 第二条规则（两种模式共用）：用户手动挪过视图就不跟随。
        //
        // 否则他刚翻过去 / 滚过去就被拽回来，等于禁止了「朗读中手动翻页」。
        // 此时胶囊呈现为「从这里开始读」，用户可按返回箭头立即对齐，
        // 也可以什么都不做 —— 等朗读读到他眼前这一页时上面那条会自动恢复跟随。
        guard !isFollowSuspended else { return }

        moveViewToSpeakingSentence(sentence)
    }

    /// 把正文移到当前朗读句处。两种模式的**判定**已在 `alignPage(to:)` 里统一，
    /// 这里只负责各自的移动手段。
    private func moveViewToSpeakingSentence(_ sentence: ReaderSentence) {

        guard let reader, let speakingChapter else { return }

        if ReaderConfiguration.shared().effectType == .scroll {

            guard let scrollController = reader.scrollController else { return }

            // 用户的手指或惯性还在滚动时不要插手：两个滚动同时进行会明显卡顿甚至跳变，
            // 「刚松手、惯性还没停」那一小段最容易撞上。
            //
            // 跳过没有后果：跟随每句判两次，下一次会再来。
            guard !scrollController.isUserScrolling else { return }

            // 滚动容器在库内，可直接按句定位；阅读记录由容器的滚动回调维护。
            // 容器内部还会判断「句子已在舒适区内就不滚」，避免逐句微抖。
            requestPositionAlter {

                scrollController.revealSpeechSentence(animated: true)
            }

            return
        }

        guard let record = reader.readModel?.recordModel,
              let displayedChapter = record.chapterModel,
              let chapterID = speakingChapter.id else { return }

        // 朗读章节与展示章节不是同一章时，页码之间没有可比性（各章页码都从 0 起算）。
        //
        // 注意这**不是**「跨章不跟随」——换章那一刻 `alignViewToChapterStart` 已经把
        // 正文带到新章了，正常情况下两者是同一章。这条只兜两种例外：
        // 接入方没注入 `presentPositionHandler`，或后台换章后还没回到前台。
        // 这两种情况下把用户从他正在看的章节拽走反而更糟，界面用三态按钮提示即可。
        guard speakingChapter.id == displayedChapter.id else { return }

        let displayedPage = record.page.intValue

        let targetPage = speakingChapter.page(location: sentence.range.location).intValue

        requestPositionAlter {

            if targetPage == displayedPage + 1 {

                // 相邻一页走接入方的翻页链路，保留原生翻页动画。
                // 左右翻页的整条链路（取页控制器、翻页动画、更新阅读记录、章末网络加载）
                // 都在接入方那侧，只能请求它推进一页。
                reader.advanceToNextPage()

            }else{

                // 相差不止一页（含往回）：**大字号下一个长句就能横跨两三页**，
                // 此时下一句的句首会直接落在两页之外，必须能一步跳过去。
                reader.presentPosition(chapterID: chapterID, location: sentence.range.location)
            }
        }
    }

    // MARK: - 跟随挂起

    /// 自动跟随是否已被用户手动挪动视图而挂起。两种阅读模式共用。
    ///
    /// 解除路径有三条，其中第一条不需要用户操作：
    /// - 朗读推进到用户眼前这一页（`alignPage(to:)` 的第一条规则）
    /// - 用户按返回箭头
    /// - 用户按「从这里开始读」
    private var isFollowSuspended = false

    /// 引擎已经请求了一次位置变更，还在等它被通报回来。
    ///
    /// **一次性令牌，不是时间窗口**：接入方的位置变更有同步的（普通翻页）也有异步的
    /// （章末需要联网加载下一章，见宿主 `processDragBoundaryForward`），用同步窗口判定
    /// 会把异步那条误判成用户操作，表现是每次跨章都错误挂起一次跟随。
    ///
    /// 令牌泄漏（请求发出但接入方最终没动，比如下一章被锁）时的退化方向是**安全**的：
    /// 用户接下来的一次手动翻页会消耗掉这个令牌、少挂起一次，下一次就恢复正常；
    /// 不会出现「永久挂起」这种只能靠点按钮才能救回来的状态。
    private var awaitsRequestedPositionAlter = false

    /// 在「这是引擎请求的位置变更」的标记下发起一次移动。
    private func requestPositionAlter(_ body: () -> Void) {

        awaitsRequestedPositionAlter = true

        body()
    }

    /// 接入方通报「用户主动挪动了视图」。
    ///
    /// 滚动模式由容器在 `scrollViewWillBeginDragging` 时调用 —— 那是明确的用户信号，
    /// 不需要靠令牌推断。左右翻页模式没有等价信号，走 `handleDisplayedPositionAlter()`
    /// 里的令牌判定。
    public func handleUserInitiatedPositionAlter() {

        guard activity != .idle else { return }

        isFollowSuspended = true
    }

    /// 接入方通报「正文展示位置变了」。
    ///
    /// 做两件事：
    ///
    /// 1. 把当前朗读句的高亮在新页上补画一遍 —— 高亮是写在具体某个正文视图上的属性，
    ///    换页即换视图，不补这一笔的表现是「翻过去高亮不见了，要等下一句开口才恢复」
    /// 2. 判断这次变更是不是引擎自己请求的；不是就说明用户手动挪了视图，挂起跟随
    public func handleDisplayedPositionAlter() {

        if awaitsRequestedPositionAlter {

            // 是引擎请求的那一次，消耗掉令牌
            awaitsRequestedPositionAlter = false

        }else{

            handleUserInitiatedPositionAlter()
        }

        reviseHighlightForDisplayedPage()
    }

    // MARK: - 高亮

    /// 当前朗读句落在指定页内的范围。
    ///
    /// 换算链：句的**章内绝对范围** ∩ 页的章内范围 → 平移 `-页起始位置` 得页内范围。
    /// 三者同坐标系（都以 `fullContent` 为基准），所以只做交集与平移，不需要别的换算。
    ///
    /// - Parameters:
    ///   - pageModel: 目标页
    ///   - chapterID: 目标页所属章节。**必须传**：不同章节的页范围都从 0 起算，
    ///     只比范围会把另一章同位置的段落也点亮。
    /// - Returns: 当前没在朗读、朗读在别的章、或该句不落在本页时返回 nil。
    public func highlightRange(inPage pageModel: ReaderPageModel, chapterID: NSNumber?) -> NSRange? {

        guard activity != .idle else { return nil }

        guard let speakingChapterID, let chapterID, speakingChapterID == chapterID else { return nil }

        guard let sentenceRange = speakingRange, let pageRange = pageModel.range else { return nil }

        let overlap = NSIntersectionRange(sentenceRange, pageRange)

        guard overlap.length > 0 else { return nil }

        return NSMakeRange(overlap.location - pageRange.location, overlap.length)
    }

    /// 刷新所有跟「朗读位置」有关的界面：正文高亮 + 控制胶囊。
    ///
    /// 两件事必须一起做：胶囊显示 `.playing` 还是 `.offPage`，取决于朗读位置是否
    /// 仍落在当前展示页上。凡是需要重写高亮的时刻，这个判断结果也可能刚变过，
    /// 分开调用早晚会漏掉某条路径。
    private func reviseSpeechPresentation(for sentence: ReaderSentence) {

        applyHighlight(for: sentence)

        reader?.reviseSpeechActionButton(animated: true)
    }

    /// 把当前朗读句的高亮重新写到正在展示的页上。
    ///
    /// 与 `applyHighlight(for:)` 的区别是**触发方向相反**：那个是「朗读推进了，
    /// 把新句画上去」，本方法是「展示的页换了，把当前句在新页上补画一遍」。
    ///
    /// 必要性：高亮是写在具体某个 `ReaderPageView` 上的属性。用户在朗读中手动翻页时，
    /// 新页的视图是新建的、身上没有高亮，而朗读句可能恰好跨到了这一页；
    /// 不补这一笔，界面上就是「翻过去高亮不见了」，要等下一句开口才恢复。
    public func reviseHighlightForDisplayedPage() {

        guard let sentence = currentSentence else { return }

        applyHighlight(for: sentence)
    }

    /// 把当前句的高亮写到正在渲染的页上。
    private func applyHighlight(for sentence: ReaderSentence) {

        guard let reader else { return }

        if ReaderConfiguration.shared().effectType == .scroll {

            // 滚动模式同屏可能有多页可见，交给容器逐个可见 cell 判定
            reader.scrollController?.reviseSpeechHighlight()

        }else{

            guard let display = reader.currentDisplayController else { return }

            // 新页控制器刚被 `setViewControllers` 接进容器时，视图加载是延后的，
            // 此刻 `renderingPageView` 还是 nil。不强制加载就会静默跳过这一笔，
            // 表现是「翻过去这一页整句都没有高亮，要等下一句开口才出现」。
            display.loadViewIfNeeded()

            guard let pageView = display.renderingPageView,
                  let record = display.recordModel,
                  let displayedChapter = record.chapterModel,
                  let pageModel = record.pageModel else { return }

            pageView.speechHighlightRange = highlightRange(inPage: pageModel,
                                                          chapterID: displayedChapter.id)
        }
    }

    /// 清除高亮。
    ///
    /// 两种模式都清一遍而不按当前模式分支：用户可能在朗读中切过阅读方向，
    /// 只清当前模式会把另一套视图上的高亮留在那里。
    private func clearHighlight() {

        guard let reader else { return }

        reader.currentDisplayController?.renderingPageView?.speechHighlightRange = nil

        reader.scrollController?.clearSpeechHighlight()
    }

    // MARK: - 章节衔接

    /// 本章读完后的衔接。
    ///
    /// 下一章的解析走 `ReaderBookModel.resolvedFollowingChapterID(forChapterID:)`，
    /// 不看 `chapterModel.nextChapterID` —— 后者可能过期或被污染，书里已有权威判定。
    private func concludeChapter() {

        logChapterConclusion()

        guard let reader, let book = reader.readModel else {

            stop()

            return
        }

        if let nextChapterID = book.resolvedFollowingChapterID(forChapterID: speakingChapterID) {

            proceed(toChapterID: nextChapterID, in: book)

            return
        }

        // 解析为 nil 有两种完全不同的语义，必须靠目录完整性区分：
        // 目录完整 → 这是全书真末章；目录不完整 → 只是下一章还没进目录，
        // 绝不能当成全书读完（会让用户以为书没了）。
        if book.isChapterListComplete {

            stop()

            return
        }

        // 请求接入方补齐后续目录页，本次朗读到此为止。
        // 不在这里等目录回来再续读：目录补齐是可能失败、也可能很慢的网络动作，
        // 挂着一个「随时可能自己响起来」的朗读比停下来更难预期。
        reader.chapterUnlockDelegate?.readControllerDidReachUnloadedBoundary(reader)

        stop()
    }

    /// 切到下一章并续读。
    private func proceed(toChapterID chapterID: NSNumber, in book: ReaderBookModel) {

        // **先让在途的异步结果全部作废。**
        //
        // `renderer.cancelAll()` 不够：它只递增渲染器的世代号，拦得住「还没开始」和
        // 「正在渲染」的，拦不住**已经通过世代检查、派发到主线程、还没执行**的那一个。
        // 那个 completion 执行时若 `sessionID` 尚未更新（它要等章节加载回来、走到
        // `beginSpeaking` 才换），就会通过会话检查，把**上一章的句子**播出去。
        //
        // 真机上表现为章节索引在两章之间来回跳、反复重播已经读过的音频（都是缓存命中，
        // 所以日志里只有「播放器提交音频」而没有「渲染完成」）。
        //
        // 放在这里而不是各个调用点：跨章有两条路径（用户点上/下一章、本章自然读完），
        // 都必经此处。
        sessionID = UUID()

        let storyID = book.storyID

        // 已缓存直接切，不必走网络。
        //
        // ⚠️ **「归档存在」不等于「有正文」。** 目录加载会为每一章建立归档，里面只有 id
        // 与标题，`content` 是空的。拿这种空壳去分句，只会得到标题那一句 ——
        // 读完立刻 `concludeChapter()` 跨到下一章，而下一章同样是空壳，于是**雪崩式跨章**：
        // 真机上表现为一秒跳一章、每章 timeline 都停在 0，最后停在一个「只有标题、
        // 正文全空」的页面上。
        //
        // 旧架构下这个缺陷被朗读速度掩盖了（`AVSpeechSynthesizer` 读一句要好几秒，
        // 足够章节加载完成）；换成「渲染 + 播放」后单句只要 0.2 秒、命中缓存几乎瞬时，
        // 朗读推进远快于网络加载，缺陷就暴露出来。
        if ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID) {

            let cached = ReaderChapterModel.model(storyID: storyID, chapterID: chapterID)

            if Self.hasReadableBody(cached) {

                beginChapter(cached)

                return
            }

            ReaderEnvironment.log("[Speech] 章节 \(chapterID) 有归档但无正文，改走网络加载")
        }

        guard let loader = reader?.chapterLoader else {

            stop()

            return
        }

        // 捕获当前会话标识：加载是异步的，用户完全可能在等待期间停止朗读或换到别处。
        // 回来时标识已变，说明这份结果属于上一次会话，必须丢掉。
        let token = sessionID

        let dispatched = loader.loadChapter(chapterId: chapterID.intValue) { [weak self] chapter in

            guard let self, self.sessionID == token else { return }

            self.beginChapter(chapter)

        } failureBlock: { [weak self] _ in

            guard let self, self.sessionID == token else { return }

            self.presentNotice(ReaderEnvironment.strings.chapterLoadFailed(self.chapterName(for: chapterID, in: book)))

            self.stop()
        }

        // 返回 false 表示被节流，两个回调都不会来，得自己收尾，否则朗读会静默悬停
        if !dispatched { stop() }
    }

    /// 章节是否有可朗读的正文。
    ///
    /// 判据是 `content`（正文纯文本）而**不是** `fullContent` —— 后者是「标题 + 正文」，
    /// 正文为空时它仍然非空（只剩标题），用它判断会把空壳章节当成可读。
    private static func hasReadableBody(_ chapter: ReaderChapterModel) -> Bool {

        guard let body = chapter.content else { return false }

        return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 换章后从该章开头续读。
    private func beginChapter(_ chapter: ReaderChapterModel) {

        guard prepare(chapter: chapter) else {

            // 准备失败（正文缺失、无可用音色）。**必须收尾** ——
            // 不 stop 的话 `activity` 会停在 `.playing` / `.preparing`，
            // 界面与锁屏显示「正在读」而实际什么都没发生，且不会自愈。
            ReaderEnvironment.log("[Speech] 章节准备失败，停止朗读 chapter=\(chapter.id ?? 0)")

            stop()

            return
        }

        // 先把正文带到新章节，再开口读。顺序反过来的话，第一句的 didStart 回调
        // 可能落在旧视图上，高亮会写到即将被销毁的页上、看起来是「高亮没出现」。
        alignViewToChapterStart(chapter)

        start(fromLocation: 0)

        // 章节变了但 activity 没变（还是 playing），不会触发 activity 的 didSet，
        // 所以锁屏信息要在这里显式刷一次，否则锁屏上的章节名会停在上一章
        publishNowPlaying()
    }

    /// 朗读切到新章节时，把正文一并带过去。
    ///
    /// 需要接入方注入 `presentPositionHandler`（左右翻页与滚动模式都得经它，
    /// 因为跨章跳转要重建整条章节数据链，不是单纯翻一页）。未注入时正文停在原处，
    /// 朗读照常进行，界面靠三态按钮呈现为「从这里开始读」。
    private func alignViewToChapterStart(_ chapter: ReaderChapterModel) {

        // **只在前台激活时导航。**
        //
        // 判据必须是 `.active`，不能只排除 `.background` —— 锁屏过渡、来电、
        // 下拉控制中心这些情况下 `applicationState` 是 `.inactive`，窗口不可见、
        // 布局同样不可信，此时跳页会让容器停在错误状态（详见 `observeAppLifecycle`）。
        //
        // 这个判据与 `ReaderScreenMetrics` 取安全区时的 `.foregroundActive` 保持一致；
        // 两处口径不同曾经就是缺陷的来源。
        //
        // 跳过之后不会漏：回到前台激活时 `handleDidBecomeActive` 会统一对齐。
        guard UIApplication.shared.applicationState == .active else {

            ReaderEnvironment.log("[Speech] 非前台激活，跳过跨章导航，等回前台统一对齐")

            return
        }

        guard let reader, let chapterID = chapter.id else { return }

        // 已经在这一章就别跳，跳转会重建正文视图（闪屏 + 丢滚动位置）
        if let record = reader.readModel?.recordModel,
           let displayedChapter = record.chapterModel,
           displayedChapter.id == chapterID { return }

        // 换章是引擎驱动的，走令牌，别被判成用户手动跳章
        requestPositionAlter {

            reader.presentPosition(chapterID: chapterID, location: 0)
        }
    }

    /// 请求切章。
    ///
    /// 不必像以前那样「先停下来等取消回调再切」（播放器允许随时替换内容），
    /// 但**必须先把当前播放停掉**，见下方说明。
    private func requestChapterSwitch(to chapterID: NSNumber) {

        guard let book = reader?.readModel else { return }

        // 在途的渲染属于旧章节，撤掉。
        // 注意这一步不足以拦住已派发到主线程的 completion，那个由 `proceed` 里的
        // `sessionID` 更新负责作废。
        renderer.cancelAll()

        // **当前播放也要停。** 新章的首句要先渲染，这期间旧句仍在播，
        // 它播完会投递「播放结束」，而那个回调会走 `advanceToNextSentence()` ——
        // 此时 `currentIndex` 已经被新章覆盖成 0，于是直接推进到第 2 句，
        // 新章第一句被跳掉。
        player.stop()

        proceed(toChapterID: chapterID, in: book)
    }

    /// 解析指定章节的上一章。
    ///
    /// `ReaderBookModel` 只提供了 `resolvedFollowingChapterID`，没有反向的，
    /// 这里按同样的口径（以目录列表为权威，不信 `chapterModel.previousChapterID`）自己算。
    private func precedingChapterID(of chapterID: NSNumber?, in book: ReaderBookModel) -> NSNumber? {

        guard let chapterID,
              let list = book.chapterListModels,
              let index = list.firstIndex(where: { $0.id == chapterID }),
              index > 0 else { return nil }

        return list[index - 1].id
    }

    /// 取章节名，供加载失败提示使用。
    private func chapterName(for chapterID: NSNumber, in book: ReaderBookModel) -> String {

        let matched = book.chapterListModels?.first { $0.id == chapterID }

        return matched?.name ?? ReaderEnvironment.strings.unnamedChapter
    }

    // MARK: - 辅助

    /// 向用户提示，挂在阅读器视图上。
    private func presentNotice(_ message: String) {

        guard let container = reader?.view else { return }

        ReaderEnvironment.presentErrorNotice(container, message)
    }

    /// 通报活动状态变化，并同步锁屏信息。
    private func notifyActivityAlter() {

        publishNowPlaying()

        reader?.reviseSpeechActionButton(animated: true)

        coordinator?.speechDidChangeActivity(activity, context: makeContext())
    }

    /// 重新把当前上下文写到锁屏 / 控制中心。
    ///
    /// 供接入方在**异步资源就绪后**主动刷新，典型场景是封面图下载完成：
    /// `nowPlayingArtwork()` 是同步接口、首次通常返回 nil（不能在那里同步等网络，
    /// 会卡住朗读推进），不主动刷新的话封面要等到下一次状态变化
    /// （暂停 / 继续 / 换章）才出现 —— 表现为「锁屏上要切一次章封面才显示」。
    ///
    /// 未在朗读时为空操作。
    public func refreshNowPlaying() {

        guard activity != .idle else { return }

        publishNowPlaying()
    }

    /// 把当前上下文写到锁屏。
    private func publishNowPlaying() {

        nowPlaying.update(context: makeContext(),
                          activity: activity,
                          artwork: coordinator?.nowPlayingArtwork())
    }

    /// 组装中立上下文快照。
    private func makeContext() -> ReaderSpeechContext {

        let book = reader?.readModel

        // 用**朗读中**的章节而非展示中的章节：跨章后两者不同，
        // 用后者会让锁屏上的章节名停在用户最后看到的那一章
        let chapter = speakingChapter

        let sentence = currentSentence

        let totalLength = chapter?.fullContent?.length ?? 0

        var progress: Double = 0

        var spokenLength = 0

        if totalLength > 0, let sentence {

            spokenLength = min(totalLength, max(0, sentence.range.location))

            progress = Double(spokenLength) / Double(totalLength)
        }

        // 时间轴**必须提供**，不能只给 progress：锁屏 / 控制中心确认播放状态变更时会一并
        // 读时间轴。但它同样**必须连续** —— 给一个原地不动的已播时间比不给更糟，
        // 系统会因为「声称在播放、时间却不走」而不再采信我们声明的 rate（详见
        // `accumulatedSpeakingTime` 的说明，那正是 1.7.1 把锁屏页弄坏的原因）。
        //
        // 所以已播时间取**实际经过的出声时长**，不用字符位置折算。
        let elapsed = accumulatedSpeakingTime + (speakingSegmentStart.map { Date().timeIntervalSince($0) } ?? 0)

        // 总时长按字符数与语言平均语速估算。**刻意不按「实测速率」外推** ——
        // 试过，结果是刚起播时把总时长算成三倍多（`spokenLength` 取的是当前句**句首**
        // 位置，是个离散值，读了 5 秒时它还很小，据此算出的速率极低）。
        // 字符估算虽然绝对值不准，但稳定、不会跳。
        let estimated = Double(totalLength) / Self.estimatedCharactersPerSecond(forLanguage: language)

        // 唯一的例外：实际读得比估算慢（低语速倍率、朗读较慢的音色）以致已播时间超过了
        // 估算总长。此时必须外推，否则会出现「已播时间 > 总时长」这种自相矛盾的组合。
        let duration: TimeInterval

        if elapsed > estimated, spokenLength > 0 {

            duration = elapsed * Double(totalLength) / Double(spokenLength)

        }else{

            duration = estimated
        }

        // 播放队列：一项 = 一章，与锁屏「上一曲 / 下一曲」的映射保持一致。
        // 目录未加载完时给的是当前已知章节数，会随补目录变大 —— 与用户在目录里看到的一致。
        let chapterList = book?.chapterListModels

        let queueCount = chapterList?.count ?? 0

        var queueIndex = 0

        if let chapterList, let speakingChapterID,
           let matched = chapterList.firstIndex(where: { $0.id == speakingChapterID }) {

            queueIndex = matched
        }

        return ReaderSpeechContext(bookTitle: book?.storyName ?? "",
                                   chapterTitle: chapter?.name ?? "",
                                   sentenceText: sentence?.text ?? "",
                                   chapterProgress: progress,
                                   estimatedDuration: duration,
                                   estimatedElapsed: elapsed,
                                   queueCount: queueCount,
                                   queueIndex: queueIndex,
                                   hasPreviousChapter: precedingChapterIDForSkip != nil,
                                   hasNextChapter: followingChapterIDForSkip != nil)
    }

    /// 按语言估算每秒朗读的字符数。
    ///
    /// 只用于折算锁屏时间轴，**不参与朗读本身**，所以精度要求很低 ——
    /// 目标是让进度条比例正确、时间数字不至于离谱，而不是精确预测。
    ///
    /// CJK 单字信息量大、语速慢；拉丁文按字符计快得多。两档足够，
    /// 再细分意义不大（真实语速还受音色与设备影响）。
    private static func estimatedCharactersPerSecond(forLanguage language: String?) -> Double {

        guard let language, !language.isEmpty else { return 15 }

        let primary = language.split(separator: "-").first.map(String.init)?.lowercased() ?? ""

        switch primary {

        case "zh", "ja", "ko": return 5.5

        default: return 15
        }
    }
}

// MARK: - ReaderSpeechPlayerDelegate

extension ReaderSpeechController: ReaderSpeechPlayerDelegate {

    func speechPlayerDidStart(_ player: ReaderSpeechPlayer) {

        // 出声计时开始。已经在计时中就不动 —— 连续朗读时句与句之间不该断开，
        // 否则每次换句都会丢掉一小段，时间轴会越走越慢。
        if speakingSegmentStart == nil { speakingSegmentStart = Date() }

        activity = .playing

        guard let currentIndex, sentences.indices.contains(currentIndex) else { return }

        // 再给跟随一次机会。
        //
        // `submitCurrentSentence()` 里已经对齐过一次，但那一刻上一句触发的翻页动画
        // 可能还在飞、阅读记录也可能还没落定，判断会失准。真正出声时（这里）动画早已结束，
        // 此时补判一次，跟随就从「一句只有一次机会」变成「会收敛」——
        // 单次失准最多晚半秒，不会拖累整句。已经对齐时本调用是空操作。
        alignPage(to: sentences[currentIndex])

        // 高亮挂在真正出声之后：从提交音频到出声之间有就绪耗时，
        // 提前高亮会让画面比声音快一截，看起来像高亮跑到了下一句
        reviseSpeechPresentation(for: sentences[currentIndex])
    }

    func speechPlayerDidFinish(_ player: ReaderSpeechPlayer) {

        // 用户已经暂停或停止时不要推进。
        //
        // 通知是异步派发的，所以「音频即将播完」那一瞬间的暂停，可能排在这条通知之前 ——
        // 漏掉这道判断就会推进到下一句并播起来，用户看到的是「点了暂停，声音停了一下
        // 又自己读下去」。
        guard activity == .playing else {

            ReaderEnvironment.log("[Speech] 播放结束但已不在播放态（\(activity)），不推进")

            return
        }

        advanceToNextSentence()
    }

    func speechPlayerDidFail(_ player: ReaderSpeechPlayer, error: Error?) {

        // 播放失败最常见的原因是音频文件损坏 —— 比如上一次写盘被系统杀掉，
        // 留下一个截断文件，而它的文件名（内容哈希）看起来完全有效。
        // 所以先把这份缓存删掉，避免下次又命中它、陷入每次到这句就失败的循环。
        if let fragment = currentFragment { audioCache.remove(for: fragment) }

        presentNotice(ReaderEnvironment.strings.speechFailed)

        stop()
    }

    func speechPlayerDidLoadDuration(_ player: ReaderSpeechPlayer) {

        // 时长可能晚于开始出声才解析出来，补写一次锁屏时间轴
        publishNowPlaying()
    }
}

// MARK: - ReaderSpeechAudioSessionDelegate

extension ReaderSpeechController: ReaderSpeechAudioSessionDelegate {

    func audioSessionRequestsPause() { pause() }

    func audioSessionRequestsResume() { resume() }

    func audioSessionRequestsStop() { stop() }
}

// MARK: - ReaderSpeechRemoteCommandDelegate

extension ReaderSpeechController: ReaderSpeechRemoteCommandDelegate {

    var canRespondToRemoteCommand: Bool { activity != .idle }

    func remoteCommandRequestsPlay() {

        ReaderEnvironment.log("[Speech] 收到远程命令 play")

        resume()
    }

    func remoteCommandRequestsPause() {

        ReaderEnvironment.log("[Speech] 收到远程命令 pause")

        pause()
    }

    func remoteCommandRequestsToggle() {

        ReaderEnvironment.log("[Speech] 收到远程命令 togglePlayPause activity=\(activity)")


        switch activity {

        // 准备中也当作「正在播」处理：用户此刻按下的意思是「停下」
        case .playing, .preparing: pause()

        case .paused: resume()

        case .idle: break
        }
    }

    func remoteCommandRequestsPreviousChapter() { skipToPreviousChapter() }

    func remoteCommandRequestsNextChapter() { skipToNextChapter() }
}
