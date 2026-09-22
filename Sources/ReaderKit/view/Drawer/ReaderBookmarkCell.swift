//
//  ReaderBookmarkCell.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/12.
//

import UIKit

/// 书签 cell 内容高度(对照 Figma 11957-12505):摘录 44 + 间距 4 + 时间 16 = 64
public let READER_MARK_CELL_CONTENT_HEIGHT: CGFloat = 64

/// 书签 cell 高度 = 内容 64 + 底部 12 间距
/// (用于同一章节分组内"非末条"书签之间的 12px 间隔;末条书签用 READER_MARK_CELL_CONTENT_HEIGHT,紧贴分组分割线)
public let READER_MARK_CELL_HEIGHT: CGFloat = READER_MARK_CELL_CONTENT_HEIGHT + 12

/// 书签 cell(章节标题已上移到 section header,本 cell 仅展示单条书签)
///
/// 结构(对照 Figma 书签面板分组内 cell):
/// - 左侧:书签徽标(圆角方块 + 书签图标)
/// - 右侧:2 行摘录 + meta 行(仅时间)
/// - 底部:分割线
open class ReaderBookmarkCell: UITableViewCell {

    /// 书签徽标背景
    private var iconBadge: UIView!

    /// 书签徽标图标
    private var badgeGlyph: UIImageView!

    /// 摘录内容(最多 2 行)
    private var snippetLabel: UILabel!

    /// 时间
    private var createdAtLabel: UILabel!


    public class func cell(_ tableView: UITableView) -> ReaderBookmarkCell {

        var cell = tableView.dequeueReusableCell(withIdentifier: "ReaderBookmarkCell")

        if cell == nil {

            cell = ReaderBookmarkCell(style: UITableViewCell.CellStyle.default, reuseIdentifier: "ReaderBookmarkCell")
        }

        return cell as! ReaderBookmarkCell
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        backgroundColor = UIColor.clear

        addSubviews()
    }

    private func addSubviews() {

        let themeColors = ReaderConfiguration.shared().currentThemeColors

        // 书签徽标背景(圆角方块)
        iconBadge = UIView()
        iconBadge.backgroundColor = themeColors.fill
        iconBadge.layer.cornerRadius = 9
        contentView.addSubview(iconBadge)

        // 书签徽标图标
        badgeGlyph = UIImageView()
        badgeGlyph.image = ReaderEnvironment.images.bookmarkBadge()?.withRenderingMode(.alwaysTemplate)
        badgeGlyph.tintColor = themeColors.textStrong
        badgeGlyph.contentMode = .scaleAspectFit
        iconBadge.addSubview(badgeGlyph)

        // 摘录内容
        snippetLabel = UILabel()
        snippetLabel.font = ReaderEnvironment.fonts.uiRegular(14)
        snippetLabel.textColor = themeColors.textSubtle
        snippetLabel.numberOfLines = 2
        contentView.addSubview(snippetLabel)

        // 时间
        createdAtLabel = UILabel()
        createdAtLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        createdAtLabel.textColor = themeColors.textFaint
        contentView.addSubview(createdAtLabel)
    }

    /// 配置 cell
    /// - Parameters:
    ///   - mark: 书签
    ///   - progress: 全书阅读进度(已不展示,保留参数兼容调用)
    ///   - isLocked: 所属章节是否锁定(锁定渐隐由 markView 区域蒙层统一处理,cell 内不做处理)
    open func configure(mark: ReaderBookmarkModel, progress: Float, isLocked: Bool) {


        snippetLabel.text = mark.content
        // 添加时间固定展示为 yyyy-MM-dd HH:mm
        createdAtLabel.text = readerClockText("yyyy-MM-dd HH:mm", Date(timeIntervalSince1970: TimeInterval(mark.time.intValue)))

        adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)

        setNeedsLayout()
    }

    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderTintPalette) {

        iconBadge.backgroundColor = colors.fill
        badgeGlyph.tintColor = colors.textStrong
        snippetLabel.textColor = colors.textSubtle
        createdAtLabel.textColor = colors.textFaint
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        let w = frame.size.width
        let margin: CGFloat = 20
        let rowTop: CGFloat = 0

        // 书签徽标:18x18,圆角9,内部图标 12x12 居中
        let badgeSize: CGFloat = 18
        let iconSize: CGFloat = 12
        iconBadge.frame = CGRect(x: margin, y: rowTop + 3, width: badgeSize, height: badgeSize)
        badgeGlyph.frame = CGRect(x: (badgeSize - iconSize) / 2, y: (badgeSize - iconSize) / 2, width: iconSize, height: iconSize)

        // 右侧内容:摘录 + meta 行
        let rightX = iconBadge.frame.maxX + 8
        let rightW = w - rightX - margin

        // 摘录:最多 2 行,行高约 22,共 44
        let excerptH: CGFloat = 44
        snippetLabel.frame = CGRect(x: rightX, y: rowTop, width: rightW, height: excerptH)

        // meta 行:仅时间(摘录下方间距 4,对齐设计)
        let metaY = snippetLabel.frame.maxY + 4
        let metaH: CGFloat = 16
        createdAtLabel.frame = CGRect(x: rightX, y: metaY, width: rightW, height: metaH)
    }

    public required init?(coder aDecoder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }
}
