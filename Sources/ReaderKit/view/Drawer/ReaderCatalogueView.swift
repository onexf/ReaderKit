//
//  ReaderCatalogueView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

@objc public protocol ReaderCatalogueDelegate: NSObjectProtocol {
    
    /// 点击章节
    @objc optional func catalogViewClickChapter(catalogView: ReaderCatalogueView, chapterListModel: ReaderChapterListItemModel)
    
    /// 目录列表滚动到接近底部、且目录尚未加载完整时触发（用于自动补目录 / 上拉加载更多）
    @objc optional func catalogViewDidReachBottomEdge(catalogView: ReaderCatalogueView)
}

open class ReaderCatalogueView: UIView,UITableViewDelegate,UITableViewDataSource {

    // MARK: - 设计稿尺寸

    /// 加载中 footer 高度（设计稿「阅读器-目录加载」：列表末尾 32 的转圈 + 上方 12 间距）
    private let loadingFooterHeight: CGFloat = 44

    /// 代理
    open weak var delegate: ReaderCatalogueDelegate!
    
    /// 数据源
    open var readModel: ReaderBookModel! {
        
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

    /// 目录未加载完整时挂在列表末尾的加载指示器
    private var loadingFooter: UIView!

    private var loadingIndicator: UIActivityIndicatorView!
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onChapterListUpdated),
                                               name: .readerChapterListDidUpdate,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 后台目录补全有新章节合并时刷新列表（仅刷新数据，不打断当前浏览位置）。
    @objc private func onChapterListUpdated() {
        guard readModel != nil else { return }
        reviseNumberColumnWidth()
        tableView.reloadData()
        reviseLoadingFooter()
    }

    /// 按最大章节号的位数量一次序号列宽
    ///
    /// 用等宽的「0」串测量而不是真实数字：Lexend Deca 的数字宽度不完全一致，
    /// 用真实数字会让不同行差几个点；字重取 Regular（当前章那档，比 Light 宽）保证都装得下。
    private func reviseNumberColumnWidth() {

        let maxNumber = max(readModel?.totalEpisodes ?? 0, readModel?.chapterListModels?.count ?? 0)
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
        tableView.showsVerticalScrollIndicator = false
        addSubview(tableView)

        // 加载中 footer
        loadingFooter = UIView()
        loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.color = ReaderConfiguration.shared().currentThemeColors.textT3
        loadingIndicator.hidesWhenStopped = true
        loadingFooter.addSubview(loadingIndicator)
    }
    
    /// 滚动到阅读记录
    open func scrollEntry() {
        
        if readModel != nil {
            
            tableView.reloadData()
       
            if !readModel.chapterListModels.isEmpty {
                
                var row = -1
                
                // 安全检查 chapterModel 是否存在
                guard let currentChapterId = readModel.recordModel.chapterModel?.id else {
                    return
                }
                
                for (index, item) in readModel.chapterListModels.enumerated() {
                    
                    if (item.id == currentChapterId) {
                        
                        row = index
                        
                        break
                    }
                }
                
                if row != -1 {
                    
                    tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
                }
            }
        }
    }

    // MARK: - 加载态

    /// 目录尚未加载完整时在列表末尾展示转圈，加载完成后移除
    open func reviseLoadingFooter() {

        let isLoading = (readModel != nil) && !readModel.isChapterListComplete

        guard isLoading else {
            loadingIndicator.stopAnimating()
            if tableView.tableFooterView === loadingFooter { tableView.tableFooterView = nil }
            return
        }

        layoutLoadingFooter()
        loadingIndicator.startAnimating()

        // 同一个 footer 实例不重复赋值，避免触发多余的表格布局
        if tableView.tableFooterView !== loadingFooter { tableView.tableFooterView = loadingFooter }
    }

    /// footer 自身的尺寸与转圈位置（宽度跟随列表）
    private func layoutLoadingFooter() {

        loadingFooter.frame = CGRect(x: 0, y: 0, width: bounds.width, height: loadingFooterHeight)

        // 上方留出与章节行一致的 20 间距，转圈居中在剩余区域
        let indicatorTop = ReaderCatalogueCell.rowSpacing
        loadingIndicator.center = CGPoint(x: bounds.width / 2,
                                         y: indicatorTop + (loadingFooterHeight - indicatorTop) / 2)
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
    open func adoptThemeColors(_ colors: ReaderThemeColors) {

        loadingIndicator.color = colors.textT3

        tableView.reloadData()
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        tableView.frame = bounds

        // footer 宽度跟随列表宽度变化（不重新挂载，避免布局递归）
        if tableView.tableFooterView === loadingFooter { layoutLoadingFooter() }
    }
    
    // MARK: UITableViewDelegate,UITableViewDataSource
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if readModel != nil { return readModel.chapterListModels.count }
        
        return 0
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = ReaderCatalogueCell.cell(tableView)
        
        // 防止数组越界
        guard indexPath.row < readModel.chapterListModels.count else {
            return cell
        }
        
        // 章节
        let chapterListModel = readModel.chapterListModels[indexPath.row]

        // 展示序号：priority 从 0 开始，缺失时用行号兜底
        let displayNumber = (chapterListModel.priority?.intValue).map { $0 + 1 } ?? (indexPath.row + 1)

        cell.configure(title: trimChapterPrefix(chapterListModel.name, number: displayNumber),
                       number: displayNumber,
                       // 当前阅读章节 - 安全检查
                       isCurrent: readModel.recordModel.chapterModel?.id == chapterListModel.id,
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
        guard indexPath.row < readModel.chapterListModels.count else {
            return
        }
        
        delegate?.catalogViewClickChapter?(catalogView: self, chapterListModel: readModel.chapterListModels[indexPath.row])
    }
    
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        guard readModel != nil else { return }
        
        // 滚动到接近底部（最后 3 行）且目录尚未加载完整时，触发补目录（上拉加载更多）。
        // ensureDirectoryLoaded 内部已做防重入与「已完整则跳过」，频繁触发安全。
        let count = readModel.chapterListModels?.count ?? 0
        if count > 0, indexPath.row >= count - 3, !readModel.isChapterListComplete {
            delegate?.catalogViewDidReachBottomEdge?(catalogView: self)
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
