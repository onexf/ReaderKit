//
//  ReaderMenuTopBar.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/19.
//

import UIKit

/// topView 高度
public let READER_MENU_TOP_VIEW_HEIGHT: CGFloat = ReaderScreenMetrics.navBarHeight

open class ReaderMenuTopBar: ReaderMenuPanel {
    
    // MARK: - 设计稿尺寸
    
    /// 图标视觉尺寸
    private let iconSize: CGFloat = 24
    
    /// 右侧图标之间的间距
    private let iconSpacing: CGFloat = 16
    
    /// 左右安全边距
    private let horizontalMargin: CGFloat = 20
    
    /// 按钮点击热区（图标仍按 iconSize 居中绘制，仅放大可点区域）
    private let touchSize: CGFloat = 44
    
    // MARK: - 子视图
    
    /// 返回
    private var back: UIButton!
    
    /// 加入书架
    private var addToBookshelf: UIButton!
    
    /// 反馈
    private var feedback: UIButton!

    public override init(frame: CGRect) { super.init(frame: frame) }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        let iconColor = ReaderConfiguration.shared().currentThemeColors.iconDefault
        
        // 返回
        back = UIButton(type:.custom)
        back.setImage(ReaderEnvironment.images.back(), for: .normal)
        back.addTarget(self, action: #selector(clickBack), for: .touchUpInside)
        back.tintColor = iconColor
        addSubview(back)
        
        // 加入书架（template 模式 + 手动着色区分 normal/selected）
        addToBookshelf = UIButton(type:.custom)
        reviseAppendToBookshelfImages()
        addToBookshelf.addTarget(self, action: #selector(clickAddToBookshelf), for: .touchUpInside)
        addSubview(addToBookshelf)
        
        // 反馈（Figma 中使用 iconDefault 颜色）
        feedback = UIButton(type:.custom)
        feedback.setImage(ReaderEnvironment.images.feedback(), for: .normal)
        feedback.tintColor = iconColor
        feedback.addTarget(self, action: #selector(clickFeedback), for: .touchUpInside)
        addSubview(feedback)
    }
    
    /// 点击返回
    @objc private func clickBack() {
        
        readMenu?.delegate?.readerMenuDidTapBack(readMenu)
    }
    
    /// 点击加入书架
    @objc private func clickAddToBookshelf() {
        
        readMenu?.delegate?.readerMenuDidTapAddToBookshelf(readMenu)
    }
    
    /// 点击反馈
    @objc private func clickFeedback() {
        
        readMenu?.delegate?.readerMenuDidTapFeedback(readMenu)
    }
    
    // 顶部栏曾有书签入口，设计改版后只保留 返回 / 反馈 / 加入书架，书签改由侧栏书签 tab
    // 承载。`verifyForMark()` / `reviseMarkBtn()` 两个空实现一并删除 —— 留着空方法让
    // 宿主继续调，读代码的人会以为「这里刷新了书签状态」，实际什么都没发生。
    
    // MARK: - 加入书架状态
    
    /// 更新加入书架按钮状态
    open func reviseAppendToBookshelfBtn(isAdded: Bool) {
        addToBookshelf.isSelected = isAdded
        reviseAppendToBookshelfImages()
    }
    
    /// 更新加书架按钮图片（未加入用 iconDefault 深色，已加入用 iconDisable 浅色）
    private func reviseAppendToBookshelfImages() {
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        let normalImage = ReaderEnvironment.images.addToBookshelf()?.withTintColor(themeColors.iconDefault)
        let selectedImage = ReaderEnvironment.images.addedToBookshelf()?.withTintColor(themeColors.iconDisable)
        addToBookshelf.setImage(normalImage, for: .normal)
        addToBookshelf.setImage(selectedImage, for: .selected)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let y = ReaderScreenMetrics.safeAreaTop
        
        // 设计稿导航区高度 44，图标垂直居中
        let barHeight = ReaderScreenMetrics.navBarHeight - y
        let centerY = y + barHeight / 2
        let touchY = centerY - touchSize / 2
        
        // 返回按钮（左侧，图标左边缘对齐 20）
        let backCenterX = horizontalMargin + iconSize / 2
        back.frame = CGRect(x: backCenterX - touchSize / 2, y: touchY, width: touchSize, height: touchSize)
        
        // 右侧两图标从右到左:加书架 → 反馈,间距 16
        // 添加书架按钮（最右侧，图标右边缘对齐 20）
        let addCenterX = frame.size.width - horizontalMargin - iconSize / 2
        addToBookshelf.frame = CGRect(x: addCenterX - touchSize / 2, y: touchY, width: touchSize, height: touchSize)
        
        // 反馈按钮（加书架左边,间距 16）
        let feedbackCenterX = addCenterX - iconSize - iconSpacing
        feedback.frame = CGRect(x: feedbackCenterX - touchSize / 2, y: touchY, width: touchSize, height: touchSize)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        backgroundColor = colors.fillPopup
        back.tintColor = colors.iconDefault
        feedback.tintColor = colors.iconDefault
        reviseAppendToBookshelfImages()
    }
}
