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

    // MARK: - 通用状态

    /// Combine 订阅容器。基类与子类共用。
    open var cancellables = Set<AnyCancellable>()
}
