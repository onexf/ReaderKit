//
//  ReaderBookmarkSectionHeader.swift
//  ReaderKit
//
//  书签 Tab 章节分组头部视图
//  结构:章节名(单行省略) + 锁图标(锁定章节展示)
//  注:章节 name 本身已包含 "Chapter N" 前缀,直接整体展示,不再额外拼接序号
//

import UIKit

open class ReaderBookmarkSectionHeader: UITableViewHeaderFooterView {

    /// 章节标题(完整章节名)
    private var headingLabel: UILabel!

    /// 锁定图标(锁定章节展示)
    private var lockGlyph: UIImageView!

    /// 是否锁定
    private var isLocked: Bool = false

    public class func header(_ tableView: UITableView) -> ReaderBookmarkSectionHeader {
        let id = "ReaderBookmarkSectionHeader"
        if let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: id) as? ReaderBookmarkSectionHeader {
            return header
        }
        return ReaderBookmarkSectionHeader(reuseIdentifier: id)
    }

    public override init(reuseIdentifier: String?) {

        super.init(reuseIdentifier: reuseIdentifier)

        addSubviews()
    }

    private func addSubviews() {

        let themeColors = ReaderConfiguration.shared().currentThemeColors

        let bg = UIView()
        bg.backgroundColor = .clear
        backgroundView = bg

        // 章节标题
        headingLabel = UILabel()
        headingLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        headingLabel.textColor = themeColors.textBody
        headingLabel.numberOfLines = 1
        headingLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(headingLabel)

        // 锁图标(锁定章节展示,着色用主题强调色 textStrong,与目录页锁定章节一致)
        lockGlyph = UIImageView()
        lockGlyph.image = ReaderEnvironment.images.chapterLocked()?.withRenderingMode(.alwaysTemplate)
        lockGlyph.tintColor = themeColors.textStrong
        lockGlyph.contentMode = .scaleAspectFit
        lockGlyph.isHidden = true
        contentView.addSubview(lockGlyph)
    }

    /// 配置分组头
    open func configure(group: ReaderBookmarkCluster) {

        let themeColors = ReaderConfiguration.shared().currentThemeColors
        isLocked = group.isLocked

        headingLabel.text = group.chapterCaption
        // 锁定提示由浮层(渐变 + 锁 + 文案)统一承载,header 不再单独显示锁图标
        lockGlyph.isHidden = true

        // 锁定章节标题置灰
        headingLabel.textColor = group.isLocked ? themeColors.textFaint : themeColors.textBody

        setNeedsLayout()
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        let margin: CGFloat = 20
        let w = contentView.bounds.width

        // 对照 Figma 11957-12505:章节名上方留 12(距上方分割线),标题行高 24,下方留 12(距书签)
        // header 总高 = 12 + 24 + 12 = 48
        let titleTop: CGFloat = 12
        let titleHeight: CGFloat = 24

        // 锁图标(右侧,与标题文本垂直居中)
        let lockSize: CGFloat = 16
        var rightLimit = w - margin
        if !lockGlyph.isHidden {
            lockGlyph.frame = CGRect(x: w - margin - lockSize, y: titleTop + (titleHeight - lockSize) / 2, width: lockSize, height: lockSize)
            rightLimit = lockGlyph.frame.minX - 8
        }

        // 标题(顶部留 12)
        headingLabel.frame = CGRect(x: margin, y: titleTop, width: max(0, rightLimit - margin), height: titleHeight)
    }

    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        headingLabel.textColor = isLocked ? colors.textFaint : colors.textBody
        lockGlyph.tintColor = colors.textStrong
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
