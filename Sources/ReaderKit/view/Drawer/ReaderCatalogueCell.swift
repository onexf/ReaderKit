//
//  ReaderCatalogueCell.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

/// 阅读器目录抽屉的章节行
///
/// 设计稿结构（章节信息为一个 row，子项间距 10）：
/// `[当前章指示条 4×16] 10 [「Chapter」 2 序号(定宽 18 居中)] 10 [章节标题 撑满] 10 [锁 18×18]`
/// 指示条只在当前章出现、锁只在锁定章出现，两者缺席时对应间距一并消失。
/// 序号定宽 18 是为了 1~99 章的标题起始 x 对齐。
open class ReaderCatalogueCell: UITableViewCell {

    // MARK: - 设计稿尺寸

    public static let identifier = "ReaderCatalogueCell"

    /// 行内容高度（设计稿 Reader/List Item：14pt × 1.3 行高）
    public static let contentHeight: CGFloat = 18

    /// 行间距（设计稿「目录list」column gap 20）
    public static let rowSpacing: CGFloat = 20

    /// cell 高度 = 内容 + 行间距，内容顶部对齐，间距留在下方，
    /// 这样首行内容能与分割线下方 12pt 处严格对齐（Figma 的 gap 只作用于相邻项之间）
    public static let rowHeight: CGFloat = contentHeight + rowSpacing

    /// 左右边距（抽屉容器 padding）
    private let horizontalMargin: CGFloat = 20

    /// row 内各子项间距
    private let itemSpacing: CGFloat = 10

    /// 「Chapter」与序号之间的间距
    private let numberSpacing: CGFloat = 2

    /// 序号列最小宽度
    ///
    /// 设计稿给的是定宽 18（居中），目的是让各行标题的起始 x 对齐。
    /// 长篇动辄上千章，18 装不下四位数，所以实际列宽由列表按全书最大章节号统一算出，
    /// 这里只作为下限，保证短篇仍与设计稿一致。
    public static let numberColumnMinWidth: CGFloat = 18

    /// 当前章指示条
    private let indicatorSize = CGSize(width: 4, height: 16)

    /// 锁图标尺寸
    private let lockSize: CGFloat = 18

    // MARK: - 子视图

    /// 章节标题（`ReaderMenuCataloguePanel` 仍在直接读写，保持对外可见）
    public private(set) var chapterName: UILabel!

    /// 「Chapter」前缀
    private var chapterPrefix: UILabel!

    /// 章节序号
    private var chapterNumber: UILabel!

    /// 当前章指示条
    private var indicator: UIView!

    /// 锁定图标
    private var lockIcon: UIImageView!

    /// 分割线：新稿目录行之间不再有分割线，这里只为兼容仍在引用它的
    /// `ReaderMenuCataloguePanel`（已无入口的旧底部目录面板）而保留，不加入视图树
    public private(set) var spaceLine: UIView!

    // MARK: - 状态

    /// 是否为当前阅读章节
    private var isCurrentChapter: Bool = false

    /// 是否锁定
    private var isLockedChapter: Bool = false

    /// 序号列宽度（由列表统一下发，保证所有行的标题起点对齐）
    private var numberColumnWidth: CGFloat = ReaderCatalogueCell.numberColumnMinWidth

    public class func cell(_ tableView: UITableView) -> ReaderCatalogueCell {

        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)

        if cell == nil {

            cell = ReaderCatalogueCell(style: .default, reuseIdentifier: identifier)
        }

        return cell as! ReaderCatalogueCell
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        backgroundColor = .clear

        addSubviews()
    }

    private func addSubviews() {

        // 当前章指示条：4×16，圆角 2
        indicator = UIView()
        indicator.layer.cornerRadius = 2
        indicator.isHidden = true
        contentView.addSubview(indicator)

        // 「Chapter」前缀
        chapterPrefix = UILabel()
        chapterPrefix.text = ReaderEnvironment.strings.chapter
        contentView.addSubview(chapterPrefix)

        // 章节序号：定宽居中
        chapterNumber = UILabel()
        chapterNumber.textAlignment = .center
        contentView.addSubview(chapterNumber)

        chapterName = UILabel()
        chapterName.numberOfLines = 1
        chapterName.lineBreakMode = .byTruncatingTail
        contentView.addSubview(chapterName)

        // 锁定图标：染色跟随行文字色
        lockIcon = UIImageView()
        lockIcon.image = UIImage(named: "novel_directory_lock_outline")?.withRenderingMode(.alwaysTemplate)
        lockIcon.isHidden = true
        contentView.addSubview(lockIcon)

        // 兼容用占位，不参与布局
        spaceLine = UIView()
        spaceLine.isHidden = true
    }

    // MARK: - 数据填充

    /// 配置一行章节
    /// - Parameters:
    ///   - title: 章节标题
    ///   - number: 展示用章节序号（从 1 开始）
    ///   - isCurrent: 是否当前阅读章节
    ///   - isLocked: 是否锁定
    ///   - numberColumnWidth: 序号列宽度（全列表统一）
    ///   - colors: 当前阅读器主题色
    open func configure(title: String?,
                   number: Int,
                   isCurrent: Bool,
                   isLocked: Bool,
                   numberColumnWidth: CGFloat,
                   colors: ReaderThemeColors) {

        isCurrentChapter = isCurrent
        isLockedChapter = isLocked
        self.numberColumnWidth = numberColumnWidth

        chapterName.text = title
        chapterNumber.text = "\(number)"

        // 设计稿：当前章 Regular + 主文字色；锁定章 Light + 辅助文字色；常态 Light + 次要文字色
        let font: UIFont = isCurrent ? ReaderEnvironment.fonts.uiRegular(14) : ReaderEnvironment.fonts.uiLight(14)
        let textColor: UIColor
        if isCurrent {
            textColor = colors.textT1
        } else if isLocked {
            textColor = colors.textT3
        } else {
            textColor = colors.textT2
        }

        chapterPrefix.font = font
        chapterNumber.font = font
        chapterName.font = font
        chapterPrefix.textColor = textColor
        chapterNumber.textColor = textColor
        chapterName.textColor = textColor

        indicator.isHidden = !isCurrent
        indicator.backgroundColor = colors.textT1

        lockIcon.isHidden = !isLocked
        lockIcon.tintColor = textColor

        setNeedsLayout()
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        let w = frame.size.width
        let contentHeight = ReaderCatalogueCell.contentHeight

        // 当前章指示条：左边距 20，与首行文字垂直居中
        indicator.frame = CGRect(x: horizontalMargin,
                                 y: (contentHeight - indicatorSize.height) / 2,
                                 width: indicatorSize.width,
                                 height: indicatorSize.height)

        // 「Chapter」+ 序号：指示条存在时整体右移（指示条宽 + 间距）
        let prefixX = isCurrentChapter ? indicator.frame.maxX + itemSpacing : horizontalMargin
        let prefixWidth = ceil(chapterPrefix.sizeThatFits(CGSize(width: w, height: contentHeight)).width)
        chapterPrefix.frame = CGRect(x: prefixX, y: 0, width: prefixWidth, height: contentHeight)

        chapterNumber.frame = CGRect(x: chapterPrefix.frame.maxX + numberSpacing,
                                     y: 0,
                                     width: numberColumnWidth,
                                     height: contentHeight)

        // 锁图标：右边距 20，与首行文字垂直居中
        lockIcon.frame = CGRect(x: w - horizontalMargin - lockSize,
                                y: (contentHeight - lockSize) / 2,
                                width: lockSize,
                                height: lockSize)

        // 章节标题：撑满序号与锁（或右边距）之间的空间
        let titleX = chapterNumber.frame.maxX + itemSpacing
        let titleMaxX = isLockedChapter ? lockIcon.frame.minX - itemSpacing : w - horizontalMargin
        chapterName.frame = CGRect(x: titleX, y: 0, width: max(0, titleMaxX - titleX), height: contentHeight)
    }

    public required init?(coder aDecoder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }
}
