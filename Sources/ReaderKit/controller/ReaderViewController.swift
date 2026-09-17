//
//  ReaderViewController.swift
//  Reader Engine
//
//  阅读器引擎基类。承载排版、分页、翻页容器、菜单、手势、进度、书签本地模型等
//  与「读一本书」有关的全部能力，**不含任何业务概念**（不认识小说 ID、场景来源、
//  归因参数、业务 ViewModel）。
//
//  接入方式：宿主继承本类，在子类里持有自己的业务状态，并实现 Contracts/ 下的
//  各注入点协议。接入方通过继承本类接入业务。
//
//  为什么是继承 + 注入两者兼用：
//  - 继承给业务状态一个天然的家（子类持有 novelID / ViewModel 等）
//  - 注入（dataSource / delegate / config）让契约显式、基类保持封闭稳定
//  详见 .kiro/docs/reader-library-architecture.md。
//

import Combine
import UIKit

/// 阅读器引擎基类。
///
/// 当前为过渡形态：部分引擎能力仍分布在接入方子类及其扩展中，
/// 本类先承载与业务无关的**注入点**与**通用状态**，后续逐步把引擎逻辑上移。
open class ReaderViewController: ReaderScreenController {

    // MARK: - 注入点（Contracts）

    /// 书末页工厂。为 nil 时阅读器没有书末页（正文读完即到最后一页）。
    ///
    /// 强引用：工厂通常无状态，且不持有阅读器（`makeTerminalPage(reader:)` 只以参数接收），
    /// 不构成循环引用。若宿主实现需要持有阅读器，应自行用 weak。
    open var terminalPageProvider: ReaderTerminalPageProviding?

    /// 书签远端同步。为 nil 时书签只存本地、不与服务端同步。
    ///
    /// weak：宿主实现通常是持有业务 ViewModel 的适配器，可能反向持有阅读器。
    open weak var bookmarkSync: ReaderBookmarkSyncing?

    /// 书架收藏。为 nil 时阅读器无收藏能力。
    open weak var bookshelfPolicy: ReaderBookshelfManaging?

    /// 目录补齐。为 nil 时引擎按「目录已完整」处理。
    open weak var catalogueSupplier: ReaderCatalogueSupplying?

    /// 宿主动作（反馈入口、详情页跳转、导航栈清理等）。为 nil 时对应入口无响应。
    open weak var hostActionHandler: ReaderHostActionHandling?

    /// 加载失败占位视图工厂。为 nil 时加载失败不显示占位视图。
    open weak var placeholderProvider: ReaderPlaceholderProviding?

    /// 章节内容加载。为 nil 时引擎无法联网取章节（仅能读已缓存内容）。
    ///
    /// 由接入方子类自身实现，
    /// 装配时指向 self。
    open weak var chapterLoader: ReaderChapterLoading?

    // MARK: - 阅读数据

    /// 阅读对象：当前书籍的章节、分页、进度、书签等本地模型。
    open var readModel: ReaderBookModel!

    /// 本次会话已阅读的章节 ID 集合。
    ///
    /// 供「阅读达标自动加书架」按已读章节数判定，滚动模式也会写入，故不能是 private。
    open var readChapterIDs: Set<Int> = []

    // MARK: - 视图层级

    /// 阅读主视图（正文承载容器）
    open var contentView: ReaderContentView!

    /// 左侧抽屉（目录 + 书签）
    open var leftView: ReaderDrawerView!

    /// 阅读菜单（顶栏 + 底部面板）
    open var readMenu: ReaderMenu!

    // MARK: - 翻页容器

    /// 平移模式（左右翻页）的翻页容器。仅该模式下创建。
    open var pageViewController: ReaderSheetController!

    /// 滚动模式（上下滚动）的容器。仅该模式下创建。
    open var scrollController: ReaderScrollController!

    /// 非滚动模式下当前展示的正文页
    open var currentDisplayController: ReaderPageContentController?

    /// 缓存的书末页。跨翻页容器重建复用，避免重复拉取数据。
    open var cachedEndViewController: ReaderTerminalPageController?

    // MARK: - 章节解锁

    /// 章节解锁状态回调。引擎翻到锁章边界或目录未完整边界时通知它。
    ///
    /// 后续将按 `reader-library-architecture.md` 改造为异步闸门
    /// （`resume(unlocked:)` 闭包），届时本属性并入 `ReaderDelegate`。
    open weak var chapterUnlockDelegate: ReaderChapterAccessDelegate?

    // MARK: - 阅读会话钩子（供子类重写）

    /// 章节切换时的会话结算。
    ///
    /// 基类不含具体实现：会话时长统计与上报口径由接入方决定。
    /// 子类重写即可，引擎内部（如滚动模式换章）会调用本方法。
    open func submitOnChapterAlter() {}

    /// 读到书末时立即结算并重启会话计时。
    ///
    /// 语义同 `submitOnChapterAlter`，区别是由「进入书末页」触发。
    open func reportReadBookShowNow() {}

    /// 按已读章节数检查是否该自动加入书架。
    ///
    /// 用闭包而非可重写方法：接入方的实现通常位于子类的 extension 中，
    /// 而 Swift 不允许在 extension 里 override 非 @objc 方法。
    /// 阈值判定属阅读行为（归引擎），「加书架怎么做」由 `bookshelfPolicy` 完成。
    open var chapterCountShelfCheckHandler: (() -> Void)?

    /// 引擎内部统一入口：按已读章节数检查自动加书架。
    open func verifySelfGatherByChapterCount() {
        chapterCountShelfCheckHandler?()
    }

    /// 跳转到指定章节。实现在子类（`+Operation`），以闭包注入。
    open var goToChapterHandler: ((_ chapterID: NSNumber) -> Void)?

    /// 引擎内部统一入口：跳转章节。
    open func goToChapter(_ chapterID: NSNumber) {
        goToChapterHandler?(chapterID)
    }

    /// 点击菜单返回。实现在子类，以闭包注入。
    open var menuBackHandler: (() -> Void)?

    /// 引擎内部统一入口：菜单返回。
    open func handleMenuBack() {
        menuBackHandler?()
    }

    /// 加载并跳转到一个刚解锁的章节。
    ///
    /// 用闭包而非可重写方法：本项目的实现位于宿主 **extension** 中
    /// （通常在子类的 extension 里），而 Swift 不允许
    /// 在 extension 里 override 非 @objc 方法，故改为由宿主装配时注入。
    open var readUnlockedChapterHandler: ((_ chapterId: Int, _ showLoading: Bool) -> Void)?

    /// 引擎内部统一入口：请求加载一个刚解锁的章节。
    open func readUnlockedChapter(chapterId: Int, showLoading: Bool = false) {
        readUnlockedChapterHandler?(chapterId, showLoading)
    }

    // MARK: - 朗读（TTS）

    /// 朗读的宿主协调扩展点。为 nil 时朗读走库内默认行为（自管音频会话与锁屏）。
    ///
    /// weak：宿主实现通常是持有业务 ViewModel 的适配器，可能反向持有阅读器。
    public weak var speechCoordinator: ReaderSpeechCoordinating? {

        // 只在编排器已创建时转发，避免仅仅注入协调者就把编排器建起来
        didSet { createdSpeechController?.coordinator = speechCoordinator }
    }

    /// 朗读编排器。首次访问时创建。
    ///
    /// 惰性创建而非随控制器一起构造：编排器会持有 `AVSpeechSynthesizer` 并注册
    /// 三类音频中断监听，不使用朗读功能的接入方不该为此付代价。
    public var speechController: ReaderSpeechController {

        if let createdSpeechController { return createdSpeechController }

        let controller = ReaderSpeechController(reader: self)

        controller.coordinator = speechCoordinator

        createdSpeechController = controller

        return controller
    }

    /// 已创建的编排器实例。
    ///
    /// 单独存一份而不用 `lazy var`：需要「查询是否已创建」而不触发创建，
    /// `lazy` 做不到这件事。
    private var createdSpeechController: ReaderSpeechController?

    /// 朗读是否已经启用过。
    ///
    /// 供退出阅读器等收尾场景判断该不该去停朗读 —— 直接读 `speechController`
    /// 会把编排器创建出来，为了停一个从未开始的朗读而创建实例是本末倒置。
    public var isSpeechEngaged: Bool { createdSpeechController != nil }

    /// 若朗读已启用则停止。退出阅读器时调用。
    public func stopSpeechIfEngaged() {

        createdSpeechController?.stop()
    }

    /// 已创建的朗读编排器；未启用朗读时为 nil。
    ///
    /// 与 `speechController` 的区别：本属性**不会**触发创建。视图层（如滚动容器
    /// 在 cell 复用后回填高亮）需要「有就用、没有就跳过」，不能因为查询而把编排器建起来。
    public var engagedSpeechController: ReaderSpeechController? { createdSpeechController }

    /// 请求正文向后翻一页。实现由接入方注入。
    ///
    /// 为什么必须注入而不能在库内实现：左右翻页模式的整条翻页链路都在接入方那侧 ——
    /// 取下一页控制器、`setViewControllers` 动画、更新阅读记录、章节边界的网络加载，
    /// 都发生在接入方实现的 `ReaderSheetControllerDelegate` 里，库内没有等价入口。
    ///
    /// 上下滚动模式不走这里：滚动容器 `ReaderScrollController` 在库内，可自行定位。
    ///
    /// 为 nil 时左右翻页模式下的朗读不会自动翻页（朗读本身照常推进），
    /// 此时朗读位置会离开当前展示页，界面上表现为控制按钮切回「从这里开始读」。
    open var advanceToNextPageHandler: (() -> Void)?

    /// 引擎内部统一入口：请求向后翻一页。
    open func advanceToNextPage() {

        advanceToNextPageHandler?()
    }

    /// 请求正文跳转到指定章节的指定**章内绝对坐标**。实现由接入方注入。
    ///
    /// 与 `advanceToNextPageHandler` 的分工：那个只能前进一页，用于朗读的顺序跟随；
    /// 本入口是任意位置跳转，用于「后台听了几章之后回到前台，把正文对齐到朗读位置」。
    ///
    /// 接入方通常直接接到自己已有的按坐标跳章能力上。为 nil 时回前台不做对齐，
    /// 正文停在用户离开时的位置。
    open var presentPositionHandler: ((_ chapterID: NSNumber, _ location: NSInteger) -> Void)?

    /// 引擎内部统一入口：请求跳转到指定位置。
    open func presentPosition(chapterID: NSNumber, location: NSInteger) {

        presentPositionHandler?(chapterID, location)
    }

    // MARK: - 朗读控制胶囊

    /// 朗读控制胶囊。首次访问时创建。
    public var speechActionButton: ReaderSpeechActionButton {

        if let createdSpeechActionButton { return createdSpeechActionButton }

        let button = ReaderSpeechActionButton()

        createdSpeechActionButton = button

        return button
    }

    private var createdSpeechActionButton: ReaderSpeechActionButton?

    /// 把朗读控制胶囊装到阅读器上，并接好两个动作。
    ///
    /// 由接入方在视图搭建完成后调用一次。**引擎不自动装**：胶囊是否出现、
    /// 出现在哪一层属接入方的交互决策，有的接入方可能压根不提供朗读入口。
    ///
    /// 胶囊落在页脚信息栏那条带上（设计稿口径），装到 `contentView` 而不是页脚视图里 ——
    /// 页脚在左右翻页与上下滚动两种模式下分别由接入方与 `ReaderScrollController` 各自持有，
    /// 装在共同的父视图上才能一处覆盖两种模式。
    ///
    /// **调用时机要早**：正文容器与页脚都是用 `insertSubview(_:at: 0)` / `aboveSubview:`
    /// 插到 `contentView` 底部的，所以先装的胶囊自然压在它们上面；而菜单遮罩与菜单栏是
    /// 后续 append 到 `contentView` 的，会压在胶囊上面 —— 正是想要的层级。
    /// 反过来在菜单初始化之后再装，胶囊会浮在菜单遮罩之上。
    open func installSpeechActionButton() {

        let button = speechActionButton

        // contentView 在 `addSubviews()` 里创建，正常调用时机下一定有；
        // 兜底挂 view 只为不让极端时序（尚未走完 viewDidLoad）崩掉
        var container: UIView = view

        if let contentView { container = contentView }

        if button.superview !== container { container.addSubview(button) }

        button.onPrimaryAction = { [weak self] in self?.handleSpeechPrimaryAction() }

        // 返回箭头只在 .offPage 态出现，语义是「把正文跳回正在朗读的位置」
        button.onReturnAction = { [weak self] in self?.speechController.returnToSpeakingPosition() }

        reviseSpeechActionButtonAnchor()

        button.adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)

        // 默认藏着：装的时候正文往往还在加载，页脚也还不存在。
        // 由接入方在正文就位后经 `isSpeechActionButtonHidden` 放出来。
        button.isHidden = true

        reviseSpeechActionButton(animated: false)
    }

    /// 重算胶囊锚点。
    ///
    /// 锚点取自 `READER_RECT`（屏幕尺寸 + 安全区推导）而非 `view.bounds`，
    /// 所以不依赖布局时机 —— `viewDidLoad` 里就能算准，不必等 `viewDidLayoutSubviews`。
    /// 这与页脚信息栏自身的定位口径一致（见 `ReaderPageContentController`）。
    open func reviseSpeechActionButtonAnchor() {

        guard let button = createdSpeechActionButton else { return }

        let rect = READER_RECT!

        // 纵向与页脚的页码、时间电量**同一条水平中线**。
        //
        // 注意不是页脚整条带的垂直中心：带高 46，而里面那行内容是 y=16、高 22
        // （`ReaderStatusBottomView.contentTopInset` / `.contentHeight`），
        // 行中心在带顶 +27 处。按带中心（+23）摆会比页码高 4pt，肉眼看得出来没对齐。
        let bandTop = rect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT

        let rowCenterY = bandTop + ReaderStatusBottomView.contentTopInset + ReaderStatusBottomView.contentHeight / 2

        button.anchorCenter = CGPoint(x: rect.midX, y: rowCenterY)
    }

    /// 按当前朗读状态刷新胶囊。
    ///
    /// 需要调用的时机有两类：
    /// - 朗读自身状态变化（开始 / 暂停 / 继续 / 推进到下一句）—— 引擎内部已自动调
    /// - **展示位置变化**（用户手动翻页、跳章）—— 引擎感知不到接入方的翻页动作，
    ///   需要接入方在翻页链路里调一次，否则「朗读位置是否在当前页」判断会滞后，
    ///   表现为翻页后胶囊没变成「从这里开始读」
    open func reviseSpeechActionButton(animated: Bool) {

        guard let button = createdSpeechActionButton else { return }

        // 用 engagedSpeechController：未启用朗读时按 .idle 渲染即可，
        // 不该为了刷新一个按钮把整套朗读设施创建出来
        button.apply(engagedSpeechController?.actionState ?? .idle, animated: animated)
    }

    /// 通报「正文展示位置变了」。
    ///
    /// 接入方**必须**在自己的位置变更收口处调用一次（翻页、跳章、解锁后续读都算）。
    /// 引擎感知不到接入方的翻页动作，少调这一次会有两个可见后果：
    ///
    /// 1. 新页上不会出现朗读高亮 —— 高亮是写在具体某个正文视图上的属性，
    ///    换页意味着换了视图，必须重新写一遍
    /// 2. 控制胶囊的「朗读位置是否还看得见」判断滞后，翻页后仍显示「暂停」
    ///
    /// 上下滚动模式不需要接入方操心，滚动容器在库内，已自行接好。
    open func notifyDisplayedPositionAlter() {

        engagedSpeechController?.handleDisplayedPositionAlter()

        reviseSpeechActionButton(animated: true)
    }

    /// 通报「正文视图被重建了，但展示位置没变」。
    ///
    /// 接入方在切换主题、字号、行距、段间距、阅读方向之后调用 —— 这些操作都会重建正文视图，
    /// 而朗读高亮是写在具体某个 `ReaderPageView` 上的属性，新建的视图身上没有它，
    /// 表现就是「切主题后高亮消失，要等下一句开口才回来」。
    ///
    /// **不要用 `notifyDisplayedPositionAlter()` 代替**：那个会参与「这次变更是不是用户
    /// 手动挪的」判定，而换肤换字号并没有挪动位置，走那条会被误判成手动操作、
    /// 把朗读跟随挂起。
    open func notifyBodyViewRebuilt() {

        engagedSpeechController?.reviseHighlightForDisplayedPage()

        // 不带动画：视图刚重建，此刻做形变动画只会看到一次突变
        reviseSpeechActionButton(animated: false)
    }

    /// 胶囊是否隐藏。
    ///
    /// 读写都不会触发创建：未装胶囊时读到 `true`（等价于不可见），写入被忽略。
    /// 供接入方把胶囊的可见性挂到页脚那条信息带上 —— 书末页、菜单展开等页脚让位的场景，
    /// 胶囊也该一起收起。
    open var isSpeechActionButtonHidden: Bool {

        get { createdSpeechActionButton?.isHidden ?? true }

        set { createdSpeechActionButton?.isHidden = newValue }
    }

    /// 胶囊换肤。接入方在主题切换时调用。
    open func adoptSpeechActionButtonTheme(_ colors: ReaderThemeColors) {

        createdSpeechActionButton?.adoptThemeColors(colors)
    }

    /// 点击胶囊主区域。
    private func handleSpeechPrimaryAction() {

        let controller = speechController

        switch controller.actionState {

        case .idle, .offPage:

            // .offPage 下主区域的语义是「从这里开始读」，即放弃原朗读位置、
            // 改从当前展示页重新开始；想回到原位置走返回箭头
            controller.startFromCurrentPage()

        case .playing:

            controller.pause()

        case .paused:

            controller.resume()
        }
    }

    // MARK: - 通用状态

    /// Combine 订阅容器。基类与子类共用。
    open var cancellables = Set<AnyCancellable>()
}
