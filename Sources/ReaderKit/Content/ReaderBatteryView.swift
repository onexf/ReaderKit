//
//  ReaderBatteryView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/08.
//
//  ---------------------------------------------------------------------------
//  页脚的电量指示。外壳默认由**代码绘制**（几何照设计稿 Figma `253:40061` 折算，
//  见下方参数区对照表），接入方注入 `ReaderImages.battery` 时改用其切图；
//  电量条无论哪条路都由本类绘制，跟随主题色。
//
//  1.13.0 修的是**默认值**：此前外壳默认取 SF Symbol `battery.100`，而那个图形
//  自带满格填充、长宽比与留白也与 20×10 完全不同，库再把电量条叠上去就是一块实心疙瘩。
//  也就是说凡是没注入自己切图的接入方**开箱即错**，而错因在库里。
//
//  设计稿的电量条起点是 (2,2)，而 1pt 描边的内边缘在 (1,1) —— **描边与填充之间
//  本来就留着 1pt 的缝，四边都留**。这道缝不是后加的修饰，缺了它满电时填充会贴死内壁、
//  与描边连成一片，正是修复前那个"两边顶满"的观感。
//  ---------------------------------------------------------------------------
//

/// 电池推荐使用的宽高
nonisolated(unsafe) public var ReaderBatterySize: CGSize = CGSize(width: 20, height: 10)

import UIKit

/// 页脚电量指示。
///
/// 仍然继承 `UIImageView` 只为保持既有接入方代码的类型兼容（此前是它，且 `image`
/// 属性可能被外部读写过）；本类自身不再使用 `image`。
open class ReaderBatteryView: UIImageView {

    // MARK: - 绘制参数
    //
    // 全部照设计稿 Figma `253:40061`（20×10 组合）折算成比例，不是自己定的"系统观感"：
    //
    // | 元素   | 设计稿几何                              |
    // |--------|-----------------------------------------|
    // | 外壳   | (0,0) 19×10，描边 1，圆角 2              |
    // | 正极头 | (19,4) 1×2 实心，右侧圆角 0.2            |
    // | 电量条 | (2,2) 高 6 实心，圆角 1                  |
    //
    // 用比例而非写死 pt，是为了让 20×10 之外的尺寸也成立（`ReaderBatterySize` 可被接入方改）。

    /// 设计稿基准尺寸。所有比例都相对它折算。
    private static let designSize = CGSize(width: 20, height: 10)

    /// 外壳宽度占总宽的比例（19/20）。余下的给正极头。
    private let shellWidthRatio: CGFloat = 0.95

    /// 外壳描边宽度占高度的比例（1/10）。
    private let shellStrokeRatio: CGFloat = 0.1

    /// 外壳圆角占高度的比例（2/10）。
    private let shellCornerRatio: CGFloat = 0.2

    /// 正极头宽度占总宽、高度占总高的比例（1/20、2/10）。
    private let terminalWidthRatio: CGFloat = 0.05
    private let terminalHeightRatio: CGFloat = 0.2

    /// 电量条相对**外壳外框**的内缩量，占高度的比例（2/10）。
    ///
    /// 设计稿电量条起点是 (2,2)，而 1pt 描边的内边缘在 (1,1) —— 也就是
    /// **描边与填充之间还留 1pt 的缝，四边都留**。这道缝是设计稿本来就有的，
    /// 没有它满电时填充会贴死内壁、与描边连成一片实心块。
    ///
    /// 因此满电宽度 = 外壳宽 - 内缩 × 2 = 19 - 4 = 15pt，右侧同样留出 1pt。
    private let levelInsetRatio: CGFloat = 0.2

    /// 电量条圆角占高度的比例（1/10）。
    private let levelCornerRatio: CGFloat = 0.1

    // MARK: - 对外

    /// 颜色。外壳与电量条同色，跟随阅读主题。
    open override var tintColor: UIColor! {

        didSet { reviseColors() }
    }

    /// 电量，0...1。
    open var batteryLevel: Float = 0 {

        didSet { setNeedsLayout() }
    }

    // MARK: - 图层

    /// 外壳。描边，不填充。
    private let shellLayer = CAShapeLayer()

    /// 正极头。实心，所以不能与描边外壳共用图层（一个图层只有一组 stroke/fill 设置）。
    private let terminalLayer = CAShapeLayer()

    /// 电量条。实心。
    private let levelLayer = CAShapeLayer()

    // MARK: - 构造

    public convenience init() {

        self.init(frame: CGRect(origin: .zero, size: ReaderBatterySize))
    }

    public override init(frame: CGRect) {

        super.init(frame: frame.size == .zero ? CGRect(origin: .zero, size: ReaderBatterySize) : frame)

        addSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }

    open func addSubviews() {

        layer.addSublayer(shellLayer)

        layer.addSublayer(terminalLayer)

        layer.addSublayer(levelLayer)

        // 接入方注入了外壳切图就用它，否则由本类绘制。
        //
        // 两条路都留着：整体绘制保证「不配置即正确」，注入则让有自己设计体系的接入方
        // 换掉外壳造型。无论走哪条，电量条都由本类按同一套比例绘制并跟随主题色 ——
        // 所以注入的切图需遵守外壳比例（见 `ReaderImages.battery` 的说明）。
        if let injected = ReaderEnvironment.images.battery() {

            image = injected

            shellLayer.isHidden = true

            terminalLayer.isHidden = true
        }

        tintColor = .white
    }

    // MARK: - 布局

    open override func layoutSubviews() {

        super.layoutSubviews()

        let width = bounds.width

        let height = bounds.height

        guard width > 0, height > 0 else { return }

        shellLayer.frame = bounds

        levelLayer.frame = bounds

        let stroke = max(0.5, height * shellStrokeRatio)

        let shellWidth = width * shellWidthRatio

        // 描边路径内缩半个线宽：`UIBezierPath` 的描边以路径为中线向两侧铺开，
        // 不缩的话外侧半个线宽落在 bounds 之外被裁掉，看起来比设计稿细一半
        let shellRect = CGRect(x: stroke / 2,
                               y: stroke / 2,
                               width: shellWidth - stroke,
                               height: height - stroke)

        shellLayer.lineWidth = stroke

        shellLayer.path = UIBezierPath(roundedRect: shellRect,
                                       cornerRadius: height * shellCornerRatio).cgPath

        // 正极头：紧贴外壳右侧、纵向居中。设计稿里它与外壳之间没有间隙（x 正好是 19）
        let terminalWidth = width * terminalWidthRatio

        let terminalHeight = height * terminalHeightRatio

        let terminalRect = CGRect(x: shellWidth,
                                  y: (height - terminalHeight) / 2,
                                  width: terminalWidth,
                                  height: terminalHeight)

        terminalLayer.frame = bounds

        // 设计稿只给右侧两角圆角（0.2），左侧与外壳相接处是直角
        terminalLayer.path = UIBezierPath(roundedRect: terminalRect,
                                          byRoundingCorners: [.topRight, .bottomRight],
                                          cornerRadii: CGSize(width: terminalWidth * 0.2,
                                                              height: terminalWidth * 0.2)).cgPath

        // 电量条：相对外壳**外框**四边内缩，缝隙与设计稿一致
        let inset = height * levelInsetRatio

        let cavity = CGRect(x: inset,
                            y: inset,
                            width: max(0, shellWidth - inset * 2),
                            height: max(0, height - inset * 2))

        let clamped = CGFloat(min(max(batteryLevel, 0), 1))

        let levelWidth = cavity.width * clamped

        let levelRect = CGRect(x: cavity.minX, y: cavity.minY, width: levelWidth, height: cavity.height)

        // 圆角不能超过自身宽度的一半，否则低电量时那一小条会被挤成一个点
        let levelCorner = min(height * levelCornerRatio, levelWidth / 2)

        levelLayer.path = UIBezierPath(roundedRect: levelRect, cornerRadius: levelCorner).cgPath
    }

    // MARK: - 颜色

    private func reviseColors() {

        let color = (tintColor ?? .white).cgColor

        shellLayer.strokeColor = color

        shellLayer.fillColor = nil

        terminalLayer.fillColor = color

        terminalLayer.strokeColor = nil

        levelLayer.fillColor = color

        levelLayer.strokeColor = nil
    }
}
