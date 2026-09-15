//
//  ReaderMenuCataloguePanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/24.
//

import UIKit

open class ReaderMenuCataloguePanel: UIView, UITableViewDelegate, UITableViewDataSource {
    
    /// 数据源
    open var readModel: ReaderBookModel! {
        didSet {
            reviseBookInfo()
            tableView.reloadData()
            scrollToActiveChapter()
        }
    }
    
    /// 选中章节回调
    open var onChapterSelected: ((ReaderChapterListItemModel) -> Void)?
    
    /// 顶部信息视图
    private var headerView: UIView!
    private var bookCoverImageView: UIImageView!
    private var bookTitleLabel: UILabel!
    private var authorLabel: UILabel!
    private var currentChapterLabel: UILabel!
    private var arrowButton: UIButton!
    
    /// 列表
    private var tableView: UITableView!
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onChapterListUpdated),
                                               name: .readerChapterListDidUpdate,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 后台目录补全有新章节合并时刷新列表（仅刷新数据，不打断用户当前浏览位置）。
    @objc private func onChapterListUpdated() {
        guard readModel != nil else { return }
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
        headerView = UIView()
        headerView.backgroundColor = .clear
        addSubview(headerView)
        
        // 书籍封面
        bookCoverImageView = UIImageView()
        bookCoverImageView.contentMode = .scaleAspectFill
        bookCoverImageView.clipsToBounds = true
        bookCoverImageView.image = ReaderEnvironment.images.bookCoverPlaceholder()
        bookCoverImageView.layer.cornerRadius = 8
        headerView.addSubview(bookCoverImageView)
        
        // 书名
        bookTitleLabel = UILabel()
        bookTitleLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        bookTitleLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textT1
        bookTitleLabel.numberOfLines = 1
        headerView.addSubview(bookTitleLabel)
        
        // 作者
        authorLabel = UILabel()
        authorLabel.font = ReaderEnvironment.fonts.uiRegular(14)
        authorLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textT3
        authorLabel.numberOfLines = 1
        headerView.addSubview(authorLabel)
        
        // 当前章节
        currentChapterLabel = UILabel()
        currentChapterLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        currentChapterLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textT3
        currentChapterLabel.numberOfLines = 1
        headerView.addSubview(currentChapterLabel)
        
        // 箭头按钮（使用 SF Symbol）
        arrowButton = UIButton(type: .custom)
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        arrowButton.setImage(UIImage(systemName: "chevron.right", withConfiguration: chevronConfig), for: .normal)
        arrowButton.tintColor = ReaderConfiguration.shared().currentThemeColors.textT1
        arrowButton.isUserInteractionEnabled = false
        headerView.addSubview(arrowButton)
        
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
    open func reviseBookInfo() {
        guard let readModel = readModel else { return }
        
        // 设置书名
        bookTitleLabel.text = readModel.bookName
        authorLabel.text = readModel.author
        
        // 设置当前章节信息（安全访问）
        if let recordModel = readModel.recordModel,
           let chapterModel = recordModel.chapterModel {
            currentChapterLabel.text = ReaderEnvironment.strings.chapter + " \(chapterModel.priority.intValue)"
        } else {
            currentChapterLabel.text = ReaderEnvironment.strings.chapter + " 1"
        }
        
        // 如果有封面图片URL，可以加载
        // bookCoverImageView.kf.setImage(with: URL(string: readModel.coverURL))
    }
    
    /// 滚动到当前章节
    private func scrollToActiveChapter() {
        guard let readModel = readModel, !readModel.chapterListModels.isEmpty else { return }
        
        if let index = readModel.chapterListModels.firstIndex(where: { $0.id == readModel.recordModel.chapterModel.id }) {
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
        headerView.frame = CGRect(x: 0, y: 0, width: w, height: headerHeight)
        
        // 布局顶部信息
        let margin: CGFloat = 20
        let coverSize: CGFloat = 48
        
        bookCoverImageView.frame = CGRect(x: margin, y: (headerHeight - coverSize) / 2, width: coverSize, height: coverSize)
        
        let textX = bookCoverImageView.frame.maxX + 12
        let textWidth = w - textX - margin - 24
        
        bookTitleLabel.frame = CGRect(x: textX, y: 20, width: textWidth, height: 20)
        authorLabel.frame = CGRect(x: textX, y: bookTitleLabel.frame.maxY + 2, width: textWidth, height: 16)
        currentChapterLabel.frame = CGRect(x: textX, y: authorLabel.frame.maxY + 2, width: textWidth, height: 16)
        
        arrowButton.frame = CGRect(x: w - margin - 16, y: (headerHeight - 16) / 2, width: 16, height: 16)
        
        // 列表
        tableView.frame = CGRect(x: 0, y: headerView.frame.maxY, width: w, height: frame.height - headerView.frame.maxY)
    }
    
    // MARK: - UITableViewDataSource
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return readModel?.chapterListModels.count ?? 0
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = ReaderCatalogueCell.cell(tableView)
        
        guard let readModel = readModel else { return cell }
        
        let chapterListModel = readModel.chapterListModels[indexPath.row]
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        // 章节名
        cell.chapterName.text = chapterListModel.name
        
        // 分割线颜色
        cell.spaceLine.backgroundColor = themeColors.dividerLine
        
        // 阅读记录高亮
        if readModel.recordModel.chapterModel.id == chapterListModel.id {
            cell.chapterName.textColor = themeColors.textT0
        } else {
            cell.chapterName.textColor = themeColors.textT1
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
        
        guard let readModel = readModel else { return }
        let chapterListModel = readModel.chapterListModels[indexPath.row]
        onChapterSelected?(chapterListModel)
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        backgroundColor = colors.fillPopup
        bookTitleLabel.textColor = colors.textT1
        authorLabel.textColor = colors.textT3
        currentChapterLabel.textColor = colors.textT3
        arrowButton.tintColor = colors.textT1
        tableView.reloadData()
    }
}
