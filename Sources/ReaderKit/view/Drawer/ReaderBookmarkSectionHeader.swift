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
    private var titleLabel: UILabel!

    /// 锁定图标(锁定章节展示)
    private var lockIcon: UIImageView!

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
        titleLabel = UILabel()
        titleLabel.font = ReaderEnvironment.fonts.uiMedium(16)
        titleLabel.textColor = themeColors.textT1
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        // 锁图标(锁定章节展示,着色用主题强调色 textT0,与目录页锁定章节一致)
        lockIcon = UIImageView()
        lockIcon.image = UIImage(named: "novel_directory_lock_outline")?.withRenderingMode(.alwaysTemplate)
        lockIcon.tintColor = themeColors.textT0
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.isHidden = true
        contentView.addSubview(lockIcon)
    }

    /// 配置分组头
    open func configure(group: ReaderBookmarkCluster) {

        let themeColors = ReaderConfiguration.shared().currentThemeColors
        isLocked = group.isLocked

        titleLabel.text = group.chapterName
        // 锁定提示由浮层(渐变 + 锁 + 文案)统一承载,header 不再单独显示锁图标
        lockIcon.isHidden = true

        // 锁定章节标题置灰
        titleLabel.textColor = group.isLocked ? themeColors.textT3 : themeColors.textT1

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
        if !lockIcon.isHidden {
            lockIcon.frame = CGRect(x: w - margin - lockSize, y: titleTop + (titleHeight - lockSize) / 2, width: lockSize, height: lockSize)
            rightLimit = lockIcon.frame.minX - 8
        }

        // 标题(顶部留 12)
        titleLabel.frame = CGRect(x: margin, y: titleTop, width: max(0, rightLimit - margin), height: titleHeight)
    }

    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        titleLabel.textColor = isLocked ? colors.textT3 : colors.textT1
        lockIcon.tintColor = colors.textT0
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
