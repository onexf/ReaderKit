//
//  ReaderScrollController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/14.
//

import UIKit

open class ReaderScrollController: ReaderScreenController, UITableViewDelegate, UITableViewDataSource {

    /// 当前主控制器
    /// 阅读器控制器。
    ///
    /// 类型为引擎基类而非具体子类：本处理器只用到 readModel / readMenu /
    /// readChapterIDs / chapterLoader / chapterUnlockDelegate 等引擎成员，
    /// 以及基类声明的会话钩子，不需要感知宿主子类的业务字段。
    open weak var vc: ReaderViewController!
    
    /// 顶部状态栏
    private var topView: ReaderStatusTopView!
    
    /// 阅读视图
    private var tableView: ReaderTableView!
    
    /// 底部状态栏
    private var bottomView: ReaderStatusBottomView!
    
    /// 当前阅读章节ID列表(只会存放本次阅读的列表) ⚠️ 仅主线程访问
    private var chapterIDs: [NSNumber] = []
    
    /// 当前正在加载的章节 ⚠️ 仅主线程访问
    private var loadChapterIDs: [NSNumber] = []
    
    /// 当前阅读的章节列表,通过已有的章节ID列表,来获取章节模型。⚠️ 仅主线程访问
    private var chapterModels: [String: ReaderChapterModel] = [:]
    
    /// 记录滚动坐标
    private var scrollPoint: CGPoint!
    
    /// 是否为向上滚动
    private var isScrollUp: Bool = true
    
    /// 标记用户是否已经开始主动滚动（防止初始加载时误触发）
    private var hasUserScrolled: Bool = false
    
    /// 标记是否正在执行章节定位（防止预加载干扰定位）
    private var isPositioningAfterReload: Bool = false

    /// 上次触发锁定章节回调的时间（用于节流，防止短时间内重复弹窗）
    private var lastLockedChapterCallbackTime: TimeInterval = 0
    
    /// 上次检测到的章节ID（章节切换时触发一次章节级记录，避免滚动时重复）
    private var lastReportedChapterID: Int?
    
    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // 阅读记录开始阅读
        reloadChapter()
    }
    
    /// 重新加载章节
    open func reloadChapter() {
        // 清空章节列表
        chapterIDs.removeAll()
        loadChapterIDs.removeAll()
        
        // 重置用户滚动标志（防止初始加载时误触发）
        hasUserScrolled = false
        
        // 标记正在定位，阻止预加载干扰
        isPositioningAfterReload = true
        
        // 清空章节模型缓存
        chapterModels.removeAll()
        
        // 记录目标章节ID（用于定位时查找正确的 section）
        let targetChapterID = vc.readModel.recordModel.chapterModel.id!
        
        // 添加当前章节
        chapterIDs.append(targetChapterID)
        
        // 刷新表格并立即完成 layout
        tableView.reloadData()
        tableView.layoutIfNeeded()
        
        // 定位到目标位置
        let targetSection = chapterIDs.firstIndex(of: targetChapterID) ?? 0
        let page = vc.readModel.recordModel.page.intValue
        let offset = vc.readModel.recordModel.scrollOffsetInPage
        let numberOfRows = tableView.numberOfRows(inSection: targetSection)
        
        if page < numberOfRows {
            let targetIndexPath = IndexPath(row: page, section: targetSection)
            let cellRect = tableView.rectForRow(at: targetIndexPath)
            var targetOffsetY = cellRect.origin.y + offset
            
            // Clamp to valid range
            let maxOffsetY = max(0, tableView.contentSize.height - tableView.bounds.height)
            targetOffsetY = min(targetOffsetY, maxOffsetY)
            targetOffsetY = max(0, targetOffsetY)
            
            tableView.contentOffset = CGPoint(x: 0, y: targetOffsetY)
        } else {
            tableView.contentOffset = .zero
        }
        
        // 定位完成，允许预加载
        isPositioningAfterReload = false
        
        // 首屏页码：上面是直接赋 contentOffset，reloadData 后首次赋值可能早于 layout 完成，
        // 这里清掉判重缓存显式补一次
        displayedPageIndexPath = nil
        revisePageNumber()
        
        // 定位完成后触发预加载上下章节
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let chapterModel = self.chapterModels[targetChapterID.stringValue] {
                self.preloadingPrior(chapterModel)
                self.preloadingFollowing(chapterModel)
            }
        }
    }
    
    /// 换肤刷新：保持当前滚动位置，重新分页后无缝替换内容
    open func reloadForThemeAlter() {
        // 记录当前滚动位置
        let currentOffset = tableView.contentOffset
        
        // 清空章节模型缓存（强制重新分页，因为文字颜色变了）
        chapterModels.removeAll()
        
        // 更新背景色
        view.backgroundColor = .clear
        tableView.backgroundColor = .clear
        
        // 更新顶部状态栏与底部信息栏颜色
        topView.reviseColors()
        bottomView.reviseColors()
        
        // 刷新表格（会触发 cellForRowAt 重新获取带新颜色的 attributedString）
        tableView.reloadData()
        
        // 恢复滚动位置
        tableView.layoutIfNeeded()
        tableView.contentOffset = currentOffset
        
        // 换肤会清缓存重新分页，本章总页数可能变，页码要重算（清掉判重缓存强制下发）
        displayedPageIndexPath = nil
        revisePageNumber()
    }
    
    /// Scroll to the very bottom (END recommend area) without animation
    open func scrollToBase() {
        tableView.layoutIfNeeded()
        let maxOffset = max(0, tableView.contentSize.height - tableView.bounds.height)
        tableView.contentOffset = CGPoint(x: 0, y: maxOffset)
    }
    
    
    // MARK: - 朗读协同
    
    /// 滚动到指定章节的指定页，供朗读跟随使用。
    ///
    /// 与左右翻页模式不同，滚动容器在库内，可以直接定位，不需要接入方注入翻页能力。
    ///
    /// - Parameters:
    ///   - chapterID: 目标章节
    ///   - page: 章内页码
    open func scrollToSpeechPage(chapterID: NSNumber?, page: Int) {
        
        guard let chapterID,
              let section = chapterIDs.firstIndex(of: chapterID) else { return }
        
        // 目标页尚未在数据源里（章节还没加载完）时不要硬滚，
        // scrollToRow 传越界 indexPath 会抛异常
        guard let chapterModel = resolveChapterModel(chapterID: chapterID),
              page >= 0,
              page < chapterModel.pageModels.count else { return }
        
        tableView.scrollToRow(at: IndexPath(row: page, section: section), at: .top, animated: true)
    }
    
    /// 刷新全部可见页的朗读高亮。
    open func reviseSpeechHighlight() {
        
        for cell in tableView.visibleCells {
            
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            
            reviseSpeechHighlight(for: cell, at: indexPath)
        }
    }
    
    /// 清除全部可见页的朗读高亮。
    open func clearSpeechHighlight() {
        
        for cell in tableView.visibleCells {
            
            (cell as? ReaderPageCell)?.renderingPageView?.speechHighlightRange = nil
        }
    }
    
    /// 按当前朗读位置刷新单个 cell 的高亮。
    ///
    /// 用 `engagedSpeechController` 而非 `speechController`：这条路径会在每次
    /// cell 即将显示时跑一遍，用后者会让「从未使用朗读的用户」也把编排器创建出来。
    private func reviseSpeechHighlight(for cell: UITableViewCell, at indexPath: IndexPath) {
        
        guard let pageCell = cell as? ReaderPageCell,
              let pageView = pageCell.renderingPageView else { return }
        
        guard let controller = vc?.engagedSpeechController else {
            
            pageView.speechHighlightRange = nil
            
            return
        }
        
        guard indexPath.section < chapterIDs.count,
              let pageModel = pageCell.pageModel else {
            
            pageView.speechHighlightRange = nil
            
            return
        }
        
        // 必须带上章节标识：不同章节的页范围都从 0 开始，只比页内范围会把
        // 另一章的同位置段落也点亮
        pageView.speechHighlightRange = controller.highlightRange(inPage: pageModel,
                                                                 chapterID: chapterIDs[indexPath.section])
    }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        // 阅读使用范围
        let readRect = READER_RECT!
        
        // 顶部状态栏
        topView = ReaderStatusTopView()
        topView.storyName.text = vc.readModel.storyName
        topView.chapterName.text = vc.readModel.recordModel.chapterModel.name
        view.addSubview(topView)
        topView.frame = CGRect(x: readRect.minX, y: readRect.minY, width: readRect.width, height: READER_STATUS_TOP_VIEW_HEIGHT)
        
        // 阅读视图 - 底部让出页脚信息栏（时间 + 电池）所占的高度
        tableView = ReaderTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.separatorStyle = .none
        // 防止误触状态栏将阅读记录重置为0
        tableView.scrollsToTop = false
        view.addSubview(tableView)
        // 时间与电池已下移到页脚，滑动模式下正文到页脚信息栏上方为止，不再延伸到屏幕物理底部
        tableView.frame = READER_VIEW_RECT
        
        // 移除自动内边距
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
        
        // 添加底部内边距，让内容不会紧贴屏幕底部
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        
        // 底部信息栏（页码 + 时间 + 电池）
        bottomView = ReaderStatusBottomView()
        // 滚动模式的页码挂在固定页脚上，由本控制器随滚动下发；翻页模式则由每页正文控制器自己画
        bottomView.showsPageNumber = true
        view.addSubview(bottomView)
        bottomView.frame = CGRect(x: readRect.minX, y: readRect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT, width: readRect.width, height: READER_STATUS_BOTTOM_VIEW_HEIGHT)
    }
    
    // MARK: - 页码
    
    /// 页码当前对应的页，用于跳过无变化的重复计算
    private var displayedPageIndexPath: IndexPath?
    
    /// 刷新页脚左侧页码。
    ///
    /// 口径对齐 Android 侧实现（`SNContentTextView.scroll()` + `SNPageView.setProgress()`）：
    ///
    /// - 页码取「**屏幕最顶端那一行像素所属的页**」。安卓那边是 `pageOffset` 滚过整页高度才
    ///   `moveToNext()`，等价于本实现里取 `contentOffset.y` 命中的那个 cell（tableView 一 cell
    ///   一页）。屏幕上通常能同时看到两页的内容（上一页尾 + 下一页头），显示的是**上面那一页**。
    /// - 章内编号，`当前页/本章总页数`，切章重置、跨章不连续（安卓 `moveToNextChapter` 里
    ///   `durChapterPos = 0`）。
    /// - 书末推荐区不显示页码（安卓用 `isInvisible` 占位隐藏）。
    ///
    /// 与安卓的一处**有意不同**：安卓分页是异步流式的，总页数没算完时分母显示 `~N` / `-`；
    /// iOS 侧 `ReaderTypesetter.pageing` 是同步分页，cell 能渲染就意味着页数已确定，
    /// 所以不需要这两种占位态。
    ///
    /// 另一处**有意不同**：滚到内容末尾时改取「可见的最后一行」。取顶端像素所属页有个
    /// 到不了的边界——末页通常不足一屏，滚到底时它虽已完整呈现，其上方仍留着前一页的尾巴，
    /// 顶端像素落在前一页，于是页码永远停在倒数第二页（正文已显示到 END、页码却是 14/15）。
    /// 中途章节不受影响：继续下滚时该页自然会成为顶端页。
    private func revisePageNumber() {
        
        guard let bottomView else { return }
        
        // 顶端那一点命中的 cell 即当前页
        let topPoint = CGPoint(x: 0, y: tableView.contentOffset.y + 0.5)
        
        // 是否已滚到内容末尾（含内容不足一屏的情况）
        let maxOffsetY = max(0, tableView.contentSize.height - tableView.bounds.height)
        let isAtContentEnd = tableView.contentOffset.y >= maxOffsetY - 1
        
        let indexPath: IndexPath
        
        if isAtContentEnd, let lastVisible = tableView.indexPathsForVisibleRows?.last {
            
            // 滚到底：用户看到的是最后一页，页码跟上
            indexPath = lastVisible
            
        } else if let topIndexPath = tableView.indexPathForRow(at: topPoint) {
            
            indexPath = topIndexPath
            
        } else {
            
            // 命中不到 cell 只剩过冲回弹一种情况（下拉刷新、滚到底回弹，contentOffset 越界）→
            // 保持上一次的值，否则页码会在回弹的几帧里闪一下消失。安卓那边是把 pageOffset
            // 钳回边界、当前页状态不变，效果等价
            return
        }
        
        // 顶端页没变就不用再拼字符串（安卓侧同样是「跨页边界才更新」）
        guard indexPath != displayedPageIndexPath else { return }
        
        displayedPageIndexPath = indexPath
        
        guard indexPath.section < chapterIDs.count,
              let chapterModel = resolveChapterModel(chapterID: chapterIDs[indexPath.section]) else {
            
            bottomView.revisePageNumber(nil)
            
            return
        }
        
        // 书籍首页不显示页码，与翻页模式 ReaderPageContentController 的处理一致
        if indexPath.row < chapterModel.pageModels.count,
           chapterModel.pageModels[indexPath.row].isHomePage {
            
            bottomView.revisePageNumber(nil)
            
            return
        }
        
        bottomView.revisePageNumber("\(indexPath.row + 1)/\(chapterModel.pageCount.intValue)")
    }
    
    // MARK: UITableViewDelegate,UITableViewDataSource
    
    open func numberOfSections(in tableView: UITableView) -> Int {
        
        return chapterIDs.count
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        guard section < chapterIDs.count else { return 0 }
        
        let chapterID = chapterIDs[section]
        
        // 获取章节内容模型
        guard let chapterModel = resolveChapterModel(chapterID: chapterID) else {
            return 0
        }
        
        // 有数据则返回页数
        return chapterModel.pageCount.intValue
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard indexPath.section < chapterIDs.count else {
            return UITableViewCell()
        }
        
        let chapterID = chapterIDs[indexPath.section]
        
        guard let chapterModel = resolveChapterModel(chapterID: chapterID),
              indexPath.row < chapterModel.pageModels.count else {
            return UITableViewCell()
        }
        
        let pageModel = chapterModel.pageModels[indexPath.row]
        
        // 是否为书籍首页
        if pageModel.isHomePage {
            
            let cell = ReaderBookCoverCell.cell(tableView)
            
            cell.homeView.readModel = vc.readModel
            
            return cell
            
        }else{
            
            let cell = ReaderPageCell.cell(tableView)
            
            cell.pageModel = pageModel
            
            return cell
        }
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        guard indexPath.section < chapterIDs.count else {
            return 0
        }
        
        let chapterID = chapterIDs[indexPath.section]
        
        guard let chapterModel = resolveChapterModel(chapterID: chapterID),
              indexPath.row < chapterModel.pageModels.count else {
            return 0
        }
        
        return chapterModel.pageModels[indexPath.row].cellHeight
    }
    
    open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return READER_SPACE_MIN_HEIGHT
    }
    
    open func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        return nil
    }
    
    open func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return READER_SPACE_MIN_HEIGHT
    }
    
    open func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }
    
    open func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        
        guard section < chapterIDs.count else { return }
        
        // Skip preloading during chapter repositioning to avoid interfering with scroll position
        guard !isPositioningAfterReload else { return }
        
        let key = chapterIDs[section].stringValue
        guard let chapterModel = chapterModels[key] else { return }
        
        // 预加载上一章
        preloadingPrior(chapterModel)
        
        // 预加载下一章
        preloadingFollowing(chapterModel)
    }
    
    /// 书籍首页将要出现
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        // 朗读高亮的回填必须在下面那条 row != 0 的提前返回之前做。
        //
        // 起因是 ReaderPageView 在换 pageModel 时会主动清掉高亮（cell 复用的必要处理），
        // 于是「滚出屏幕再滚回来」的页会丢失高亮。这里在页重新可见的时机补设回去。
        reviseSpeechHighlight(for: cell, at: indexPath)
        
        if indexPath.row != 0 { return }
        
        guard indexPath.section < chapterIDs.count else { return }
        
        let chapterID = chapterIDs[indexPath.section]
        
        guard let chapterModel = resolveChapterModel(chapterID: chapterID),
              indexPath.row < chapterModel.pageModels.count else {
            return
        }
        
        let pageModel = chapterModel.pageModels[indexPath.row]
        
        if pageModel.isHomePage {
            
            topView?.isHidden = true
        }
    }
    
    /// 书籍首页消失
    open func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        if indexPath.row != 0 { return }
        
        guard indexPath.section < chapterIDs.count else { return }
        
        let chapterID = chapterIDs[indexPath.section]
        
        guard let chapterModel = resolveChapterModel(chapterID: chapterID),
              indexPath.row < chapterModel.pageModels.count else {
            return
        }
        
        let pageModel = chapterModel.pageModels[indexPath.row]
        
        if pageModel.isHomePage {
            
            topView?.isHidden = false
        }
    }
    
    
    // MARK: 监控滚动以及拖拽
    
    // 开始拖拽
    open func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
 
        // 隐藏菜单
        vc.readMenu.presentDropdown(isShow: false)
        
        // 重置属性
        isScrollUp = true
        scrollPoint = CGPoint.zero
        
        // 标记用户已开始主动滚动
        hasUserScrolled = true
    }
    
    // 结束拖拽
    open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        
        // 更新阅读记录
        reviseReadEntry(isRollingUp: isScrollUp)
    }
    
    // 开始减速
    open func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        
        // 更新阅读记录
        reviseReadEntry(isRollingUp: isScrollUp)
    }
    
    // 结束减速
    open func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        
        // 更新阅读记录
        reviseReadEntry(isRollingUp: isScrollUp)
    }
    
    /// 系统功能，点击状态栏自动滚动到顶部；更新阅读章节
    open func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        reviseReadEntry(isRollingUp: true)
    }
    
    // 正在滚动
    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        // 页码必须在下面那道 scrollPoint 守卫**之前**刷新：scrollPoint 只在用户首次拖拽
        // （scrollViewWillBeginDragging）时才被赋值，程序化改 contentOffset（定位、换肤恢复、
        // 滚到书末）都会被那道守卫直接拦掉，页码就会停在旧值上。
        revisePageNumber()
        
        if scrollPoint == nil { return }
        
        let point = scrollView.panGestureRecognizer.translation(in: scrollView)
        
        if point.y < scrollPoint.y { // 上滚
            
            isScrollUp = true
            
        }else if point.y > scrollPoint.y { // 下滚
            
            isScrollUp = false
            
        }else{ }
        
        // 记录坐标
        scrollPoint = point
        
        // 实时检测是否接近底部锁定章节（滚动过程中即触发，更灵敏）
        if hasUserScrolled && isScrollUp {
            verifyIfReachedBase(scrollView)
        }
        
        // 滚动到边界时重新触发章节预加载（处理加载失败后重试）
        if hasUserScrolled {
            reattemptPreloadingAtBoundaryIfRequired(scrollView)
        }
    }
    
    /// 滚动到顶部/底部边界时，重新触发章节预加载（处理加载失败后重试场景）
    private func reattemptPreloadingAtBoundaryIfRequired(_ scrollView: UIScrollView) {
        guard !chapterIDs.isEmpty else { return }
        
        let contentOffsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.frame.size.height
        
        // 向下滚动（查看前面内容）且接近顶部时，重试加载上一章
        if !isScrollUp && contentOffsetY < 50 {
            let firstChapterID = chapterIDs.first!
            if let chapterModel = chapterModels[firstChapterID.stringValue] {
                preloadingPrior(chapterModel)
            }
        }
        
        // 向上滚动（查看后面内容）且接近底部时，重试加载下一章
        if isScrollUp && (contentOffsetY + scrollViewHeight) > (contentHeight - 50) {
            let lastChapterID = chapterIDs.last!
            if let chapterModel = chapterModels[lastChapterID.stringValue] {
                preloadingFollowing(chapterModel)
            }
        }
    }
    
    /// 检查是否滚动到底部，触发解锁回调
    private func verifyIfReachedBase(_ scrollView: UIScrollView) {
        // 只在用户主动滚动且向上滚动（内容向上=手指向上=看更多内容）时检查
        guard hasUserScrolled && isScrollUp else { return }
        
        // 节流：2秒内最多触发一次，防止短时间内重复弹窗
        let now = Date().timeIntervalSince1970
        guard now - lastLockedChapterCallbackTime >= 2.0 else { return }
        
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.frame.size.height
        let contentOffsetY = scrollView.contentOffset.y
        let bottomInset = scrollView.contentInset.bottom
        
        let maxOffsetY = contentHeight - scrollViewHeight + bottomInset
        let distanceFromBottom = maxOffsetY - contentOffsetY
        
        // 当距离底部小于50点时开始检测
        guard distanceFromBottom < -10 else { return }
        
        // 直接通过可见cell判断是否已到达最后加载章节的末尾区域
        // 不再依赖 recordModel.isLastPage（它在滚动结束后才更新，导致延迟）
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              let lastVisibleIndexPath = visibleIndexPaths.last else { return }
        
        let lastSection = lastVisibleIndexPath.section
        guard lastSection < chapterIDs.count else { return }
        
        let lastVisibleChapterID = chapterIDs[lastSection]
        guard let lastVisibleChapterModel = resolveChapterModel(chapterID: lastVisibleChapterID) else { return }
        
        // 必须是该章节最后一页才触发
        let totalPages = lastVisibleChapterModel.pageCount.intValue
        guard lastVisibleIndexPath.row >= totalPages - 1 else { return }
        
        // 权威解析下一章（不信任缓存的 nextChapterID；边界未加载完时触发补目录）
        guard let nextChapterID = vc.readModel.resolvedFollowingChapterID(forChapterID: lastVisibleChapterID) else {
            // 已加载边界：目录未完整则触发补目录，补齐后可继续向下滚动
            if !vc.readModel.isChapterListComplete {
                vc.chapterUnlockDelegate?.readControllerDidReachUnloadedBoundary(vc)
            }
            return
        }
        guard let nextChapterListModel = vc.readModel.chapterListModels.first(where: { $0.id == nextChapterID }) else { return }
        
        if nextChapterListModel.isLocked {
            // 下一章仍然锁定，走正常解锁流程
            lastLockedChapterCallbackTime = now
            
            let nextChapterNumber = (nextChapterListModel.priority?.intValue ?? 0) + 1
            
            self.vc.chapterUnlockDelegate?.readController(
                self.vc,
                didAttemptToLoadLockedChapter: nextChapterID.intValue,
                chapterName: nextChapterListModel.name ?? "",
                chapterNumber: nextChapterNumber
            )
        } else if !chapterIDs.contains(nextChapterID) && !loadChapterIDs.contains(nextChapterID) {
            // Compensation: the chapter is no longer locked (e.g. subscription arrived while
            // the unlock notification was missed), but its content hasn't been loaded yet.
            // Proactively load it so the user can continue scrolling.
            lastLockedChapterCallbackTime = now
            // log("🔓 [补偿] 下一章已解锁但未加载，主动加载 chapterId:\(nextChapterID)")
            
            // 不要写 alreadyLock=1：命中此分支说明下一章在当前权益下未锁定（isLocked==false，多为 VIP 生效），
            // 只是内容未加载需补偿。VIP 是动态权益，绝不修改章节锁定状态；若写 1 会被当金币买断落盘，
            // VIP 过期后该章仍判未锁。直接补偿加载即可。
            self.vc.readUnlockedChapter(chapterId: nextChapterID.intValue, showLoading: false)
        }
    }
    
    // MARK: 阅读记录以及进度
    
    /// 更新阅读记录(滚动模式) isRollingUp:是否为往上滚动
    /// ⚠️ 全部在主线程执行，避免多线程竞态导致 EXC_BAD_ACCESS
    private func reviseReadEntry(isRollingUp: Bool) {
        
        let indexPaths = tableView.indexPathsForVisibleRows
        
        guard let indexPaths = indexPaths,
              !indexPaths.isEmpty else {
            return
        }
        
        // 章节切换检测：向上滚动取最后可见，向下滚动取第一可见
        let detectIndexPath: IndexPath = isRollingUp ? indexPaths.last! : indexPaths.first!
        
        guard detectIndexPath.section < chapterIDs.count else { return }
        
        let chapterID = chapterIDs[detectIndexPath.section]
        
        guard let chapterModel = resolveChapterModel(chapterID: chapterID) else {
            return
        }
        
        // 检测章节是否切换（用于自动加书架）
        let oldChapterID = vc.readModel.recordModel.chapterModel?.id.intValue
        let newChapterID = chapterModel.id.intValue
        
        // 章节切换时，先上报旧章节数据（在 recordModel 被更新之前）
        if oldChapterID != newChapterID, lastReportedChapterID != oldChapterID {
            lastReportedChapterID = oldChapterID
            vc.submitOnChapterAlter()
        }
        
        // 阅读记录保存
        let firstIndexPath = indexPaths.first!
        let lastIndexPath = indexPaths.last!
        
        let recordIndexPath: IndexPath
        let recordOffset: CGFloat
        
        if firstIndexPath.section != lastIndexPath.section {
            // 跨章节：保存最新章节的第一个可见 page + offset 0
            let latestSection = lastIndexPath.section
            recordIndexPath = indexPaths.first(where: { $0.section == latestSection }) ?? lastIndexPath
            recordOffset = 0
        } else {
            // 单章节：用顶部第一个可见 cell + 精确 offset
            recordIndexPath = firstIndexPath
            let cellRect = tableView.rectForRow(at: firstIndexPath)
            recordOffset = max(0, min(tableView.contentOffset.y - cellRect.origin.y, cellRect.height - 1))
        }
        
        let recordSection = recordIndexPath.section
        if recordSection < chapterIDs.count {
            let recordChapterID = chapterIDs[recordSection]
            if let recordChapterModel = resolveChapterModel(chapterID: recordChapterID) {
                vc.readModel.recordModel.modify(chapterModel: recordChapterModel, page: recordIndexPath.row, isSave: false)
                vc.readModel.recordModel.scrollOffsetInPage = recordOffset
                vc.readModel.recordModel.save()
            }
        }
        
        READER_RECORD_CURRENT_CHAPTER_LOCATION = vc.readModel.recordModel.locationFirst
        
        // 如果章节切换了，记录新章节并检查条件
        if oldChapterID != newChapterID {
            // 切换章节时重置标志位
            hasUserScrolled = false
            
            vc.readChapterIDs.insert(newChapterID)
            // log("📚 [滚动模式] 切换章节 - 新章节ID: \(newChapterID), 本次会话已读章节: \(vc.readChapterIDs.count)")
            vc.verifySelfGatherByChapterCount()
        }
        
        // 顶部状态栏显示屏幕顶部可见章节名
        if let firstIndexPath = indexPaths.first,
           firstIndexPath.section < chapterIDs.count,
           let topChapterModel = resolveChapterModel(chapterID: chapterIDs[firstIndexPath.section]) {
            topView.chapterName.text = topChapterModel.name
        }
        
    }
    
    // MARK: 获得阅读数据
    
    /// 获取章节内容模型 (仅主线程调用)
    private func resolveChapterModel(chapterID: NSNumber) ->ReaderChapterModel? {
        
        let key = chapterID.stringValue
        
        // 内存中已有，直接返回
        if let chapterModel = chapterModels[key] {
            return chapterModel
        }
        
        // 内存中不存在，尝试从磁盘/解析加载
        let isExist = ReaderChapterModel.isExist(storyID: vc.readModel.storyID, chapterID: chapterID)
        
        if isExist || vc.readModel.storySourceType == .local {
            
            var chapterModel: ReaderChapterModel?
            
            if !isExist {
                chapterModel = ReaderFastTextFileParser.parser(readModel: vc.readModel, chapterID: chapterID)
            }else{
                chapterModel = ReaderChapterModel.model(storyID: vc.readModel.storyID, chapterID: chapterID)
                
                // 更新章节链接关系（防止使用旧的缓存数据）
                if let model = chapterModel,
                   let chapterIndex = vc.readModel.chapterListModels.firstIndex(where: { $0.id == chapterID }) {
                    if chapterIndex > 0 {
                        model.previousChapterID = vc.readModel.chapterListModels[chapterIndex - 1].id
                    } else {
                        model.previousChapterID = READER_NO_MORE_CHAPTER
                    }
                    if chapterIndex < vc.readModel.chapterListModels.count - 1 {
                        model.nextChapterID = vc.readModel.chapterListModels[chapterIndex + 1].id
                    } else {
                        model.nextChapterID = READER_NO_MORE_CHAPTER
                    }
                    model.save()
                }
            }
            
            if let model = chapterModel {
                chapterModels[key] = model
            }
            return chapterModel
            
        }else{ // 网络章节 - 异步加载，返回nil
            
            if !loadChapterIDs.contains(chapterID) {
                loadChapterIDs.append(chapterID)
                
                let dispatched = vc.chapterLoader?.loadChapter(chapterId: chapterID.intValue, successBlock: { [weak self] tempChapterModel in
                    // 回到主线程更新所有数据结构
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.chapterModels[chapterID.stringValue] = tempChapterModel
                        if let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) {
                            self.loadChapterIDs.remove(at: loadIndex)
                        }
                        self.tableView.reloadData()
                    }
                }, failureBlock: { [weak self] error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) {
                            self.loadChapterIDs.remove(at: loadIndex)
                        }
                    }
                })
                
                // If throttled, remove from loading list so it can be retried after cooldown
                if dispatched != true {
                    if let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) {
                        self.loadChapterIDs.remove(at: loadIndex)
                    }
                }
            }
        }
        
        return nil
    }
    
    
    // MARK: 预加载数据
    
    /// 预加载上一个章节
    private func preloadingPrior(_ chapterModel: ReaderChapterModel!) {
   
        let chapterID = chapterModel.previousChapterID
        
        if (chapterModel == nil) || chapterModel.isFirstChapter || loadChapterIDs.contains(chapterID!) || chapterIDs.contains(chapterID!) { return }
        
        // 加入加载列表（主线程）
        loadChapterIDs.append(chapterID!)
        
        let storyID = chapterModel.storyID
        let readModel = vc.readModel!
        let chapterListModels = readModel.chapterListModels!
        let isLocal = readModel.storySourceType == .local
        let currentChapterModelId = chapterModel.id!
        
        // 磁盘I/O放后台线程
        // 注意：reviseFont() 内部依赖 READER_VIEW_RECT → ReaderScreenMetrics.safeAreaTop → UIWindow，必须在主线程执行。
        // 这里用 isUpdateFont: false 避免在后台触碰 UI API，主线程回调里再补 reviseFont()。
        DispatchQueue.global().async { [weak self] () in
            
            let isExist = ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID)
            
            if isExist || isLocal {
                
                var tempChapterModel: ReaderChapterModel!
                
                if !isExist {
                    tempChapterModel = ReaderFastTextFileParser.parser(readModel: readModel, chapterID: chapterID, isUpdateFont: false)
                }else{
                    tempChapterModel = ReaderChapterModel.model(storyID: storyID, chapterID: chapterID!, isUpdateFont: false)
                    
                    if let model = tempChapterModel,
                       let chapterIndex = chapterListModels.firstIndex(where: { $0.id == chapterID }) {
                        if chapterIndex > 0 {
                            model.previousChapterID = chapterListModels[chapterIndex - 1].id
                        } else {
                            model.previousChapterID = READER_NO_MORE_CHAPTER
                        }
                        if chapterIndex < chapterListModels.count - 1 {
                            model.nextChapterID = chapterListModels[chapterIndex + 1].id
                        } else {
                            model.nextChapterID = READER_NO_MORE_CHAPTER
                        }
                        model.save()
                    }
                }
            
                // 回到主线程更新所有数据结构
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // 主线程补做字体/分页（依赖 UIWindow safeArea）
                    tempChapterModel?.reviseFont()
                    
                    self.chapterModels[chapterID!.stringValue] = tempChapterModel
                    
                    guard let currentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId),
                          let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID!) else {
                        return
                    }
                    
                    // Record the current visible position relative to the current chapter's first visible cell
                    let currentOffset = self.tableView.contentOffset.y
                    let currentFirstCellRect = self.tableView.rectForRow(at: IndexPath(row: 0, section: currentIndex))
                    let relativeOffset = currentOffset - currentFirstCellRect.origin.y
                    
                    let previousIndex = max(0, currentIndex - 1)
                    self.chapterIDs.insert(chapterID!, at: previousIndex)
                    self.loadChapterIDs.remove(at: loadIndex)
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                    
                    // After reloadData, the current chapter moved to a new section index
                    // Recalculate its position and restore the relative offset
                    let newCurrentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId) ?? (previousIndex + 1)
                    let newFirstCellRect = self.tableView.rectForRow(at: IndexPath(row: 0, section: newCurrentIndex))
                    self.tableView.contentOffset = CGPoint(x: 0, y: newFirstCellRect.origin.y + relativeOffset)
                }
                
            }else{ // 加载网络章节数据
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // 检查上一章是否锁定（付费墙已移除，恒为 false）
                    if let previousChapterListModel = self.vc.readModel.chapterListModels.first(where: { $0.id == chapterID }) {
                        if previousChapterListModel.isLocked {
                            if let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID!) {
                                self.loadChapterIDs.remove(at: loadIndex)
                            }
                            return
                        }
                    }
                    
                    guard let id = chapterID?.intValue else { return }
                    let dispatched = self.vc.chapterLoader?.loadChapter(chapterId: id, successBlock: { [weak self] tempChapterModel in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            self.chapterModels[chapterID!.stringValue] = tempChapterModel
                            
                            guard let currentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId),
                                  let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID!) else {
                                return
                            }
                            
                            // Record the current visible position relative to the current chapter's first visible cell
                            let currentOffset = self.tableView.contentOffset.y
                            let currentFirstCellRect = self.tableView.rectForRow(at: IndexPath(row: 0, section: currentIndex))
                            let relativeOffset = currentOffset - currentFirstCellRect.origin.y
                            
                            let previousIndex = max(0, currentIndex - 1)
                            self.chapterIDs.insert(chapterID!, at: previousIndex)
                            self.loadChapterIDs.remove(at: loadIndex)
                            self.tableView.reloadData()
                            self.tableView.layoutIfNeeded()
                            
                            // After reloadData, the current chapter moved to a new section index
                            let newCurrentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId) ?? (previousIndex + 1)
                            let newFirstCellRect = self.tableView.rectForRow(at: IndexPath(row: 0, section: newCurrentIndex))
                            self.tableView.contentOffset = CGPoint(x: 0, y: newFirstCellRect.origin.y + relativeOffset)
                        }
                    }, failureBlock: { [weak self] error in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self,
                                  let chapterID = chapterID,
                                  let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) else {
                                return
                            }
                            self.loadChapterIDs.remove(at: loadIndex)
                            ReaderEnvironment.presentErrorNotice(self.view, error.localizedDescription)
                        }
                    })
                    
                    // If throttled, remove from loading list so it can be retried after cooldown
                    if dispatched != true, let chapterID = chapterID,
                       let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) {
                        self.loadChapterIDs.remove(at: loadIndex)
                    }
                }
            }
        }
    }
    
    /// 预加载下一个章节
    private func preloadingFollowing(_ chapterModel: ReaderChapterModel!) {
        
        let chapterID = chapterModel.nextChapterID
        
        if (chapterModel == nil) || chapterModel.isLastChapter || loadChapterIDs.contains(chapterID!) || chapterIDs.contains(chapterID!) { return }
        
        // 加入加载列表（主线程）
        loadChapterIDs.append(chapterID!)
        
        let storyID = chapterModel.storyID
        let readModel = vc.readModel!
        let chapterListModels = readModel.chapterListModels!
        let isLocal = readModel.storySourceType == .local
        let currentChapterModelId = chapterModel.id!
        
        // 磁盘I/O放后台线程
        // 注意：reviseFont() 内部依赖 READER_VIEW_RECT → ReaderScreenMetrics.safeAreaTop → UIWindow，必须在主线程执行。
        // 这里用 isUpdateFont: false 避免在后台触碰 UI API，主线程回调里再补 reviseFont()。
        DispatchQueue.global().async { [weak self] () in
            
            let isExist = ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID)
            
            if isExist || isLocal {
                
                var tempChapterModel: ReaderChapterModel!
                
                if !isExist {
                    tempChapterModel = ReaderFastTextFileParser.parser(readModel: readModel, chapterID: chapterID, isUpdateFont: false)
                }else{
                    tempChapterModel = ReaderChapterModel.model(storyID: storyID, chapterID: chapterID!, isUpdateFont: false)
                    
                    if let model = tempChapterModel,
                       let chapterIndex = chapterListModels.firstIndex(where: { $0.id == chapterID }) {
                        if chapterIndex > 0 {
                            model.previousChapterID = chapterListModels[chapterIndex - 1].id
                        } else {
                            model.previousChapterID = READER_NO_MORE_CHAPTER
                        }
                        if chapterIndex < chapterListModels.count - 1 {
                            model.nextChapterID = chapterListModels[chapterIndex + 1].id
                        } else {
                            model.nextChapterID = READER_NO_MORE_CHAPTER
                        }
                        model.save()
                    }
                }
                
                // 回到主线程更新所有数据结构
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // 主线程补做字体/分页（依赖 UIWindow safeArea）
                    tempChapterModel?.reviseFont()
                    
                    self.chapterModels[chapterID!.stringValue] = tempChapterModel
                    
                    guard let chapterID = chapterID,
                          let currentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId),
                          let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) else {
                        return
                    }
                    
                    let nextIndex = currentIndex + 1
                    guard nextIndex <= self.chapterIDs.count else { return }
                    
                    self.chapterIDs.insert(chapterID, at: nextIndex)
                    self.loadChapterIDs.remove(at: loadIndex)
                    self.tableView.reloadData()
                }
                
            }else{ // 加载网络章节数据
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // 检查下一章是否锁定（付费墙已移除，恒为 false）
                    if let nextChapterListModel = self.vc.readModel.chapterListModels.first(where: { $0.id == chapterID }) {
                        if nextChapterListModel.isLocked {
                            if let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID!) {
                                self.loadChapterIDs.remove(at: loadIndex)
                            }
                            return
                        }
                    }
                    
                    guard let id = chapterID?.intValue else { return }
                    let dispatched = self.vc.chapterLoader?.loadChapter(chapterId: id, successBlock: { [weak self] tempChapterModel in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            self.chapterModels[chapterID!.stringValue] = tempChapterModel
                            
                            guard let chapterID = chapterID,
                                  let currentIndex = self.chapterIDs.firstIndex(of: currentChapterModelId),
                                  let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) else {
                                return
                            }
                            
                            let nextIndex = currentIndex + 1
                            guard nextIndex <= self.chapterIDs.count else { return }
                            
                            self.chapterIDs.insert(chapterID, at: nextIndex)
                            self.loadChapterIDs.remove(at: loadIndex)
                            self.tableView.reloadData()
                        }
                    }, failureBlock: { [weak self] error in
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self,
                                  let chapterID = chapterID,
                                  let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) else {
                                return
                            }
                            self.loadChapterIDs.remove(at: loadIndex)
                            ReaderEnvironment.presentErrorNotice(self.view, error.localizedDescription)
                        }
                    })
                    
                    // If throttled, remove from loading list so it can be retried after cooldown
                    if dispatched != true, let chapterID = chapterID,
                       let loadIndex = self.loadChapterIDs.firstIndex(of: chapterID) {
                        self.loadChapterIDs.remove(at: loadIndex)
                    }
                }
            }
        }
    }
    
    deinit {
        bottomView?.discardClock()
    }
}
