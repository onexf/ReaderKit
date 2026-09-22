//
//  ReaderDrawerView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/08/05.
//

import UIKit

/// leftView 代理协议
public protocol ReaderDrawerDelegate: AnyObject {
    /// 点击书籍信息区域，跳转到详情页
    func readLeftViewDidClickBookInfo(_ leftView: ReaderDrawerView)
}

/// 抽屉右侧露出的遮罩宽度
///
/// 设计稿在 375 宽下抽屉宽 271、右侧露出 104 的遮罩点击区。这里固定露出宽度而不是固定
/// 抽屉宽度：参考宽度下结果恰为 271，大屏上抽屉随屏宽变宽，露出的「点击关闭」区域保持一致。
public let READER_LEFT_VIEW_PEEK_WIDTH: CGFloat = 104

/// leftView 宽高度
public let READER_LEFT_VIEW_WIDTH: CGFloat = ReaderScreenMetrics.screenWidth - READER_LEFT_VIEW_PEEK_WIDTH

public let READER_LEFT_VIEW_HEIGHT: CGFloat = ReaderScreenMetrics.screenHeight

/// 抽屉圆角（设计稿 borderRadius 0/12/0/0，只有右上角）
public let READER_LEFT_VIEW_CORNER_RADIUS: CGFloat = 12

/// 阅读器目录抽屉
///
/// 设计稿结构（column，padding 32/20/0，块间距 12）：
/// `书籍信息(封面 + 书名 + 作者 → 间距 16 → 章节总数) / 分割线 / 目录list`
open class ReaderDrawerView: UIView {

    // MARK: - 设计稿尺寸

    /// 左右内边距
    private let horizontalMargin: CGFloat = 20

    /// 顶部内边距（设计稿值，从抽屉顶边算）
    private let topPadding: CGFloat = 32

    // 说明：设计稿的 32 是在「隐藏状态栏、无刘海」的 375×812 画板上量的，抽屉贴屏幕顶边
    // 铺满时直接用 32 会让书名被刘海 / 灵动岛压住。
    // safeAreaInsets.top 就是缺口高度本身（状态栏隐藏后依然上报，刘海机型 44~47、
    // 灵动岛机型 59），所以内容起点取「设计稿 32」与「缺口高度」的较大值即可：
    // 缺口下沿本身就是视觉分界，不需要再额外留白；无刘海机型结果仍是设计稿的 32。
    // 见 layoutSubviews 里的 contentTop。

    /// 书籍信息 / 分割线 / 目录列表 之间的间距
    private let sectionSpacing: CGFloat = 12

    /// 封面尺寸
    private let coverSize = CGSize(width: 45, height: 60)

    /// 封面圆角
    private let coverCornerRadius: CGFloat = 8

    /// 封面与右侧文字列的间距
    private let coverTextSpacing: CGFloat = 10

    /// 书名与作者的间距
    private let titleAuthorSpacing: CGFloat = 10

    /// 书名占位高度（Reader/List Title 行高 24）
    private let titleHeight: CGFloat = 24

    /// 作者占位高度（设计稿固定 21）
    private let authorHeight: CGFloat = 21

    /// 书籍信息与章节总数的间距
    private let bookInfoSpacing: CGFloat = 16

    /// 章节总数占位高度（12pt 行高 18）
    private let chapterCountHeight: CGFloat = 18

    /// 分割线高度
    private let dividerHeight: CGFloat = 1

    // MARK: - 子视图

    /// 代理
    open weak var delegate: ReaderDrawerDelegate?

    /// 顶部书籍信息区域（整块可点，跳详情）
    private var bookHeader: UIControl!
    private var coverThumb: UIImageView!
    private var storyTitleLabel: UILabel!
    private var writerLabel: UILabel!

    /// 章节总数
    private var chapterCountLabel: UILabel!

    /// 分割线
    private var divider: UIView!

    /// 目录
    public private(set) var catalogueList: ReaderCatalogueView!

    /// 书签
    ///
    /// 新版目录稿里没有 Contents / Bookmark 切换 tab，书签入口暂时没有落点，
    /// 这里保留视图与数据链路（书签的增删仍会 `reloadMarks()`），恒定隐藏、不参与展示，
    /// 等书签侧的设计稿确定入口后直接接回，避免现在把整条书签链路拆掉。
    public private(set) var markView: ReaderBookmarkListView!

    public override init(frame: CGRect) {

        super.init(frame: frame)

        addSubviews()
    }

    private func addSubviews() {

        let themeColors = ReaderConfiguration.shared().currentThemeColors

        // 顶部书籍信息区域：只做信息展示，不可点击
        //
        // TODO: 【1.0 无书籍详情页】
        //   接入方关闭了书名页，目录抽屉这块书籍信息是详情页残留的最后一个入口，
        //   一并关掉，否则用户从这里仍能进到不该出现的页面。
        //   注意：该取舍由接入方的产品形态决定，恢复展示时接回即可。
        //   恢复时：取消下面 addAction 的注释，并去掉 isUserInteractionEnabled = false。
        //   对应的回调链仍保留：`handleBookInfoTap` → `readLeftViewDidClickBookInfo`
        //   → 由接入方跳转到书籍详情页。
        bookHeader = UIControl()
        bookHeader.backgroundColor = .clear
        // 置为不可交互而非仅移除 target，避免 UIControl 仍吃掉触摸并给出高亮反馈
        bookHeader.isUserInteractionEnabled = false
//        bookHeader.addAction(UIAction { [weak self] _ in self?.handleBookInfoTap() }, for: .touchUpInside)
        addSubview(bookHeader)

        // 书籍封面
        coverThumb = UIImageView()
        coverThumb.contentMode = .scaleAspectFill
        coverThumb.clipsToBounds = true
        coverThumb.image = ReaderEnvironment.images.coverPlaceholder()
        coverThumb.layer.cornerRadius = coverCornerRadius
        bookHeader.addSubview(coverThumb)

        // 书名
        storyTitleLabel = UILabel()
        storyTitleLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        storyTitleLabel.textColor = themeColors.textBody
        storyTitleLabel.numberOfLines = 1
        bookHeader.addSubview(storyTitleLabel)

        // 作者
        writerLabel = UILabel()
        writerLabel.font = ReaderEnvironment.fonts.uiLight(14)
        writerLabel.textColor = themeColors.textFaint
        writerLabel.numberOfLines = 1
        bookHeader.addSubview(writerLabel)

        // 章节总数
        chapterCountLabel = UILabel()
        chapterCountLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        chapterCountLabel.textColor = themeColors.textFaint
        chapterCountLabel.numberOfLines = 1
        addSubview(chapterCountLabel)

        // 分割线：设计稿逐主题取的是控件填充色（比 separatorTint 更实一档）
        divider = UIView()
        divider.backgroundColor = themeColors.fillControl
        addSubview(divider)

        // 目录
        catalogueList = ReaderCatalogueView()
        addSubview(catalogueList)

        // 书签（暂无入口，恒定隐藏）
        markView = ReaderBookmarkListView()
        markView.isHidden = true
        addSubview(markView)

        // 更新当前UI
        updateUI()
    }

    /// 点击书籍信息区域，回调给阅读控制器
    ///
    /// 1.0 无书籍详情页，`bookHeader` 已置为不可交互，此方法当前不会被触发。
    /// 保留实现与回调链，恢复详情页时只需在 `addSubviews()` 里放开 addAction。
    private func handleBookInfoTap() {
        delegate?.readLeftViewDidClickBookInfo(self)
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()

        let w = frame.width
        let safeInsets = ReaderScreenMetrics.safeAreaInsets

        // 内容起点：贴在刘海 / 灵动岛下沿（无刘海机型即设计稿的 32）
        let contentTop = max(topPadding, safeInsets.top)

        // MARK: 书籍信息：封面 45×60，右侧文字列（书名 + 作者）在封面高度内垂直居中
        bookHeader.frame = CGRect(x: horizontalMargin,
                                  y: contentTop,
                                  width: w - horizontalMargin * 2,
                                  height: coverSize.height)

        coverThumb.frame = CGRect(origin: .zero, size: coverSize)

        let textX = coverThumb.frame.maxX + coverTextSpacing
        let textWidth = bookHeader.frame.width - textX
        let textBlockHeight = titleHeight + titleAuthorSpacing + authorHeight
        let textY = (coverSize.height - textBlockHeight) / 2

        storyTitleLabel.frame = CGRect(x: textX, y: textY, width: textWidth, height: titleHeight)
        writerLabel.frame = CGRect(x: textX,
                                   y: storyTitleLabel.frame.maxY + titleAuthorSpacing,
                                   width: textWidth,
                                   height: authorHeight)

        // MARK: 章节总数：书籍信息下方 16
        chapterCountLabel.frame = CGRect(x: horizontalMargin,
                                         y: bookHeader.frame.maxY + bookInfoSpacing,
                                         width: w - horizontalMargin * 2,
                                         height: chapterCountHeight)

        // MARK: 分割线：章节总数下方 12
        divider.frame = CGRect(x: horizontalMargin,
                                 y: chapterCountLabel.frame.maxY + sectionSpacing,
                                 width: w - horizontalMargin * 2,
                                 height: dividerHeight)

        // MARK: 目录列表：分割线下方 12，向下铺到安全区上沿
        let listY = divider.frame.maxY + sectionSpacing
        let listHeight = frame.height - safeInsets.bottom - listY
        catalogueList.frame = CGRect(x: 0, y: listY, width: w, height: max(0, listHeight))
        markView.frame = catalogueList.frame
    }

    // MARK: - 数据填充

    /// 更新书籍信息
    open func reviseStoryInfo(storyName: String?, writer: String?, totalChapterCount: Int) {
        storyTitleLabel.text = storyName
        writerLabel.text = writer
        chapterCountLabel.text = ReaderEnvironment.strings.chapterCount(totalChapterCount)
    }

    /// 更新书封图片
    open func reviseBookOverlay(url: String?) {
        guard let urlString = url, !urlString.isEmpty else {
            return
        }
        let compressedURL = urlString.getImageCompressURL(width: Int(coverSize.width), heigth: Int(coverSize.height))
        ReaderEnvironment.images.loadRemoteImage(coverThumb,
                                                compressedURL,
                                                ReaderEnvironment.images.coverPlaceholder())
    }

    // MARK: - 主题换肤

    /// 刷新UI 例如: 日夜间可以根据需求判断修改目录背景颜色,文字颜色等等
    open func updateUI() {
        adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)
    }

    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        backgroundColor = colors.fillSheet

        // 书籍信息区域
        storyTitleLabel.textColor = colors.textBody
        writerLabel.textColor = colors.textFaint
        chapterCountLabel.textColor = colors.textFaint

        // 分割线
        divider.backgroundColor = colors.fillControl

        // 目录列表
        catalogueList.adoptThemeColors(colors)

        // 书签列表（暂无入口，仍随主题刷新，避免接回入口时出现旧配色）
        markView.adoptThemeColors(colors)
    }

    public required init?(coder aDecoder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }
}
