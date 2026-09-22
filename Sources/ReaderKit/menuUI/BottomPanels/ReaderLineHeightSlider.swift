//
//  ReaderLineHeightSlider.swift
//  ReaderKit
//
//  阅读器设置面板的行高滑块
//
//  设计稿规格（各主题一致，仅取色不同）：
//  - 控件高 24，滑块头 24×24 纯白圆形，阴影 dy 0.97 / blur 4.61 / 黑 14%
//  - 轨道高 4、圆角 2；滑块头中心左侧为 accent，右侧为 separatorTint
//  - 滑块头中心行程为 [12, width - 12]，即最小值时轨道左侧仍有 12pt 的已填充段
//

import UIKit

/// 行高滑块。继承 UIControl 是为了让阅读器的呼出手势自动放行（手势拦截会跳过 UIControl）
open class ReaderLineHeightSlider: UIControl {
    
    // MARK: - 设计稿尺寸
    
    /// 轨道高度
    private let trackHeight: CGFloat = 4
    
    /// 滑块头直径
    private let thumbSize: CGFloat = 24
    
    /// 纵向额外热区（控件本身只有 24 高，直接拖不好点）
    private let extraTouchInset: CGFloat = 12
    
    // MARK: - 取值
    
    /// 最小值（行高百分比）
    open var minimumValue: Int = 120
    
    /// 最大值（行高百分比）
    open var maximumValue: Int = 200
    
    /// 当前值。拖动时连续取值（1 为最小粒度），不再吸附到 10 的整数档
    public private(set) var value: Int = 160
    
    /// 拖动过程中的实时回调：每次值变化都会触发，用于实时刷新正文行距（调用方需自行节流重排）
    open var onValueChanging: ((Int) -> Void)?
    
    /// 手指抬起（或轻点轨道）后的提交回调：在这里落库并做一次权威重排
    open var onValueCommitted: ((Int) -> Void)?
    
    // MARK: - 子视图
    
    /// 已填充轨道（滑块头左侧）
    private lazy var filledTrackView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = trackHeight / 2
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    
    /// 未填充轨道（滑块头右侧）
    private lazy var remainTrackView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = trackHeight / 2
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    
    /// 滑块头
    private lazy var thumbView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = thumbSize / 2
        view.isUserInteractionEnabled = false
        // 设计稿阴影：offset (0, 0.97)、stdDeviation 4.61、黑 14%
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.14
        view.layer.shadowOffset = CGSize(width: 0, height: 0.97)
        view.layer.shadowRadius = 4.61
        return view
    }()
    
    // MARK: - 构造
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(filledTrackView)
        addSubview(remainTrackView)
        addSubview(thumbView)
    }
    
    // MARK: - 取值更新
    
    /// 设置当前值（不触发回调）
    open func setValue(_ newValue: Int) {
        value = clamp(newValue)
        setNeedsLayout()
    }
    
    /// 主题换肤
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        filledTrackView.backgroundColor = colors.accent
        remainTrackView.backgroundColor = colors.separatorTint
    }
    
    /// 夹到 [min, max] 区间内（连续取值，不做档位吸附）
    private func clamp(_ raw: Int) -> Int {
        return max(minimumValue, min(maximumValue, raw))
    }
    
    /// 当前值对应的进度 0...1
    private var progress: CGFloat {
        guard maximumValue > minimumValue else { return 0 }
        return CGFloat(value - minimumValue) / CGFloat(maximumValue - minimumValue)
    }
    
    // MARK: - Layout
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        let w = bounds.width
        let h = bounds.height
        let travel = max(0, w - thumbSize)
        let thumbCenterX = thumbSize / 2 + travel * progress
        let trackY = (h - trackHeight) / 2
        
        filledTrackView.frame = CGRect(x: 0, y: trackY, width: thumbCenterX, height: trackHeight)
        remainTrackView.frame = CGRect(x: thumbCenterX, y: trackY, width: max(0, w - thumbCenterX), height: trackHeight)
        thumbView.frame = CGRect(x: thumbCenterX - thumbSize / 2, y: (h - thumbSize) / 2, width: thumbSize, height: thumbSize)
    }
    
    /// 扩大纵向热区
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let touchArea = bounds.insetBy(dx: 0, dy: -extraTouchInset)
        return touchArea.contains(point)
    }
    
    // MARK: - 拖动
    
    open override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        reviseValue(with: touch)
        return true
    }
    
    open override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        reviseValue(with: touch)
        return true
    }
    
    open override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        onValueCommitted?(value)
    }
    
    open override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        onValueCommitted?(value)
    }
    
    /// 把触点横坐标换算成值（连续，1 为最小粒度）
    private func reviseValue(with touch: UITouch) {
        let travel = max(1, bounds.width - thumbSize)
        let x = touch.location(in: self).x - thumbSize / 2
        let ratio = max(0, min(1, x / travel))
        let raw = minimumValue + Int((ratio * CGFloat(maximumValue - minimumValue)).rounded())
        let next = clamp(raw)
        
        guard next != value else { return }
        value = next
        setNeedsLayout()
        layoutIfNeeded()
        onValueChanging?(next)
    }
}
