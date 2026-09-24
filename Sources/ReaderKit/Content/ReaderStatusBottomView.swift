//
//  ReaderStatusBottomView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/14.
//

import UIKit

/// bottomView 高度
public let READER_STATUS_BOTTOM_VIEW_HEIGHT: CGFloat =  46

/// 阅读器页脚
///
/// 按设计稿（Figma 阅读器 162:8599）页脚右侧展示时间与电池，整条透明度 60%。
///
/// ## 左侧页码分两条路
///
/// - **上下滚动模式**：用本视图自带的 `pageLabel`，由 `ReaderScrollController`
///   在滚动时下发文案。滚动模式下页脚是固定的一层、正文是 tableView，页码只能由外部驱动。
/// - **左右翻页模式**：仍由每页的 `ReaderPageContentController.folioLabel` 负责。
///   那边每翻一页都会新建一个正文控制器，页码随 VC 创建天然算好，改动它反而要新增刷新链路。
///
/// 两条路的样式（Regular 12 / textSubtle / 整条 60% 透明）与基线一致，视觉上无差别。
open class ReaderStatusBottomView: UIView {
    
    /// 设计稿中信息行距页脚区顶部的距离（与正文页页码 label 保持同一基线）
    public static let contentTopInset: CGFloat = 16
    
    /// 设计稿中信息行的高度
    public static let contentHeight: CGFloat = 22
    
    /// 时间与电池的间距
    private let timeBatterySpacing: CGFloat = 4
    
    /// 页码与右侧「时间 + 电池」组的最小间距
    private let pageNumberTrailingSpacing: CGFloat = 8
    
    /// 页码（滚动模式使用，默认隐藏）
    private var pageLabel: UILabel!
    
    /// 时间
    private var clockLabel: UILabel!
    
    /// 电池
    private var batteryGauge: ReaderBatteryView!
    
    /// 计时器
    private var timer: Timer?
    
    /// 是否启用左侧页码。
    ///
    /// 默认关闭：翻页模式的页码由正文页自己画，本视图开着会重复显示两个页码。
    /// 滚动模式在创建页脚后显式打开。
    open var showsPageNumber: Bool = false {
        
        didSet { revisePageNumberVisibility() }
    }
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        // 设计稿中整条信息栏透明度 60%
        alpha = 0.6
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        // 电池
        batteryGauge = ReaderBatteryView()
        batteryGauge.tintColor = ReaderConfiguration.shared().currentThemeColors.textBody
        addSubview(batteryGauge)
        
        // 页码（滚动模式使用）：样式与正文页的 folioLabel 一致，
        // 透明度由整条页脚的 alpha 0.6 提供，不再单独设
        pageLabel = UILabel()
        pageLabel.textAlignment = .left
        pageLabel.font = ReaderEnvironment.fonts.uiRegular(readerScaled(12))
        pageLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textSubtle
        pageLabel.isHidden = true
        addSubview(pageLabel)
        
        // 时间
        clockLabel = UILabel()
        clockLabel.textAlignment = .right
        // 设计稿 App/14/Light：Lexend Deca Light 14
        clockLabel.font = ReaderEnvironment.fonts.uiLight(readerScaled(14))
        clockLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textBody
        clockLabel.setContentHuggingPriority(.required, for: .horizontal)
        clockLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(clockLabel)
        
        // 初始化调用
        didChangeTime()
        
        // 添加定时器
        appendClock()
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let w = frame.size.width
        let rowY = Self.contentTopInset
        let rowHeight = Self.contentHeight
        
        // 电池：右边缘与正文右边缘对齐，垂直居中于信息行
        let batteryX = w - ReaderBatterySize.width
        batteryGauge.frame = CGRect(x: batteryX,
                                   y: rowY + (rowHeight - ReaderBatterySize.height) / 2,
                                   width: ReaderBatterySize.width,
                                   height: ReaderBatterySize.height)
        
        // 时间：紧贴电池左侧，宽度按实际文本自适应
        let timeLabelWidth = measuredTimeWidth()
        let timeLabelX = batteryX - timeBatterySpacing - timeLabelWidth
        clockLabel.frame = CGRect(x: timeLabelX,
                                 y: rowY,
                                 width: timeLabelWidth,
                                 height: rowHeight)
        
        // 页码：左边缘与正文对齐（页脚本身已按正文左右边距摆放），
        // 宽度延伸到「时间 + 电池」组左侧，长文案时截断而不是压到时间上
        // （对齐 Android widget_tome_sheet.xml 里 tv_footer_left 到 barrier_footer 的约束）
        pageLabel.frame = CGRect(x: 0,
                                 y: rowY,
                                 width: max(0, timeLabelX - pageNumberTrailingSpacing),
                                 height: rowHeight)
    }
    
    // MARK: -- 页码
    
    /// 下发页码文案。
    ///
    /// 传 `nil` 表示当前位置不该显示页码（书末推荐区、书籍首页），此时隐藏但**不改变布局**，
    /// 与 Android `SNPageView.setProgress` 用 `isInvisible` 占位隐藏的口径一致。
    ///
    /// 内部做文本判重（对齐 Android 的 `setTextIfNotEqual`），所以外部可以在
    /// `scrollViewDidScroll` 里放心地每帧调用，值没变不会触发重绘。
    open func revisePageNumber(_ text: String?) {
        
        guard let pageLabel, pageLabel.text != text else { return }
        
        pageLabel.text = text
        
        revisePageNumberVisibility()
    }
    
    /// 页码可见性由「是否启用」与「是否有文案」共同决定
    private func revisePageNumberVisibility() {
        
        guard let pageLabel else { return }
        
        pageLabel.isHidden = !showsPageNumber || (pageLabel.text?.isEmpty ?? true)
    }
    
    /// 时间文本的实际宽度（额外加 2pt 避免被压缩）
    private func measuredTimeWidth() -> CGFloat {
        
        guard let text = clockLabel.text, !text.isEmpty, let font = clockLabel.font else { return 50 }
        
        return ceil(text.size(withAttributes: [.font: font]).width) + 2
    }
    
    // MARK: -- 时间相关
    
    /// 添加定时器
    open func appendClock() {
        
        if timer == nil {
            
            // 用闭包 + weak self，避免 target-action 版定时器强引用本视图导致 deinit 永不触发
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] currentTimer in
                
                guard let self else {
                    
                    currentTimer.invalidate()
                    
                    return
                }
                
                self.didChangeTime()
            }
            
            RunLoop.current.add(timer!, forMode: .common)
        }
    }
    
    /// 删除定时器
    open func discardClock() {
        
        if timer != nil {
            
            timer!.invalidate()
            
            timer = nil
        }
    }
    
    /// 时间变化
    open func didChangeTime() {
        
        clockLabel.text = readerClockText("HH:mm")
        
        batteryGauge.batteryLevel = UIDevice.current.batteryLevel
        
        // 时间更新后需要重新布局，确保宽度自适应
        setNeedsLayout()
    }
    
    /// 更新主题颜色
    open func reviseColors() {
        
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        clockLabel.textColor = themeColors.textBody
        
        batteryGauge.tintColor = themeColors.textBody
        
        // 页码用 textSubtle（与正文页的 folioLabel 一致，比时间/电池弱一级）
        pageLabel.textColor = themeColors.textSubtle
    }
    
    /// 销毁
    deinit {
        
        discardClock()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
