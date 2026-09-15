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
    private let blockHeight: CGFloat = 74

    private let lockIcon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let leftLine = UIView()
    private let rightLine = UIView()
    private let leftLineGradient = CAGradientLayer()
    private let rightLineGradient = CAGradientLayer()

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

        lockIcon.contentMode = .scaleAspectFit
        contentView.addSubview(lockIcon)

        leftLine.layer.addSublayer(leftLineGradient)
        rightLine.layer.addSublayer(rightLineGradient)
        leftLineGradient.startPoint = CGPoint(x: 0, y: 0.5)
        leftLineGradient.endPoint = CGPoint(x: 1, y: 0.5)
        rightLineGradient.startPoint = CGPoint(x: 0, y: 0.5)
        rightLineGradient.endPoint = CGPoint(x: 1, y: 0.5)
        contentView.addSubview(leftLine)
        contentView.addSubview(rightLine)

        titleLabel.text = ReaderEnvironment.strings.bookmarkLocked
        titleLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)

        subtitleLabel.text = ReaderEnvironment.strings.bookmarkLockedSub
        subtitleLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        subtitleLabel.textAlignment = .center
        contentView.addSubview(subtitleLabel)

        refresh()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 刷新配色与锁切图(随主题)
    open func refresh() {
        let colors = ReaderConfiguration.shared().currentThemeColors
        lockIcon.image = ReaderEnvironment.images.bookmarkLockSeal(ReaderConfiguration.shared().themeType)
        titleLabel.textColor = colors.textT1
        subtitleLabel.textColor = colors.textT3
        let lineColor = colors.dividerLine
        leftLineGradient.colors = [lineColor.withAlphaComponent(0).cgColor, lineColor.cgColor]
        rightLineGradient.colors = [lineColor.cgColor, lineColor.withAlphaComponent(0).cgColor]
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
        let top = max(0, (h - blockHeight) / 2)

        lockIcon.frame = CGRect(x: (w - iconSize) / 2, y: top, width: iconSize, height: iconSize)

        titleLabel.sizeToFit()
        let titleW = min(titleLabel.frame.width, w - margin * 2)
        titleLabel.frame = CGRect(x: (w - titleW) / 2,
                                  y: lockIcon.frame.maxY + iconTitleGap,
                                  width: titleW,
                                  height: titleH)

        let lineH: CGFloat = 1
        let lineY = titleLabel.frame.midY - lineH / 2
        let lineGap: CGFloat = 12
        let leftMaxX = titleLabel.frame.minX - lineGap
        let rightMinX = titleLabel.frame.maxX + lineGap
        leftLine.frame = CGRect(x: margin, y: lineY, width: max(0, leftMaxX - margin), height: lineH)
        rightLine.frame = CGRect(x: rightMinX, y: lineY, width: max(0, w - margin - rightMinX), height: lineH)

        subtitleLabel.frame = CGRect(x: margin,
                                     y: titleLabel.frame.maxY + titleSubtitleGap,
                                     width: w - margin * 2,
                                     height: subtitleH)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftLineGradient.frame = leftLine.bounds
        rightLineGradient.frame = rightLine.bounds
        CATransaction.commit()
    }
}
