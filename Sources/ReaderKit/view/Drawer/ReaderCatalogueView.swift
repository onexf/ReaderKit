//
//  ReaderCatalogueView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

public protocol ReaderCatalogueDelegate: AnyObject {

    /// 点了目录里的一章。
    func catalogueView(_ catalogueView: ReaderCatalogueView, didSelect chapter: ReaderChapterListItemModel)

    /// 列表滚到接近底部、且目录尚未加载完整 —— 该补下一页了。
    func catalogueViewDidReachBottomEdge(_ catalogueView: ReaderCatalogueView)

    /// 补页失败后用户点了列表末尾的失败提示。
    ///
    /// 与 `catalogueViewDidReachBottomEdge` 分开：那条是滚动自动触发、可以静默失败，
    /// 这条是用户明确要求重试，宿主应当绕开失败计数一类的节流。
    func catalogueViewDidRequestRetry(_ catalogueView: ReaderCatalogueView)
}

open class ReaderCatalogueView: UIView, UITableViewDelegate, UITableViewDataSource {

    // MARK: - 设计稿尺寸

    /// 加载中 footer 高度（设计稿「阅读器-目录加载」：列表末尾 32 的转圈 + 上方 12 间距）
    private let loadingFooterHeight: CGFloat = 44

    /// 失败态 footer 高度：一行文案，比转圈略高一点好点中
    private let failureFooterHeight: CGFloat = 56

    /// 代理
    open weak var delegate: (any ReaderCatalogueDelegate)?
    
    /// 宿主报告的「补页失败」。
    ///
    /// 目录完整性（`isChapterListComplete`）只能表达「补完了没有」，表达不了
    /// 「还没补完但已经失败了」—— 只看它的话失败之后转圈会一直转，用户既看不出失败
    /// 也没有重试入口。宿主在补页彻底失败时置 `true`，重新开始补页时置回 `false`。
    open var isCatalogueSupplyFailed: Bool = false {
        didSet {
            guard oldValue != isCatalogueSupplyFailed else { return }
            reviseLoadingFooter()
        }
    }
    
    /// 数据源
    open var bookModel: ReaderBookModel! {
        
        didSet{
            
            reviseNumberColumnWidth()
            
            tableView.reloadData()
            
            reviseLoadingFooter()
            
            scrollEntry()
        }
    }

    /// 序号列宽度：按全书最大章节号统一算，保证所有行的标题起点对齐
    private var numberColumnWidth: CGFloat = ReaderCatalogueCell.numberColumnMinWidth
    
    public private(set) var tableView: ReaderTableView!

    /// 目录未加载完整时挂在列表末尾的 footer（转圈或失败提示共用这一个容器）
    private var loadingFooter: UIView!

    /// 加载中的指示视图。由接入方经 `ReaderEnvironment.makeLoadingIndicator` 提供，
    /// 主题变化时整个重建 —— 它可能是 Lottie 那种颜色烤死的东西，改不了色。
    private var loadingIndicator: UIView!

    /// 失败态的提示文案，整块可点重试
    private var failureLabel: UILabel!

    /// 有一次「定位到当前章」还没做成 —— 尺寸就绪后补做。见 `scrollEntry()`。
    private var needsScrollToCurrentChapter = false
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCatalogueRefresh),
                                               name: .readerChapterListDidUpdate,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 后台目录补全有新章节合并时刷新列表（仅刷新数据，不打断当前浏览位置）。
    @objc private func handleCatalogueRefresh() {
        guard bookModel != nil else { return }
        reviseNumberColumnWidth()
        tableView.reloadData()
        reviseLoadingFooter()
    }

    /// 按最大章节号的位数量一次序号列宽
    ///
    /// 用等宽的「0」串测量而不是真实数字：Lexend Deca 的数字宽度不完全一致，
    /// 用真实数字会让不同行差几个点；字重取 Regular（当前章那档，比 Light 宽）保证都装得下。
    private func reviseNumberColumnWidth() {

        let maxNumber = max(bookModel?.totalChapterCount ?? 0, bookModel?.catalogueEntries?.count ?? 0)
        let digits = max(2, String(max(1, maxNumber)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let measured = ceil(sample.size(withAttributes: [.font: ReaderEnvironment.fonts.uiRegular(14)]).width)

        numberColumnWidth = max(ReaderCatalogueCell.numberColumnMinWidth, measured)
    }
    
    private func addSubviews() {
        
        backgroundColor = .clear
        
        tableView = ReaderTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        // 设计稿首行内容与分割线下方 12pt 处严格对齐，这里不再额外留顶部内边距
        tableView.contentInset = .zero
        // 关掉自动安全区调整。
        //
        // 抽屉以 `.zero` 创建（也就是暂时贴在屏幕左上角），表格在那一刻会被判成
        // 「贴着安全区顶边」而自动加上一段顶部 inset；等抽屉拿到真实 frame、inset 归零时，
        // contentOffset 未必跟着回位 —— 症状是列表顶部多出一段空白，首行看起来缺失了。
        // 这个列表永远嵌在抽屉里、不贴屏幕边，自动调整对它没有意义。
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.showsVerticalScrollIndicator = false
        addSubview(tableView)

        // 加载中 / 失败 footer（同一个容器，按状态切换里面显示哪个）
        loadingFooter = UIView()

        installLoadingIndicator(tintColor: ReaderConfiguration.shared().currentThemeColors.textFaint)

        failureLabel = UILabel()
        failureLabel.font = ReaderEnvironment.fonts.uiRegular(13)
        failureLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textFaint
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 2
        failureLabel.isHidden = true
        // 整块可点：转圈那一小团太小，点不中
        failureLabel.isUserInteractionEnabled = true
        failureLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(touchRetry))
        )
        loadingFooter.addSubview(failureLabel)
    }
    
    @objc private func touchRetry() {
        
        delegate?.catalogueViewDidRequestRetry(self)
    }
    
    /// 装（或重装）加载中的指示视图。
    ///
    /// **用约束居中而不是设 frame。** 接入方给的视图可能只有固有尺寸
    /// （`UIActivityIndicatorView`）、也可能只有自带的宽高约束（`LottieAnimationView`），
    /// 库替它设 frame 的话后者会被自己的约束覆盖、或者干脆是 0×0。
    /// 只固定位置、把尺寸留给它自己，两种都成立。
    private func installLoadingIndicator(tintColor: UIColor) {
        
        loadingIndicator?.removeFromSuperview()
        
        let indicator = ReaderEnvironment.makeLoadingIndicator(tintColor)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        loadingFooter.addSubview(indicator)
        
        // 垂直方向：上方留出与章节行一致的 20 间距，在剩余区域居中。
        // 折算成「相对 footer 居中，再往下挪半个间距」。
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: loadingFooter.centerXAnchor),
            indicator.centerYAnchor.constraint(
                equalTo: loadingFooter.centerYAnchor,
                constant: ReaderCatalogueCell.rowSpacing / 2
            ),
        ])
        
        loadingIndicator = indicator
    }
    
    /// 滚动到阅读记录
    ///
    /// ⚠️ **本方法可能在自身还没有尺寸时被调用。** 抽屉的既有装配顺序是「先灌数据、
    /// 再设 frame」（`ReaderDrawerView` 以 `.zero` 创建），此时 `scrollToRow` 在零尺寸
    /// 表格上**无效且不报错** —— 症状是目录永远停在第一条，从不定位到当前章。
    /// 所以尺寸不可用时先记下来，等 `layoutSubviews` 拿到尺寸再补做。
    open func scrollEntry() {
        
        guard bookModel != nil else { return }
        
        guard bounds.height > 0 else {
            needsScrollToCurrentChapter = true
            return
        }
        
        performScrollToCurrentChapter()
    }
    
    private func performScrollToCurrentChapter() {
        
        guard let bookModel, !bookModel.catalogueEntries.isEmpty else { return }
        
        tableView.reloadData()
        
        // 安全检查 chapterModel 是否存在
        guard let currentChapterId = bookModel.readingRecord.activeChapter?.id else { return }
        
        guard let row = bookModel.catalogueEntries.firstIndex(where: { $0.id == currentChapterId }) else {
            // 当前章还不在已加载目录里（分页目录常态）。不滚，等补到了再说 ——
            // 滚到一个错的位置比停在顶部更难判断。
            return
        }
        
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
    }

    // MARK: - 加载态

    /// 按目录完整性与宿主报告的失败态渲染列表末尾的 footer。
    ///
    /// 三态：目录完整 → 不挂 footer；未完整且未失败 → 转圈；未完整且已失败 → 可点重试的文案。
    open func reviseLoadingFooter() {

        guard let bookModel, !bookModel.isChapterListComplete else {
            // footer 整个摘下来，指示视图跟着离屏，不需要额外停动画 ——
            // 接入方给的视图库也不知道怎么停（见 `makeLoadingIndicator` 的约定）。
            if tableView.tableFooterView === loadingFooter { tableView.tableFooterView = nil }
            return
        }

        let isFailed = isCatalogueSupplyFailed

        // 文案在这里取而不是在 addSubviews 里取：本视图是懒建的，但注入点的配置时机
        // 由宿主决定，现取才保证拿到的是宿主设过的那份。
        failureLabel.text = ReaderEnvironment.strings.catalogueLoadFailed
        failureLabel.isHidden = !isFailed
        loadingIndicator.isHidden = isFailed

        let targetHeight = isFailed ? failureFooterHeight : loadingFooterHeight
        // 高度变了必须重新赋值 —— UITableView 只在挂载时读一次 footer 高度，
        // 光改 frame 它不会重新给 contentSize 留位置。
        let needsRemount = tableView.tableFooterView !== loadingFooter
            || abs(loadingFooter.frame.height - targetHeight) > 0.5

        layoutLoadingFooter(height: targetHeight)

        if needsRemount { tableView.tableFooterView = loadingFooter }
    }

    /// footer 的尺寸与内部元素位置（宽度跟随列表）。
    ///
    /// ⚠️ **只改 size，不要动 origin。** `tableFooterView` 的位置由 UITableView 按
    /// contentSize 算，这里把 origin 写成 (0, 0) 的话，在表格下一次重新布局之前它就
    /// 一直停在列表坐标原点 —— 症状是转圈跑到列表顶部、压在前几行章节上。
    private func layoutLoadingFooter(height: CGFloat) {

        loadingFooter.frame.size = CGSize(width: bounds.width, height: height)

        // 加载中的指示视图不在这里摆 —— 它是约束居中的（见 `installLoadingIndicator`），
        // footer 的 bounds 一变它自己就跟上了。

        // 失败文案：上方留出与章节行一致的 20 间距，占满剩余区域。
        let contentTop = ReaderCatalogueCell.rowSpacing
        failureLabel.frame = CGRect(x: 0, y: contentTop, width: bounds.width, height: height - contentTop)
    }

    // MARK: - 标题处理

    /// 去掉章节名里与行首序号重复的「Chapter N」前缀
    ///
    /// 设计稿把序号和标题拆成了两段（行首固定「Chapter N」+ 后面纯标题），而服务端下发的
    /// name 通常自带前缀（`Chapter 1: Betrayal`、`Chapter 1 -Rejecting Me...`），标题为空时
    /// 还会被接入方的目录合并逻辑兜底成 `Chapter N`。直接展示会变成
    /// 「Chapter 1  Chapter 1: Betrayal」，所以这里把重复的前缀连同紧随的分隔符一起剥掉。
    /// 前缀里的序号与行首序号不一致时不做处理，原样展示，避免误删正文标题。
    private func trimChapterPrefix(_ name: String?, number: Int) -> String? {

        guard let trimmed = name?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }

        let chapterWord = ReaderEnvironment.strings.chapter
        // 兼容「Chapter 1」与「Chapter1」两种写法
        let candidates = ["\(chapterWord) \(number)", "\(chapterWord)\(number)"]

        guard let prefix = candidates.first(where: { trimmed.hasPrefix($0) }) else { return trimmed }

        // 剥掉前缀后再逐个去掉紧随的分隔符与空格（只处理开头，保留标题自身的标点）
        let separators: Set<Character> = [" ", ":", "：", "-", "—", "–", ".", "。", "、", ",", "，"]
        var rest = trimmed.dropFirst(prefix.count)
        while let first = rest.first, separators.contains(first) {
            rest = rest.dropFirst()
        }

        return rest.isEmpty ? nil : String(rest)
    }

    // MARK: - 主题换肤

    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderTintPalette) {

        // 指示视图整个重建而不是改色：接入方给的可能是 Lottie 那种颜色烤死在文件里的东西，
        // 库无从得知该改它哪个属性。重建的代价只是一次 addSubview。
        let wasHidden = loadingIndicator?.isHidden ?? false
        installLoadingIndicator(tintColor: colors.textFaint)
        loadingIndicator.isHidden = wasHidden

        failureLabel.textColor = colors.textFaint

        tableView.reloadData()
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        tableView.frame = bounds

        // footer 宽度跟随列表宽度变化（不重新挂载，避免布局递归）
        if tableView.tableFooterView === loadingFooter {
            layoutLoadingFooter(height: loadingFooter.frame.height)
        }

        // 补做那次落空的定位（`scrollEntry()` 在还没有尺寸时被调用过）。
        // 先清标记再做：`performScrollToCurrentChapter` 里的 `reloadData` 只会让表格
        // 这个子视图重新布局，不会回头触发本方法，但清了更稳。
        if needsScrollToCurrentChapter, bounds.height > 0 {
            needsScrollToCurrentChapter = false
            performScrollToCurrentChapter()
        }
    }
    
    // MARK: UITableViewDelegate,UITableViewDataSource
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if bookModel != nil { return bookModel.catalogueEntries.count }
        
        return 0
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = ReaderCatalogueCell.cell(tableView)
        
        // 防止数组越界
        guard indexPath.row < bookModel.catalogueEntries.count else {
            return cell
        }
        
        // 章节
        let chapterListModel = bookModel.catalogueEntries[indexPath.row]

        // 展示序号：priority 从 0 开始，缺失时用行号兜底
        let displayNumber = (chapterListModel.priority?.intValue).map { $0 + 1 } ?? (indexPath.row + 1)

        cell.configure(title: trimChapterPrefix(chapterListModel.name, number: displayNumber),
                       number: displayNumber,
                       // 当前阅读章节 - 安全检查
                       isCurrent: bookModel.readingRecord.activeChapter?.id == chapterListModel.id,
                       // 需要解锁且未解锁
                       isLocked: chapterListModel.isLocked,
                       numberColumnWidth: numberColumnWidth,
                       colors: ReaderConfiguration.shared().currentThemeColors)
        
        return cell
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // 设计稿：章节行内容 18 + 行间距 20
        return ReaderCatalogueCell.rowHeight
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        // 防止数组越界
        guard indexPath.row < bookModel.catalogueEntries.count else {
            return
        }
        
        delegate?.catalogueView(self, didSelect: bookModel.catalogueEntries[indexPath.row])
    }
    
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        guard bookModel != nil else { return }
        
        // 滚动到接近底部（最后 3 行）且目录尚未加载完整时，触发补目录（上拉加载更多）。
        // ensureDirectoryLoaded 内部已做防重入与「已完整则跳过」，频繁触发安全。
        let count = bookModel.catalogueEntries?.count ?? 0
        if count > 0, indexPath.row >= count - 3, !bookModel.isChapterListComplete {
            delegate?.catalogueViewDidReachBottomEdge(self)
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
