//
//  ReaderMenuBottomBar.swift
//  ReaderKit
//
//  Created by Asuna on 2025/08/16.
//

import UIKit

/// progressView 高度
public let READER_MENU_PROGRESS_VIEW_HEIGHT: CGFloat = 68

/// 呼出菜单各段动画的统一时长
///
/// 之前 topView / bottomView 用 0.2s、设置面板与目录遮罩用 0.25s，三段同时跑时肉眼能看出
/// 不同步，统一成一个值后顶栏、底栏、遮罩、面板始终一致。
public let READER_MENU_MOTION_TIME: TimeInterval = 0.25

/// 呼出菜单各段动画的统一曲线（原先 topView 用 easeOut、bottomView 用默认 easeInOut）
public let READER_MENU_MOTION_OPTIONS: UIView.AnimationOptions = .curveEaseOut

/// 底部 tab 栏高度（设计稿：20 顶部留白 + 64 item(12+24+2+14+12)）
public let READER_MENU_BOTTOM_TAB_BAR_HEIGHT: CGFloat = 84

/// 设置面板高度（设计稿逐段累加）：
/// 20(顶部留白) + 24(行高滑块) + 16 + 50(字号) + 16 + 50(主题色块) + 16 + 40(阅读方向)
/// 设计稿面板底部还有 20 留白，这里由 tab 栏自带的 20 顶部留白承担，不重复计
public let READER_MENU_SETTING_PANEL_HEIGHT: CGFloat = 232

/// funcView 的固定内容高度（设置面板 + tab 栏）
///
/// funcView 高度恒定、底部锚定在 bottomView 里，所以面板与 tab 栏的**绝对位置在展开与
/// 收起两种状态下完全一致**，展开只是 bottomView 长高后把面板露出来。
/// 之前 funcView 高度随状态变化，面板会跟着容器顶边向上平移 166pt，横穿静止的 tab 栏
/// （tab 栏 z 序在面板之上），观感就是面板从 tab 栏底下钻出来再爬上去。
public let READER_MENU_FUNC_VIEW_CONTENT_HEIGHT: CGFloat = READER_MENU_SETTING_PANEL_HEIGHT + READER_MENU_BOTTOM_TAB_BAR_HEIGHT

/// 呼出菜单顶部圆角（设计稿 12，仅上方两角）
public let READER_MENU_BOTTOM_VIEW_CORNER_RADIUS: CGFloat = 12

/// bottomView 基础高度（不包含字体调整区域）
public let READER_MENU_BOTTOM_VIEW_BASE_HEIGHT: CGFloat = ReaderScreenMetrics.safeAreaBottom + READER_MENU_BOTTOM_TAB_BAR_HEIGHT

/// bottomView 扩展高度（包含设置面板）
public let READER_MENU_BOTTOM_VIEW_EXPANDED_HEIGHT: CGFloat = ReaderScreenMetrics.safeAreaBottom + READER_MENU_SETTING_PANEL_HEIGHT + READER_MENU_BOTTOM_TAB_BAR_HEIGHT

/// bottomView 目录高度（包含目录区域）- 屏幕高度减去170
public let READER_MENU_BOTTOM_VIEW_CATALOG_HEIGHT: CGFloat = ReaderScreenMetrics.screenHeight - 170

open class ReaderMenuBottomBar: ReaderMenuPanel {
    
    /// 进度
    public private(set) var progressView: ReaderMenuProgressPanel!
    
    /// 功能
    public private(set) var funcView: ReaderMenuSettingsPanel!
    
    /// 目录视图
    public private(set) var catalogView: ReaderMenuCataloguePanel!

    public override init(frame: CGRect) { super.init(frame: frame) }
    
    /// 获取当前应该显示的高度
    open func getCurrentHeight() -> CGFloat {
        if !catalogView.isHidden {
            return READER_MENU_BOTTOM_VIEW_CATALOG_HEIGHT
        } else if funcView.isOptionPanelShown() {
            return READER_MENU_BOTTOM_VIEW_EXPANDED_HEIGHT
        } else {
            return READER_MENU_BOTTOM_VIEW_BASE_HEIGHT
        }
    }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        // 设计稿：呼出菜单顶部两角圆角 12，裁剪由容器统一负责
        layer.cornerRadius = READER_MENU_BOTTOM_VIEW_CORNER_RADIUS
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true
        
        progressView = ReaderMenuProgressPanel(readMenu: readMenu)
        progressView.isHidden = true
        addSubview(progressView)
        
        funcView = ReaderMenuSettingsPanel(readMenu: readMenu)
        addSubview(funcView)
        
        // 目录视图
        catalogView = ReaderMenuCataloguePanel()
        catalogView.isHidden = true
        catalogView.onChapterSelected = { [weak self] chapterModel in
            self?.processCatalogChapterPicked(chapterModel)
        }
        addSubview(catalogView)
    }
    
    /// 处理目录章节选中
    private func processCatalogChapterPicked(_ chapterModel: ReaderChapterListItemModel) {
        funcView.processCatalogChapterPicked(chapterModel)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let w = frame.size.width
        let h = frame.size.height
        
        progressView.frame = CGRect(x: 0, y: 0, width: w, height: READER_MENU_PROGRESS_VIEW_HEIGHT)
        
        // funcView 底部锚定、高度恒定：收起态时设置面板落在 bottomView 上方被裁掉，
        // 展开态时正好露出来。tab 栏与面板的绝对位置因此在两种状态下都不变。
        let safeAreaBottom = ReaderScreenMetrics.safeAreaBottom
        let funcViewTotalHeight = READER_MENU_FUNC_VIEW_CONTENT_HEIGHT + safeAreaBottom
        funcView.frame = CGRect(x: 0, y: h - funcViewTotalHeight, width: w, height: funcViewTotalHeight)
        
        // 目录视图 - 从 0 开始到 tab 栏上方（目录态下面板不展开，按 tab 栏高度算）
        let catalogViewHeight = h - (READER_MENU_BOTTOM_TAB_BAR_HEIGHT + safeAreaBottom)
        catalogView.frame = CGRect(x: 0, y: 0, width: w, height: max(0, catalogViewHeight))
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色到所有子视图
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        funcView.adoptThemeColors(colors)
        catalogView.adoptThemeColors(colors)
    }
}
