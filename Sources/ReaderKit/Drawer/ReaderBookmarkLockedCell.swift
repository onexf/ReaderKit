//
//  ReaderBookmarkLockedCell.swift
//  ReaderKit
//
//  锁定章节在书签列表中的提示 cell:锁图标 + Chapter locked + Subscribe to read more!
//  章节名展示在 section header,本 cell 只展示居中的锁定提示,不展示书签内容。
//  对照 Figma node 11766-52085 / 11766-51383。
//

import UIKit

open class ReaderBookmarkLockedCell: UITableViewCell {

    /// cell 高度
    public static let cellHeight: CGFloat = 100

    /// CTA 内容块高度(锁 24 + 间距 4 + 标题 24 + 间距 4 + 副标题 18)
    private let lockedRowHeight: CGFloat = 74

    private let lockGlyph = UIImageView()
    private let noticeLabel = UILabel()
    private let detailLabel = UILabel()
    private let leadingRule = UIView()
    private let trailingRule = UIView()
    private let leadingRuleGradient = CAGradientLayer()
    private let trailingRuleGradient = CAGradientLayer()

    public class func cell(_ tableView: UITableView) -> ReaderBookmarkLockedCell {
        let id = "ReaderBookmarkLockedCell"
        if let cell = tableView.dequeueReusableCell(withIdentifier: id) as? ReaderBookmarkLockedCell {
            return cell
        }
        return ReaderBookmarkLockedCell(style: .default, reuseIdentifier: id)
    }

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        lockGlyph.contentMode = .scaleAspectFit
        contentView.addSubview(lockGlyph)

        leadingRule.layer.addSublayer(leadingRuleGradient)
        trailingRule.layer.addSublayer(trailingRuleGradient)
        leadingRuleGradient.startPoint = CGPoint(x: 0, y: 0.5)
        leadingRuleGradient.endPoint = CGPoint(x: 1, y: 0.5)
        trailingRuleGradient.startPoint = CGPoint(x: 0, y: 0.5)
        trailingRuleGradient.endPoint = CGPoint(x: 1, y: 0.5)
        contentView.addSubview(leadingRule)
        contentView.addSubview(trailingRule)

        noticeLabel.text = ReaderEnvironment.strings.bookmarkLocked
        noticeLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        noticeLabel.textAlignment = .center
        contentView.addSubview(noticeLabel)

        detailLabel.text = ReaderEnvironment.strings.bookmarkLockedSub
        detailLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        detailLabel.textAlignment = .center
        contentView.addSubview(detailLabel)

        refresh()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 刷新配色与锁切图(随主题)
    open func refresh() {
        let colors = ReaderConfiguration.shared().currentThemeColors
        lockGlyph.image = ReaderEnvironment.images.bookmarkLockSeal(ReaderConfiguration.shared().themeType)
        noticeLabel.textColor = colors.textBody
        detailLabel.textColor = colors.textFaint
        let lineColor = colors.separatorTint
        leadingRuleGradient.colors = [lineColor.withAlphaComponent(0).cgColor, lineColor.cgColor]
        trailingRuleGradient.colors = [lineColor.cgColor, lineColor.withAlphaComponent(0).cgColor]
        setNeedsLayout()
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let margin: CGFloat = 20

        let iconSize: CGFloat = 24
        let titleH: CGFloat = 24
        let subtitleH: CGFloat = 18
        let iconTitleGap: CGFloat = 4
        let titleSubtitleGap: CGFloat = 4

        // 整块垂直居中
        let top = max(0, (h - lockedRowHeight) / 2)

        lockGlyph.frame = CGRect(x: (w - iconSize) / 2, y: top, width: iconSize, height: iconSize)

        noticeLabel.sizeToFit()
        let titleW = min(noticeLabel.frame.width, w - margin * 2)
        noticeLabel.frame = CGRect(x: (w - titleW) / 2,
                                  y: lockGlyph.frame.maxY + iconTitleGap,
                                  width: titleW,
                                  height: titleH)

        let lineH: CGFloat = 1
        let lineY = noticeLabel.frame.midY - lineH / 2
        let lineGap: CGFloat = 12
        let leftMaxX = noticeLabel.frame.minX - lineGap
        let rightMinX = noticeLabel.frame.maxX + lineGap
        leadingRule.frame = CGRect(x: margin, y: lineY, width: max(0, leftMaxX - margin), height: lineH)
        trailingRule.frame = CGRect(x: rightMinX, y: lineY, width: max(0, w - margin - rightMinX), height: lineH)

        detailLabel.frame = CGRect(x: margin,
                                     y: noticeLabel.frame.maxY + titleSubtitleGap,
                                     width: w - margin * 2,
                                     height: subtitleH)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leadingRuleGradient.frame = leadingRule.bounds
        trailingRuleGradient.frame = trailingRule.bounds
        CATransaction.commit()
    }
}
