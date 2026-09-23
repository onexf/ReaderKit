//
//  ReaderMenuTabRail.swift
//  ReaderKit
//
//  Created by Kiro on 2026/04/01.
//

import UIKit

/// 底部按钮栏代理协议
public protocol ReaderMenuTabRailDelegate: AnyObject {
    /// 点击目录按钮
    func bottomTabBarDidClickCatalogue(_ tabBar: ReaderMenuTabRail)
    /// 点击日/夜间切换按钮
    func bottomTabBarDidClickNightMode(_ tabBar: ReaderMenuTabRail)
    /// 点击设置按钮
    func bottomTabBarDidClickSetting(_ tabBar: ReaderMenuTabRail)
}

/// 阅读器底部按钮栏（目录 / 日夜间 / 设置），供 FuncView 和 LeftView 共用
open class ReaderMenuTabRail: UIView {

    // MARK: - 设计稿尺寸

    /// tab 区顶部留白
    private let topPadding: CGFloat = 20

    /// 容器左右内边距
    private let horizontalMargin: CGFloat = 20

    /// 单个 item 高度：12 上下内边距 + 24 图标 + 2 间距 + 14 文字
    private let itemHeight: CGFloat = 64

    /// 图标尺寸
    private let iconSize: CGFloat = 24

    /// 图标与文字间距
    private let iconTitleSpacing: CGFloat = 2

    /// 文字占位高度（与 uiLight(10) 行高对齐）
    private let titleHeight: CGFloat = 14

    open weak var delegate: ReaderMenuTabRailDelegate?

    /// 当前是否为夜间模式（仅控制图标显示，不执行切换逻辑）
    open var isDarkTheme: Bool = false {
        didSet { reviseNightVariantBtn() }
    }

    // MARK: - 按钮

    public private(set) var catalogueTab: UIButton!
    public private(set) var themeToggleButton: UIButton!
    public private(set) var settingsTab: UIButton!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI 搭建

    private func configureViews() {
        let colors = ReaderConfiguration.shared().currentThemeColors
        backgroundColor = colors.fillSheet

        let iconColor = colors.iconStandard

        // 目录按钮：暂不设选中态。设计稿没给「目录选中」的图，
        // 原先资源里那张实心圆角方块与常态的文档轮廓不是同一套形状语言，不能拿来当选中态，
        // 该资源已在个人中心改版时移除，需要选中态时请让设计补图
        catalogueTab = craftLaneBtn(
            normalImage: ReaderEnvironment.images.tabCatalogue(),
            title: ReaderEnvironment.strings.directory
        )
        catalogueTab.tintColor = iconColor
        catalogueTab.addAction(UIAction { [weak self] _ in self?.presentCatalogue() }, for: .touchUpInside)
        addSubview(catalogueTab)

        // 日/夜间切换按钮
        themeToggleButton = craftLaneBtn(
            normalImage: ReaderEnvironment.images.nightMode(),
            title: ReaderEnvironment.strings.night
        )
        themeToggleButton.tintColor = iconColor
        themeToggleButton.addAction(UIAction { [weak self] _ in self?.toggleNightTheme() }, for: .touchUpInside)
        addSubview(themeToggleButton)

        // 设置按钮：常态描边六边形，设置面板展开时换成实心六边形
        // （设计稿那几帧面板都是展开的，里面的实心图标是选中态，不是常态）
        settingsTab = craftLaneBtn(
            normalImage: ReaderEnvironment.images.tabBookmark(),
            activeIcon: ReaderEnvironment.images.tabBookmarkSelected(),
            title: ReaderEnvironment.strings.setting
        )
        settingsTab.tintColor = iconColor
        settingsTab.addAction(UIAction { [weak self] _ in self?.presentSettings() }, for: .touchUpInside)
        addSubview(settingsTab)

        reviseNightVariantBtn()
    }

    /// 创建 tab 按钮（图标在上，文字在下）
    ///
    /// activeIcon 传 nil 表示该 tab 没有选中态，此时 isSelected 不会有任何视觉变化。
    /// 文案颜色两态相同：设计稿里选中与否只体现在图标上。
    private func craftLaneBtn(normalImage: UIImage?, activeIcon: UIImage? = nil, title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(normalImage, for: .normal)
        if let activeIcon {
            button.setImage(activeIcon, for: .selected)
            button.setImage(activeIcon, for: [.selected, .highlighted])
        }
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = ReaderEnvironment.fonts.uiLight(10)
        button.setTitleColor(laneTitleColor(ReaderConfiguration.shared().currentThemeColors), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        configureBtnLayout(button)
        return button
    }

    /// tab 文案颜色：6 套主题的设计稿都取主文字色（此前浅色主题误取了 textSubtle，偏灰）
    private func laneTitleColor(_ colors: ReaderTintPalette) -> UIColor {
        return colors.textBody
    }

    /// 配置按钮图标在上、文字在下的布局
    private func configureBtnLayout(_ button: UIButton) {
        button.titleLabel?.textAlignment = .center
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center

        button.imageEdgeInsets = UIEdgeInsets(
            top: -(titleHeight + iconTitleSpacing),
            left: 0,
            bottom: 0,
            right: -button.titleLabel!.intrinsicContentSize.width
        )
        button.titleEdgeInsets = UIEdgeInsets(
            top: iconSize + iconTitleSpacing,
            left: -iconSize,
            bottom: 0,
            right: 0
        )
    }

    /// 根据 isDarkTheme 更新日/夜间按钮的图标和文字
    private func reviseNightVariantBtn() {
        if isDarkTheme {
            themeToggleButton.setImage(ReaderEnvironment.images.dayMode(), for: .normal)
            themeToggleButton.setTitle(ReaderEnvironment.strings.day, for: .normal)
        } else {
            themeToggleButton.setImage(ReaderEnvironment.images.nightMode(), for: .normal)
            themeToggleButton.setTitle(ReaderEnvironment.strings.night, for: .normal)
        }
        configureBtnLayout(themeToggleButton)
    }

    // MARK: - Actions

    private func presentCatalogue() {
        delegate?.bottomTabBarDidClickCatalogue(self)
    }

    private func toggleNightTheme() {
        delegate?.bottomTabBarDidClickNightMode(self)
    }

    private func presentSettings() {
        delegate?.bottomTabBarDidClickSetting(self)
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()

        // 设计稿：容器左右各留 20，三个 item 在剩余宽度内三等分，顶部留白 20
        let contentWidth = bounds.width - horizontalMargin * 2
        let buttonWidth = contentWidth / 3

        catalogueTab.frame = CGRect(x: horizontalMargin, y: topPadding, width: buttonWidth, height: itemHeight)
        themeToggleButton.frame = CGRect(x: horizontalMargin + buttonWidth, y: topPadding, width: buttonWidth, height: itemHeight)
        settingsTab.frame = CGRect(x: horizontalMargin + buttonWidth * 2, y: topPadding, width: buttonWidth, height: itemHeight)
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderTintPalette) {
        backgroundColor = colors.fillSheet
        
        // 更新按钮文字颜色和图标 tintColor
        let iconColor = colors.iconStandard
        let titleColor = laneTitleColor(colors)
        catalogueTab.setTitleColor(titleColor, for: .normal)
        catalogueTab.tintColor = iconColor
        themeToggleButton.setTitleColor(titleColor, for: .normal)
        themeToggleButton.tintColor = iconColor
        settingsTab.setTitleColor(titleColor, for: .normal)
        settingsTab.tintColor = iconColor
    }
}
