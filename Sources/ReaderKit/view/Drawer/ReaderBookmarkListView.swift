//
//  ReaderBookmarkListView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/06.
//

import UIKit

/// 长按书签弹出的操作菜单里的按钮。
public enum ReaderBookmarkMenuAction {

    /// 删除这一条。
    case remove

    /// 清空本书全部书签。
    case clearAll

    /// 取消。
    case cancel
}

public protocol ReaderBookmarkListDelegate: AnyObject {

    /// 点了一条书签。
    func bookmarkListView(_ listView: ReaderBookmarkListView, didSelect bookmark: ReaderBookmarkModel)

    /// 书签数据变了（删除 / 清空之后）。供宿主刷新菜单上的书签按钮状态。
    func bookmarkListViewDidChangeBookmarks(_ listView: ReaderBookmarkListView)

    /// 请求删除书签。**悲观删除，以服务端结果为准。**
    ///
    /// 宿主调服务端删，成功（或服务端本来就没有）回 `completion(true)`，列表才移除本地那条；
    /// 回 `false` 则列表原样不动。
    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        requestDelete bookmarks: [ReaderBookmarkModel],
        completion: @escaping (Bool) -> Void
    )

    /// 请求清空本书全部书签。同样是悲观删除。
    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        requestClearAllWithCompletion completion: @escaping (Bool) -> Void
    )

    /// 书签 cell 曝光。已过滤锁定章节，且只在列表真正可见时回调。曝光埋点用。
    func bookmarkListView(_ listView: ReaderBookmarkListView, willExpose bookmark: ReaderBookmarkModel)

    /// 长按弹出操作菜单。菜单曝光埋点用。
    func bookmarkListView(_ listView: ReaderBookmarkListView, willShowMenuFor bookmark: ReaderBookmarkModel)

    /// 点了操作菜单里的某个按钮。点击埋点用。
    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        didSelectMenuAction action: ReaderBookmarkMenuAction,
        for bookmark: ReaderBookmarkModel
    )
}

/// 可以不实现的那几个。
///
/// 三个埋点回调默认什么都不做。两个删除请求**默认回 `false`，也就是不删** ——
/// 书签是要与服务端对账的数据，宿主没接上删除接口时本地就不该自己删掉，
/// 否则换设备再进来它又回来了，用户会以为删除失效。
public extension ReaderBookmarkListDelegate {

    func bookmarkListView(_ listView: ReaderBookmarkListView, willExpose bookmark: ReaderBookmarkModel) {}

    func bookmarkListView(_ listView: ReaderBookmarkListView, willShowMenuFor bookmark: ReaderBookmarkModel) {}

    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        didSelectMenuAction action: ReaderBookmarkMenuAction,
        for bookmark: ReaderBookmarkModel
    ) {}

    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        requestDelete bookmarks: [ReaderBookmarkModel],
        completion: @escaping (Bool) -> Void
    ) {
        completion(false)
    }

    func bookmarkListView(
        _ listView: ReaderBookmarkListView,
        requestClearAllWithCompletion completion: @escaping (Bool) -> Void
    ) {
        completion(false)
    }
}

open class ReaderBookmarkListView: UIView, UITableViewDelegate, UITableViewDataSource {
    
    /// 代理
    open weak var delegate: (any ReaderBookmarkListDelegate)?
    
    /// 数据源
    open var bookModel: ReaderBookModel! {
        
        didSet{
            // 按本书加载排序状态(存"是否降序",未设置默认 false → 升序)
            if let storyID = bookModel?.storyID {
                isAscendingOrder = !ReaderDefaults.bool(ReaderBookmarkListView.sortDescendingKey(storyID: storyID))
            }
            reloadMarks()
        }
    }
    
    /// 组间排序:true = 章节从小到大(默认);false = 章节从大到小
    /// 组内书签固定按时间由近到远,不随此开关变化
    /// 排序状态按书持久化(存"是否降序",未设置默认 false 即升序)
    private static func sortDescendingKey(storyID: String) -> String {
        return "ReaderKit.bookmarkSortDescending.\(storyID)"
    }
    public private(set) var isAscendingOrder: Bool = true
    
    /// 当前展示用的分组快照
    private var groups: [ReaderBookmarkCluster] = []
    
    public private(set) var tableView: ReaderTableView!
    
    /// section header 高度(对照 Figma 11957-12505):上方 12(距分割线)+ 章节名行高 24 + 下方 12(距书签)= 48
    private let sectionHeaderHeight: CGFloat = 48
    
    // MARK: - 空态(无书签时展示:插图 + 文案)
    
    private var placeholderStack: UIView!
    private var placeholderImageView: UIImageView!
    private var placeholderLabel: UILabel!
    
    /// 空态插图尺寸/间距统一为最新通用空态规格(设计稿 199×129 / 间距 20),
    /// 与库内其他空态视图对齐
    private let placeholderImageSize = CGSize(width: 199, height: 129)
    private let placeholderImageGap: CGFloat = 20
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
        
        // 目录补全 / 对账更新后刷新书签(分组的章节序、锁定态、被删章节移除都依赖最新章节列表)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCatalogueRefresh),
                                               name: .readerChapterListDidUpdate,
                                               object: nil)
        
        // 服务端书签列表拉取合并完成后刷新(重装/换设备后从服务端拉回的书签需在列表实时展示)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleBookmarkMerge(_:)),
                                               name: .readerBookmarksMerged,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 章节列表更新后刷新书签列表(仅在已有数据时)
    @objc private func handleCatalogueRefresh() {
        guard bookModel != nil else { return }
        reloadMarks()
    }
    
    /// 服务端书签合并完成后刷新当前书的书签列表(object 为 storyID,只刷新匹配的书)
    @objc private func handleBookmarkMerge(_ note: Notification) {
        guard let storyID = note.object as? String, storyID == bookModel?.storyID else { return }
        reloadMarks()
    }
    
    private func addSubviews() {
        
        backgroundColor = .clear
        
        tableView = ReaderTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionFooterHeight = 0
        // iOS 15+ 默认会给每个 section header 顶部加约 22pt 间距,这里清零,避免分组间距过松
        tableView.sectionHeaderTopPadding = 0
        addSubview(tableView)
        
        // 长按书签弹出删除 sheet
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleRowLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        tableView.addGestureRecognizer(longPress)
        
        // 空态:插图 + 文案
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        placeholderStack = UIView()
        placeholderStack.isHidden = true
        addSubview(placeholderStack)
        
        placeholderImageView = UIImageView()
        // 统一为最新通用空态插图(empty_no_content 无记录),插图自带底色,六套阅读主题下不染色不替换,
        // 与库内其他空态视图处理方式一致
        placeholderImageView.image = ReaderEnvironment.images.bookmarkEmpty()
        placeholderImageView.contentMode = .scaleAspectFit
        placeholderStack.addSubview(placeholderImageView)
        
        placeholderLabel = UILabel()
        placeholderLabel.text = ReaderEnvironment.strings.bookmarkEmpty
        placeholderLabel.font = ReaderEnvironment.fonts.uiRegular(14)
        placeholderLabel.textColor = themeColors.textFaint
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderStack.addSubview(placeholderLabel)
    }
    
    /// 长按书签:弹出删除 sheet(Remove 删当前 / Clear All 清全部)
    @objc private func handleRowLongPress(_ gesture: UILongPressGestureRecognizer) {
        
        guard gesture.state == .began, bookModel != nil else { return }
        
        let point = gesture.location(in: tableView)
        
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.section < groups.count,
              indexPath.row < groups[indexPath.section].bookmarks.count else { return }
        
        let mark = groups[indexPath.section].bookmarks[indexPath.row]
        
        // 锁定章节的书签不支持操作菜单(仅可通过 Clear All 清除)
        if groups[indexPath.section].isLocked { return }
        
        // sheet 曝光上报(由外部用统一锁定逻辑判定 bookmark_type)
        delegate?.bookmarkListView(self, willShowMenuFor: mark)
        
        ReaderBookmarkDeleteSheet.show(onRemove: { [weak self] in
            
            guard let self = self else { return }
            
            self.delegate?.bookmarkListView(self, didSelectMenuAction: .remove, for: mark)
            
            self.discardMark(mark)
            
        }, onClearAllConfirmed: { [weak self] in
            
            // 确认清除后只执行清除,不在此处上报(点击上报已在 onClearAllTapped)
            self?.clearAllMarks()
            
        }, onClearAllTapped: { [weak self] in
            
            guard let self = self else { return }
            
            // 点击 Clear All 按钮即上报(无论后续是否确认)
            self.delegate?.bookmarkListView(self, didSelectMenuAction: .clearAll, for: mark)
            
        }, onCancel: { [weak self] in
            
            guard let self = self else { return }
            
            self.delegate?.bookmarkListView(self, didSelectMenuAction: .cancel, for: mark)
        })
    }
    
    /// 删除单条书签并刷新
    private func discardMark(_ mark: ReaderBookmarkModel) {
        
        // 悲观删除:先请求服务端,成功(或服务端已无)才移除本地并刷新;失败不移除
        delegate?.bookmarkListView(self, requestDelete: [mark], completion: { [weak self] success in
            guard let self = self, success else { return }
            guard let realIndex = self.bookModel.bookmarkEntries.firstIndex(of: mark) else { return }
            _ = self.bookModel.discardMark(index: realIndex)
            self.reloadMarks()
            self.delegate?.bookmarkListViewDidChangeBookmarks(self)
        })
    }
    
    /// 清空全部书签并刷新
    private func clearAllMarks() {
        
        // 悲观清空:走按书清空接口(deleteByBook)一次删该书全部,成功才清空本地并刷新;失败不清空
        delegate?.bookmarkListView(self, requestClearAllWithCompletion: { [weak self] success in
            guard let self = self, success else { return }
            self.bookModel.discardAllMarks()
            self.reloadMarks()
            self.delegate?.bookmarkListViewDidChangeBookmarks(self)
        })
    }
    
    /// 切换组间排序(章节升序 / 降序)并刷新列表;组内时间顺序不变
    open func toggleSort() {
        
        isAscendingOrder.toggle()
        
        // 按本书持久化排序状态(存是否降序)
        if let storyID = bookModel?.storyID {
            ReaderDefaults.setBool(!isAscendingOrder, ReaderBookmarkListView.sortDescendingKey(storyID: storyID))
        }
        
        reloadMarks()
    }
    
    /// 重新分组并刷新书签列表
    open func reloadMarks() {
        
        guard bookModel != nil else {
            
            groups = []
            
            tableView.reloadData()
            
            reviseVacantState()
            
            return
        }
        
        // 锁定章节只保留最近一个(markGroups 已过滤);列表里其 section 仅展示章节名(header)
        // + 一个锁定提示 cell(锁 + Chapter locked + Subscribe),不展示书签内容
        groups = bookModel.markGroups(isAscendingOrder: isAscendingOrder)
        
        tableView.reloadData()
        
        reviseVacantState()
    }
    
    /// 主题切换后刷新列表(锁定提示 cell 随 reloadData 重建)
    open func renewSealedTipTheme() {
        tableView.reloadData()
    }

    /// 应用主题颜色(日/夜间、护眼色切换时由外部调用)
    /// 列表 cell / section header 随 reloadData 用当前主题色重建,
    /// 此处负责刷新不随 reloadData 重建的空态(插图随主题切换、文案颜色)
    open func adoptThemeColors(_ colors: ReaderTintPalette) {

        // 空态插图统一为通用 empty_no_content,自带底色不随主题切换;仅文案色跟随阅读主题
        placeholderLabel.textColor = colors.textFaint

        tableView.reloadData()
    }

    /// 根据数据更新空态显隐
    private func reviseVacantState() {
        
        placeholderStack.isHidden = !groups.isEmpty
        
        placeholderLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textFaint
        
        setNeedsLayout()
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        tableView.frame = bounds
        
        let labelHeight = placeholderLabel.sizeThatFits(CGSize(width: bounds.width - 40, height: .greatestFiniteMagnitude)).height
        let groupHeight = placeholderImageSize.height + placeholderImageGap + labelHeight
        let groupTop = max(0, (bounds.height - groupHeight) / 2 - 20)
        placeholderStack.frame = CGRect(x: 0, y: groupTop, width: bounds.width, height: groupHeight)
        
        placeholderImageView.frame = CGRect(x: (bounds.width - placeholderImageSize.width) / 2,
                                      y: 0,
                                      width: placeholderImageSize.width,
                                      height: placeholderImageSize.height)
        
        placeholderLabel.frame = CGRect(x: 20,
                                  y: placeholderImageView.frame.maxY + placeholderImageGap,
                                  width: bounds.width - 40,
                                  height: labelHeight)
    }
    
    // MARK: UITableViewDelegate,UITableViewDataSource
    
    open func numberOfSections(in tableView: UITableView) -> Int {
        
        return groups.count
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        guard section < groups.count else { return 0 }
        
        // 锁定章节:章节名在 header,内容区用 1 个锁定提示 cell(锁 + Chapter locked + Subscribe)
        if groups[section].isLocked { return 1 }
        
        return groups[section].bookmarks.count
    }
    
    open func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        guard section < groups.count else { return nil }
        
        let header = ReaderBookmarkSectionHeader.header(tableView)
        
        header.configure(group: groups[section])
        
        return header
    }
    
    open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        
        return sectionHeaderHeight
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard indexPath.section < groups.count else {
            return ReaderBookmarkCell.cell(tableView)
        }
        
        let group = groups[indexPath.section]
        
        // 锁定章节:返回锁定提示 cell(锁 + Chapter locked + Subscribe to read more)
        if group.isLocked {
            let cell = ReaderBookmarkLockedCell.cell(tableView)
            cell.refresh()
            return cell
        }
        
        let cell = ReaderBookmarkCell.cell(tableView)
        
        guard indexPath.row < group.bookmarks.count else { return cell }
        
        let mark = group.bookmarks[indexPath.row]
        
        cell.configure(mark: mark,
                       progress: bookModel.markProgress(mark),
                       isLocked: group.isLocked)
        
        return cell
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        guard indexPath.section < groups.count else { return READER_MARK_CELL_HEIGHT }
        
        let group = groups[indexPath.section]
        
        if group.isLocked {
            return ReaderBookmarkLockedCell.cellHeight
        }
        
        // 分组内最后一条书签:不再额外留底部 12 间距(与下一个章节标题的 12px 间距由 header 顶部提供)
        // 非最后一条:底部留 12,作为同章节多条书签之间的间隔
        let isLast = indexPath.row == group.bookmarks.count - 1
        return isLast ? READER_MARK_CELL_CONTENT_HEIGHT : READER_MARK_CELL_HEIGHT
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard indexPath.section < groups.count else { return }
        
        let group = groups[indexPath.section]
        
        // 锁定章节的提示 cell 不响应点击
        guard !group.isLocked, indexPath.row < group.bookmarks.count else { return }
        
        delegate?.bookmarkListView(self, didSelect: group.bookmarks[indexPath.row])
    }
    
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
        // 列表未真正展示给用户时(隐藏态 reloadData 等)不上报曝光
        guard isMarkListVisible else { return }
        
        guard indexPath.section < groups.count else { return }
        
        let group = groups[indexPath.section]
        
        // 上锁章节的书签无需上报(锁定章节仅展示一个锁定提示 cell)
        guard !group.isLocked, indexPath.row < group.bookmarks.count else { return }
        
        delegate?.bookmarkListView(self, willExpose: group.bookmarks[indexPath.row])
    }
    
    /// 书签列表是否真正可见(自身及祖先均未隐藏、未透明,且在窗口可见区域内)
    /// 用于过滤隐藏态/离屏时 reloadData 触发的无效 willDisplay 曝光
    private var isMarkListVisible: Bool {
        
        guard let window = window else { return false }
        
        var view: UIView? = self
        while let current = view {
            if current.isHidden || current.alpha <= 0.01 { return false }
            view = current.superview
        }
        
        let frameInWindow = convert(bounds, to: window)
        return window.bounds.intersects(frameInWindow)
    }
    
    open func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        
        // 锁定章节提示 cell 不可滑动删除
        if indexPath.section < groups.count, groups[indexPath.section].isLocked {
            return .none
        }
        
        return .delete
    }
    
    open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        guard editingStyle == .delete,
              indexPath.section < groups.count,
              !groups[indexPath.section].isLocked,
              indexPath.row < groups[indexPath.section].bookmarks.count else { return }
        
        let mark = groups[indexPath.section].bookmarks[indexPath.row]
        
        // 悲观删除:先请求服务端,成功才移除本地;成功/失败都整体刷新(成功移除该行、失败让滑动复位)
        delegate?.bookmarkListView(self, requestDelete: [mark], completion: { [weak self] success in
            guard let self = self else { return }
            if success, let realIndex = self.bookModel.bookmarkEntries.firstIndex(of: mark) {
                _ = self.bookModel.discardMark(index: realIndex)
                self.delegate?.bookmarkListViewDidChangeBookmarks(self)
            }
            self.reloadMarks()
        })
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
