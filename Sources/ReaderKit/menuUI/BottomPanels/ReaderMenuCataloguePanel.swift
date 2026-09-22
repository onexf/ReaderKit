//
//  ReaderMenuCataloguePanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/24.
//

import UIKit

open class ReaderMenuCataloguePanel: UIView, UITableViewDelegate, UITableViewDataSource {
    
    /// 数据源
    open var bookModel: ReaderBookModel! {
        didSet {
            reviseStoryInfo()
            tableView.reloadData()
            scrollToActiveChapter()
        }
    }
    
    /// 选中章节回调
    open var onChapterChosen: ((ReaderChapterListItemModel) -> Void)?
    
    /// 顶部信息视图
    private var bookHeader: UIView!
    private var coverThumb: UIImageView!
    private var storyTitleLabel: UILabel!
    private var writerLabel: UILabel!
    private var activeChapterLabel: UILabel!
    private var orderToggle: UIButton!
    
    /// 列表
    private var tableView: UITableView!
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCatalogueRefresh),
                                               name: .readerChapterListDidUpdate,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 后台目录补全有新章节合并时刷新列表（仅刷新数据，不打断用户当前浏览位置）。
    @objc private func handleCatalogueRefresh() {
        guard bookModel != nil else { return }
        tableView.reloadData()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureViews() {
        backgroundColor = ReaderConfiguration.shared().bgColor
        
        // 设置圆角 - 左上和右上
        layer.cornerRadius = 12
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        
        // 顶部信息视图
        bookHeader = UIView()
        bookHeader.backgroundColor = .clear
        addSubview(bookHeader)
        
        // 书籍封面
        coverThumb = UIImageView()
        coverThumb.contentMode = .scaleAspectFill
        coverThumb.clipsToBounds = true
        coverThumb.image = ReaderEnvironment.images.coverPlaceholder()
        coverThumb.layer.cornerRadius = 8
        bookHeader.addSubview(coverThumb)
        
        // 书名
        storyTitleLabel = UILabel()
        storyTitleLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        storyTitleLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textBody
        storyTitleLabel.numberOfLines = 1
        bookHeader.addSubview(storyTitleLabel)
        
        // 作者
        writerLabel = UILabel()
        writerLabel.font = ReaderEnvironment.fonts.uiRegular(14)
        writerLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textFaint
        writerLabel.numberOfLines = 1
        bookHeader.addSubview(writerLabel)
        
        // 当前章节
        activeChapterLabel = UILabel()
        activeChapterLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        activeChapterLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textFaint
        activeChapterLabel.numberOfLines = 1
        bookHeader.addSubview(activeChapterLabel)
        
        // 箭头按钮
        orderToggle = UIButton(type: .custom)
        orderToggle.setImage(ReaderEnvironment.images.disclosureArrow()?.withRenderingMode(.alwaysTemplate), for: .normal)
        orderToggle.tintColor = ReaderConfiguration.shared().currentThemeColors.textBody
        orderToggle.isUserInteractionEnabled = false
        bookHeader.addSubview(orderToggle)
        
        // 列表
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = true
        addSubview(tableView)
    }
    
    /// 更新书籍信息
    open func reviseStoryInfo() {
        guard let bookModel = bookModel else { return }
        
        // 设置书名
        storyTitleLabel.text = bookModel.storyName
        writerLabel.text = bookModel.writer
        
        // 设置当前章节信息（安全访问）
        if let recordModel = bookModel.recordModel,
           let chapterModel = recordModel.chapterModel {
            activeChapterLabel.text = ReaderEnvironment.strings.chapter + " \(chapterModel.priority.intValue)"
        } else {
            activeChapterLabel.text = ReaderEnvironment.strings.chapter + " 1"
        }
        
        // 如果有封面图片URL，可以加载
        // coverThumb.kf.setImage(with: URL(string: bookModel.coverURL))
    }
    
    /// 滚动到当前章节
    private func scrollToActiveChapter() {
        guard let bookModel = bookModel, !bookModel.chapterListModels.isEmpty else { return }
        
        if let index = bookModel.chapterListModels.firstIndex(where: { $0.id == bookModel.recordModel.chapterModel.id }) {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: false)
            }
        }
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        let w = frame.width
        
        // 顶部信息视图
        let headerHeight: CGFloat = 80
        bookHeader.frame = CGRect(x: 0, y: 0, width: w, height: headerHeight)
        
        // 布局顶部信息
        let margin: CGFloat = 20
        let coverSize: CGFloat = 48
        
        coverThumb.frame = CGRect(x: margin, y: (headerHeight - coverSize) / 2, width: coverSize, height: coverSize)
        
        let textX = coverThumb.frame.maxX + 12
        let textWidth = w - textX - margin - 24
        
        storyTitleLabel.frame = CGRect(x: textX, y: 20, width: textWidth, height: 20)
        writerLabel.frame = CGRect(x: textX, y: storyTitleLabel.frame.maxY + 2, width: textWidth, height: 16)
        activeChapterLabel.frame = CGRect(x: textX, y: writerLabel.frame.maxY + 2, width: textWidth, height: 16)
        
        orderToggle.frame = CGRect(x: w - margin - 16, y: (headerHeight - 16) / 2, width: 16, height: 16)
        
        // 列表
        tableView.frame = CGRect(x: 0, y: bookHeader.frame.maxY, width: w, height: frame.height - bookHeader.frame.maxY)
    }
    
    // MARK: - UITableViewDataSource
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bookModel?.chapterListModels.count ?? 0
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = ReaderCatalogueCell.cell(tableView)
        
        guard let bookModel = bookModel else { return cell }
        
        let chapterListModel = bookModel.chapterListModels[indexPath.row]
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        // 章节名
        cell.chapterTitleLabel.text = chapterListModel.name
        
        // 分割线颜色
        cell.divider.backgroundColor = themeColors.separatorTint
        
        // 阅读记录高亮
        if bookModel.recordModel.chapterModel.id == chapterListModel.id {
            cell.chapterTitleLabel.textColor = themeColors.textStrong
        } else {
            cell.chapterTitleLabel.textColor = themeColors.textBody
        }
        
        // cell 背景透明
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let bookModel = bookModel else { return }
        let chapterListModel = bookModel.chapterListModels[indexPath.row]
        onChapterChosen?(chapterListModel)
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        backgroundColor = colors.fillSheet
        storyTitleLabel.textColor = colors.textBody
        writerLabel.textColor = colors.textFaint
        activeChapterLabel.textColor = colors.textFaint
        orderToggle.tintColor = colors.textBody
        tableView.reloadData()
    }
}
