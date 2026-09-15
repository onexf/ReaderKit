//
//  ReaderProgressSlider.swift
//  ReaderKit
//
//  阅读进度滑块：系统 UISlider + 拖动时在滑块头上方显示数值气泡。
//
//  轨道、滑块头、取值、着色全部沿用系统 UISlider，本类只补气泡与拖动回调。
//

import UIKit

/// 带数值气泡的进度滑块。
///
/// 用法：设置 `bubbleTextProvider` 提供气泡文案，`onDragFinished` 接收拖动结束的最终值。
open class ReaderProgressSlider: UISlider {

    // MARK: - 对外配置

    /// 气泡文案。参数为当前值，返回要显示的字符串。未设置时按整数显示。
    open var bubbleTextProvider: ((Float) -> String)?

    /// 拖动结束（松手或取消）时回调，参数为最终值。
    ///
    /// 轻点轨道跳转也会触发：系统 UISlider 的轻点会走完整的 begin/end tracking。
    open var onDragFinished: ((Float) -> Void)?

    /// 气泡背景色
    open var bubbleColor: UIColor = .darkGray {
        didSet { bubbleView.fillColor = bubbleColor }
    }

    /// 气泡文字颜色
    open var bubbleTextColor: UIColor = .white {
        didSet { bubbleView.textColor = bubbleTextColor }
    }

    /// 气泡字体
    open var bubbleFont: UIFont = .systemFont(ofSize: 22, weight: .bold) {
        didSet { bubbleView.font = bubbleFont }
    }

    /// 气泡底部箭头长度
    open var bubbleArrowLength: CGFloat = 5 {
        didSet { bubbleView.arrowLength = bubbleArrowLength }
    }

    /// 气泡圆角
    open var bubbleCornerRadius: CGFloat = 4 {
        didSet { bubbleView.cornerRadius = bubbleCornerRadius }
    }

    /// 气泡与滑块头之间的垂直间距
    open var bubbleSpacing: CGFloat = 2

    // MARK: - 子视图

    private lazy var bubbleView: BubbleView = {
        let view = BubbleView()
        view.fillColor = bubbleColor
        view.textColor = bubbleTextColor
        view.font = bubbleFont
        view.arrowLength = bubbleArrowLength
        view.cornerRadius = bubbleCornerRadius
        view.isUserInteractionEnabled = false
        view.alpha = 0
        return view
    }()

    // MARK: - 构造

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // 气泡画在滑块头上方，会超出自身 bounds，不能裁切
        clipsToBounds = false
        addSubview(bubbleView)
    }

    // MARK: - 气泡显隐

    /// 显示气泡（拖动开始）
    private func showBubble() {
        reviseBubble()
        bubbleView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.bubbleView.alpha = 1
            self.bubbleView.transform = .identity
        }
    }

    /// 隐藏气泡（拖动结束）
    private func hideBubble() {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.bubbleView.alpha = 0
            self.bubbleView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
    }

    /// 刷新气泡文案与位置
    private func reviseBubble() {
        bubbleView.text = bubbleTextProvider?(value) ?? "\(Int(value))"

        let thumb = thumbRect(forBounds: bounds, trackRect: trackRect(forBounds: bounds), value: value)
        let size = bubbleView.intrinsicSize
        bubbleView.bounds = CGRect(origin: .zero, size: size)
        bubbleView.center = CGPoint(x: thumb.midX,
                                   y: thumb.minY - bubbleSpacing - size.height / 2)
    }

    // MARK: - 跟踪

    open override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let began = super.beginTracking(touch, with: event)
        if began { showBubble() }
        return began
    }

    open override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let continued = super.continueTracking(touch, with: event)
        reviseBubble()
        return continued
    }

    open override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        hideBubble()
        onDragFinished?(value)
    }

    open override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        hideBubble()
        onDragFinished?(value)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        // 拖动中布局变化时保持气泡跟随
        if bubbleView.alpha > 0 { reviseBubble() }
    }

    // MARK: - 气泡视图

    /// 圆角矩形 + 底部箭头的气泡。
    private final class BubbleView: UIView {

        var text: String = "" {
            didSet {
                guard text != oldValue else { return }
                textLayer.string = text
                setNeedsLayout()
            }
        }

        var font: UIFont = .systemFont(ofSize: 22, weight: .bold) {
            didSet {
                textLayer.font = font.fontName as CFTypeRef
                textLayer.fontSize = font.pointSize
                setNeedsLayout()
            }
        }

        var textColor: UIColor = .white {
            didSet { textLayer.foregroundColor = textColor.cgColor }
        }

        var fillColor: UIColor = .darkGray {
            didSet { shapeLayer.fillColor = fillColor.cgColor }
        }

        var arrowLength: CGFloat = 5 { didSet { setNeedsLayout() } }

        var cornerRadius: CGFloat = 4 { didSet { setNeedsLayout() } }

        /// 文字四周内边距
        private let textInset = CGSize(width: 8, height: 3)

        private let shapeLayer = CAShapeLayer()

        private let textLayer = CATextLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            shapeLayer.fillColor = fillColor.cgColor
            layer.addSublayer(shapeLayer)

            textLayer.alignmentMode = .center
            textLayer.truncationMode = .end
            textLayer.font = font.fontName as CFTypeRef
            textLayer.fontSize = font.pointSize
            textLayer.foregroundColor = textColor.cgColor
            textLayer.contentsScale = UIScreen.main.scale
            layer.addSublayer(textLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 依文案与字体算出气泡尺寸（含箭头与内边距）
        var intrinsicSize: CGSize {
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            return CGSize(width: ceil(textSize.width) + textInset.width * 2,
                          height: ceil(textSize.height) + textInset.height * 2 + arrowLength)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            shapeLayer.frame = bounds
            shapeLayer.path = bubblePath().cgPath

            let textHeight = bounds.height - arrowLength - textInset.height * 2
            textLayer.frame = CGRect(x: 0,
                                     y: textInset.height,
                                     width: bounds.width,
                                     height: textHeight)
        }

        /// 圆角矩形主体 + 底边中间向下的箭头
        private func bubblePath() -> UIBezierPath {
            let w = bounds.width
            let bodyHeight = max(0, bounds.height - arrowLength)
            let r = min(cornerRadius, min(w, bodyHeight) / 2)
            let arrowHalfWidth = max(arrowLength, 3)

            let path = UIBezierPath()
            // 左上角起，顺时针
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(withCenter: CGPoint(x: w - r, y: r), radius: r,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: w, y: bodyHeight - r))
            path.addArc(withCenter: CGPoint(x: w - r, y: bodyHeight - r), radius: r,
                        startAngle: 0, endAngle: .pi / 2, clockwise: true)
            // 底边 → 箭头
            path.addLine(to: CGPoint(x: w / 2 + arrowHalfWidth, y: bodyHeight))
            path.addLine(to: CGPoint(x: w / 2, y: bodyHeight + arrowLength))
            path.addLine(to: CGPoint(x: w / 2 - arrowHalfWidth, y: bodyHeight))
            path.addLine(to: CGPoint(x: r, y: bodyHeight))
            path.addArc(withCenter: CGPoint(x: r, y: bodyHeight - r), radius: r,
                        startAngle: .pi / 2, endAngle: .pi, clockwise: true)
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(withCenter: CGPoint(x: r, y: r), radius: r,
                        startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
            path.close()
            return path
        }
    }
}
