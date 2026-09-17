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

    /// 合成引擎。默认是设备端实现，二期可换成云端实现而不改本类。
    private let synthesizer: ReaderSpeechSynthesizing

    /// 音频会话与系统中断。
    private let audioSession: ReaderSpeechAudioSession

    /// 锁屏播放信息与远程控制。
    private let nowPlaying: ReaderSpeechNowPlaying

    /// 宿主协调扩展点。未注入时全部走默认行为。
    public weak var coordinator: ReaderSpeechCoordinating? {

        didSet {

            audioSession.isManagedExternally = coordinator?.managesAudioSessionExternally ?? false

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

    /// 朗读控制胶囊该显示成哪一态。
    ///
    /// 把「活动状态」与「朗读位置是否在当前展示页」两件事收敛成一个枚举，
    /// 界面直接照它渲染即可，不必自己判断位置关系。
    public var actionState: ReaderSpeechActionState {

        switch activity {

        case .idle:

            return .idle

        case .playing:

            return isSpeakingOnDisplayedPage ? .playing : .offPage

        case .paused:

            return isSpeakingOnDisplayedPage ? .paused : .offPage
        }
    }

    /// 朗读位置是否落在当前展示页上。
    ///
    /// 两个条件都要满足：同一章、且同一页。只比页码会在跨章时误判
    /// （各章页码都从 0 起算，第 2 章第 0 页与第 3 章第 0 页页码相同）。
    private var isSpeakingOnDisplayedPage: Bool {

        guard let sentence = currentSentence,
              let speakingChapter,
              let record = reader?.readModel?.recordModel,
              let displayedChapter = record.chapterModel,
              speakingChapter.id == displayedChapter.id else { return false }

        return speakingChapter.page(location: sentence.range.location).intValue == record.page.intValue
    }

    /// 把正文跳回朗读位置。控制胶囊上的返回箭头调这个。
    ///
    /// 与 `alignPage(to:)` 的区别：那个只在自然顺序推进时跟随、且只前进一页；
    /// 本方法是用户主动要求对齐，任意距离、任意方向都跳。
    public func returnToSpeakingPosition() {

        guard let reader,
              let speakingChapter,
              let chapterID = speakingChapter.id,
              let sentence = currentSentence else { return }

        reader.presentPosition(chapterID: chapterID, location: sentence.range.location)

        applyHighlight(for: sentence)
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

    /// 停止完成后要接着做的事。
    ///
    /// 换句（重新指定起点）不能直接提交新片段 —— 引擎只在 idle 状态接受提交。
    /// 所以流程是「记下待办 → stop() → 等取消回调 → 执行待办」。
    private var pendingIntent: PendingIntent?

    private enum PendingIntent {

        /// 停止收尾后从指定章内坐标重新开始。
        case restart(location: NSInteger)

        /// 停止收尾后切到指定章节并从头读。
        case switchChapter(id: NSNumber)

        /// 单纯停止。
        case halt
    }

    // MARK: - 构造

    /// - Parameters:
    ///   - reader: 所属阅读器
    ///   - synthesizer: 合成引擎，默认设备端实现
    public init(reader: ReaderViewController,
                synthesizer: ReaderSpeechSynthesizing = ReaderSystemSpeechSynthesizer()) {

        self.reader = reader

        self.synthesizer = synthesizer

        self.audioSession = ReaderSpeechAudioSession()

        self.nowPlaying = ReaderSpeechNowPlaying()

        self.synthesizer.delegate = self

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

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handleWillEnterForeground),
                                              name: UIApplication.willEnterForegroundNotification,
                                              object: nil)
    }

    /// 回到前台：把正文对齐到当前朗读位置。
    ///
    /// 后台听书期间正文视图不跟着走（没必要，也做不了动画），所以回来时可能已经
    /// 隔了好几页甚至好几章。不对齐的话用户看到的是自己离开时那一页，
    /// 与耳朵里听到的内容对不上。
    @objc private func handleWillEnterForeground() {

        guard activity != .idle else { return }

        guard let reader,
              let speakingChapter,
              let chapterID = speakingChapter.id,
              let sentence = currentSentence else { return }

        // 已经对齐就不要跳：跳转会重建正文视图，无谓的重建既闪屏也丢滚动位置
        if let record = reader.readModel?.recordModel,
           let displayedChapter = record.chapterModel,
           displayedChapter.id == chapterID,
           speakingChapter.page(location: sentence.range.location).intValue == record.page.intValue {

            applyHighlight(for: sentence)

            return
        }

        reader.presentPosition(chapterID: chapterID, location: sentence.range.location)

        // 跳转后视图是新建的，高亮要重新写一遍
        applyHighlight(for: sentence)
    }

    // MARK: - 对外控制

    /// 从当前展示页开始朗读。
    ///
    /// 起点取当前页起始坐标所属的那个句的**句首**：页边界通常落在句子中间，
    /// 从页边界读起会从半句开始，听感是漏了前半句。
    public func startFromCurrentPage() {

        guard let record = reader?.readModel?.recordModel,
              let chapter = record.chapterModel else { return }

        guard prepare(chapter: chapter) else { return }

        start(fromLocation: record.locationFirst.intValue)
    }

    /// 从指定章内绝对坐标开始朗读。
    public func start(fromLocation location: NSInteger) {

        // 引擎非空闲时不能直接提交，先停再续（见 pendingIntent 的说明）
        guard synthesizer.state == .idle else {

            pendingIntent = .restart(location: location)

            synthesizer.stop()

            return
        }

        beginSpeaking(fromLocation: location)
    }

    /// 暂停。
    public func pause() {

        guard activity == .playing else { return }

        synthesizer.pause()

        activity = .paused
    }

    /// 从暂停位置继续。
    public func resume() {

        guard activity == .paused else { return }

        // 中断（来电等）期间系统会把会话置为非激活，继续前必须重新激活，
        // 否则 continueSpeaking 不出声
        audioSession.activate()

        synthesizer.resume()

        activity = .playing
    }

    /// 切到下一章并从头朗读。锁屏「下一曲」与界面跳章都走这里。
    ///
    /// 已是末章时静默忽略 —— 锁屏按钮点了没反应比读出错误内容好。
    public func skipToNextChapter() {

        guard let book = reader?.readModel,
              let target = book.resolvedFollowingChapterID(forChapterID: speakingChapterID) else { return }

        requestChapterSwitch(to: target)
    }

    /// 切到上一章并从头朗读。已是首章时静默忽略。
    public func skipToPreviousChapter() {

        guard let book = reader?.readModel,
              let target = precedingChapterID(of: speakingChapterID, in: book) else { return }

        requestChapterSwitch(to: target)
    }

    /// 停止朗读并释放音频会话。
    public func stop() {

        guard activity != .idle else { return }

        pendingIntent = .halt

        synthesizer.stop()

        // 引擎已经是 idle（例如最后一句刚读完还没决定下一步）时，
        // stop() 不会产生取消回调，需要在这里直接收尾，否则状态永远停在播放中
        if synthesizer.state == .idle {

            pendingIntent = nil

            finishStop()
        }
    }

    // MARK: - 章节准备

    /// 为指定章节准备分句、语言与音色。已准备过同一章则复用。
    ///
    /// - Returns: 准备失败（缺正文、无可用音色）时返回 false，并已向用户提示。
    private func prepare(chapter: ReaderChapterModel) -> Bool {

        if let speakingChapterID, speakingChapterID == chapter.id, !sentences.isEmpty { return true }

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

        currentIndex = index

        audioSession.activate()

        nowPlaying.activate()

        submitCurrentSentence()
    }

    /// 把当前句交给引擎。
    private func submitCurrentSentence() {

        guard let currentIndex, sentences.indices.contains(currentIndex) else { return }

        let sentence = sentences[currentIndex]

        // 翻页放在提交之前：翻页有动画耗时，等出声了再翻会出现「声音已经在读下一页、
        // 画面还停在上一页」。高亮则相反，挂在 didStart（见该回调的说明）。
        alignPage(to: sentence)

        let fragment = ReaderSpeechFragment(text: sentence.text,
                                           range: sentence.range,
                                           voiceIdentifier: voiceIdentifier,
                                           language: language)

        synthesizer.speak(fragment)
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

    /// 停止收尾。
    private func finishStop() {

        currentIndex = nil

        // 换一个会话标识，让所有在途的异步结果（章节加载回调）作废。
        // 不做这一步的话，用户停止朗读后，之前发出的章节请求回来时会把朗读又启动起来。
        sessionID = UUID()

        clearHighlight()

        audioSession.deactivate()

        nowPlaying.deactivate()

        activity = .idle
    }

    // MARK: - 翻页跟随

    /// 让正文跟上朗读位置。
    ///
    /// **只在自然顺序推进（目标页正好是当前页的下一页）时才翻页。**
    ///
    /// 这条限制是刻意的：用户在朗读中手动翻页或跳章后，朗读位置会与展示页脱开，
    /// 若无条件「翻到朗读所在页」，用户刚翻过去就被拽回来，等于禁止了手动翻页。
    /// 脱开状态下界面会把控制按钮切成「从这里开始读」，由用户决定要不要对齐。
    private func alignPage(to sentence: ReaderSentence) {

        guard let reader,
              let record = reader.readModel?.recordModel,
              let displayedChapter = record.chapterModel,
              let speakingChapter else { return }

        // 朗读章节与展示章节不是同一章时，页码之间没有可比性（各章页码都从 0 起算），
        // 直接返回。
        //
        // 注意这**不是**「跨章不跟随」——换章那一刻 `alignViewToChapterStart` 已经把
        // 正文带到新章了，正常情况下两者是同一章。这条只兜两种例外：
        // 接入方没注入 `presentPositionHandler`，或后台换章后还没回到前台。
        // 这两种情况下把用户从他正在看的章节拽走反而更糟，界面用三态按钮提示即可。
        guard speakingChapter.id == displayedChapter.id else { return }

        let targetPage = speakingChapter.page(location: sentence.range.location).intValue

        guard targetPage == record.page.intValue + 1 else { return }

        if ReaderConfiguration.shared().effectType == .scroll {

            // 滚动容器在库内，可直接定位；阅读记录由容器的滚动回调维护
            reader.scrollController?.scrollToSpeechPage(chapterID: speakingChapter.id, page: targetPage)

        }else{

            // 左右翻页的整条链路（取页控制器、翻页动画、更新阅读记录、章末网络加载）
            // 都在接入方那侧，只能请求它推进一页
            reader.advanceToNextPage()
        }
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

    /// 把当前句的高亮写到正在渲染的页上。
    private func applyHighlight(for sentence: ReaderSentence) {

        guard let reader else { return }

        if ReaderConfiguration.shared().effectType == .scroll {

            // 滚动模式同屏可能有多页可见，交给容器逐个可见 cell 判定
            reader.scrollController?.reviseSpeechHighlight()

        }else{

            guard let display = reader.currentDisplayController,
                  let pageView = display.renderingPageView,
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

        let storyID = book.storyID

        // 已缓存直接切，不必走网络
        if ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID) {

            beginChapter(ReaderChapterModel.model(storyID: storyID, chapterID: chapterID))

            return
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

    /// 换章后从该章开头续读。
    private func beginChapter(_ chapter: ReaderChapterModel) {

        guard prepare(chapter: chapter) else { return }

        // 先把正文带到新章节，再开口读。顺序反过来的话，第一句的 didStart 回调
        // 可能落在旧视图上，高亮会写到即将被销毁的页上、看起来是「高亮没出现」。
        alignViewToChapterStart(chapter)

        // 走到这里时引擎必然是 idle（本方法只由 didFinish 链路与其异步续接触发），
        // 所以 start 会直接提交而不是排待办
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

        // 后台不导航：视图不可见，重建纯属浪费，且部分容器在后台布局会拿到错误尺寸。
        // 回前台时 handleWillEnterForeground 会统一对齐，不会漏。
        guard UIApplication.shared.applicationState != .background else { return }

        guard let reader, let chapterID = chapter.id else { return }

        // 已经在这一章就别跳，跳转会重建正文视图（闪屏 + 丢滚动位置）
        if let record = reader.readModel?.recordModel,
           let displayedChapter = record.chapterModel,
           displayedChapter.id == chapterID { return }

        reader.presentPosition(chapterID: chapterID, location: 0)
    }

    /// 请求切章。引擎在忙时先停再切。
    private func requestChapterSwitch(to chapterID: NSNumber) {

        guard let book = reader?.readModel else { return }

        guard synthesizer.state == .idle else {

            pendingIntent = .switchChapter(id: chapterID)

            synthesizer.stop()

            return
        }

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

        coordinator?.speechDidChangeActivity(activity, context: makeContext())
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

        // 章内进度按字符位置估算。刻意不做时间维度的进度：
        // AVSpeechSynthesizer 不提供音频时长，任何「还剩几分钟」都是编的。
        let totalLength = chapter?.fullContent?.length ?? 0

        var progress: Double = 0

        if totalLength > 0, let sentence {

            progress = min(1, max(0, Double(sentence.range.location) / Double(totalLength)))
        }

        return ReaderSpeechContext(bookTitle: book?.storyName ?? "",
                                   chapterTitle: chapter?.name ?? "",
                                   sentenceText: sentence?.text ?? "",
                                   chapterProgress: progress)
    }
}

// MARK: - ReaderSpeechSynthesizingDelegate

extension ReaderSpeechController: ReaderSpeechSynthesizingDelegate {

    public func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didStart fragment: ReaderSpeechFragment) {

        activity = .playing

        guard let currentIndex, sentences.indices.contains(currentIndex) else { return }

        // 高亮挂在真正出声之后：引擎从收到请求到出声之间有延迟，
        // 提前高亮会让画面比声音快一截，看起来像高亮跑到了下一句
        applyHighlight(for: sentences[currentIndex])
    }

    public func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didFinish fragment: ReaderSpeechFragment) {

        advanceToNextSentence()
    }

    public func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didCancel fragment: ReaderSpeechFragment) {

        // 取消回调是「待办」的执行时机：引擎此刻确认回到 idle，可以安全提交新片段
        guard let intent = pendingIntent else {

            finishStop()

            return
        }

        pendingIntent = nil

        switch intent {

        case .restart(let location):

            beginSpeaking(fromLocation: location)

        case .switchChapter(let chapterID):

            guard let book = reader?.readModel else {

                finishStop()

                return
            }

            proceed(toChapterID: chapterID, in: book)

        case .halt:

            finishStop()
        }
    }

    public func speechSynthesizer(_ synthesizer: ReaderSpeechSynthesizing, didFailWith error: ReaderSpeechError) {

        switch error {

        case .voiceUnavailable:

            presentNotice(ReaderEnvironment.strings.speechVoiceUnavailable)

        case .engineRejected:

            // 正常流程不该走到这里：提交前已保证引擎处于 idle、且句文本非空。
            // 真的发生说明状态机被绕开了，此时停下来比继续推进安全。
            presentNotice(ReaderEnvironment.strings.speechFailed)
        }

        stop()
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

    func remoteCommandRequestsPlay() { resume() }

    func remoteCommandRequestsPause() { pause() }

    func remoteCommandRequestsToggle() {

        switch activity {

        case .playing: pause()

        case .paused: resume()

        case .idle: break
        }
    }

    func remoteCommandRequestsPreviousChapter() { skipToPreviousChapter() }

    func remoteCommandRequestsNextChapter() { skipToNextChapter() }
}
