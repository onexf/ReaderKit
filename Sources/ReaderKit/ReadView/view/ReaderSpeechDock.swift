//
//  ReaderSpeechDock.swift
//  ReaderKit — ReadView
//
//  呼出菜单上的朗读入口 / 迷你播放器。与页脚的 `ReaderSpeechActionButton` 是两个东西：
//
//  | | 未朗读 | 朗读中 |
//  |---|---|---|
//  | 菜单展开 | 本控件（右下，入口态） | 本控件（左下，播放态） |
//  | 菜单收起 | 无 | `ReaderSpeechActionButton`（页脚） |
//
//  也就是说本控件**只在菜单呼出期间可见**，菜单一收就整体隐藏，由页脚胶囊接手。
//

import UIKit

/// 朗读 dock 的两种形态。
public enum ReaderSpeechDockForm {

    /// 入口态：右下角方形，只有一个耳机图标，点击开始朗读。
    case entry

    /// 播放态：左下角横向胶囊，书封 + 进度环/暂停 + 关闭。
    case playing
}

/// 呼出菜单上的朗读 dock。
///
/// 两种形态**底边对齐在同一条线上**（设计稿两张图的底边都落在菜单面板顶边上方 20pt），
/// 所以形态切换只需要动 x / width / height，纵向锚点恒定 —— 这让「右下方块 ⇄ 左下胶囊」
/// 可以用一次 frame 动画完成，不需要两个视图交叉淡入淡出位置。
open class ReaderSpeechDock: UIView {

    // MARK: - 设计稿尺寸

    /// 入口态边长
    public static let entrySide: CGFloat = 54

    /// 播放态尺寸
    public static let playingSize = CGSize(width: 124, height: 48)

    /// 两态共用的圆角
    private let cornerRadius: CGFloat = 12

    /// 距屏幕左 / 右边缘的间距
    public static let horizontalMargin: CGFloat = 20

    /// 底边与菜单面板顶边的间距
    public static let bottomGap: CGFloat = 20

    /// 入口态图标边长
    private let entryIconSide: CGFloat = 32

    /// 播放态：书封边长与圆角
    private let coverSide: CGFloat = 40
    private let coverRadius: CGFloat = 10

    /// 播放态：进度环控件边长
    private let toggleSide: CGFloat = 36

    /// 播放态：关闭按钮边长
    private let closeSide: CGFloat = 20

    /// 播放态内边距（设计稿 4 / 8 / 4 / 4）
    private let playingInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 8)

    /// 播放态元素间距
    private let playingItemGap: CGFloat = 8

    // MARK: - 对外

    /// 当前形态。
    public private(set) var form: ReaderSpeechDockForm = .entry

    /// 底边锚点：`x` 为**贴靠边缘的那一侧**由内部按形态决定，这里只取 `y`。
    ///
    /// 用底边而不是中心做锚点，是因为两态高度不同（54 / 48）而设计稿要求底边齐平；
    /// 用中心锚点就得在切换时同时改 y，多一处容易算错的地方。
    open var anchorBottomY: CGFloat = 0 {

        didSet { reviseGeometry(animated: false) }
    }

    /// 容器宽度。用来算右对齐时的 x。
    open var containerWidth: CGFloat = 0 {

        didSet { reviseGeometry(animated: false) }
    }

    /// 点击入口（开始朗读）。
    open var onStartAction: (() -> Void)?

    /// 点击进度环中央（暂停 / 继续）。
    open var onToggleAction: (() -> Void)?

    /// 点击关闭（停止朗读，回到入口态）。
    open var onCloseAction: (() -> Void)?

    /// 点击书封（打开朗读播放器页）。仅播放态下可触发。
    open var onCoverAction: (() -> Void)?

    /// 进度环取值，0...1。
    open var progress: Double = 0 {

        didSet { toggleView.progress = progress }
    }

    /// 播放态中央图标是否显示为「暂停」。`true` 显示暂停（当前在播），`false` 显示播放。
    open var isPlaying: Bool = true {

        didSet { toggleView.isPlaying = isPlaying }
    }

    // MARK: - 子视图

    /// 入口态：耳机图标。唯一需要图片资源的元素，走 `ReaderImages` 注入。
    private lazy var entryIconView: UIImageView = {

        let view = UIImageView()

        view.contentMode = .scaleAspectFit

        return view
    }()

    /// 入口态点击区，铺满整个 dock。
    private lazy var entryControl: UIControl = {

        let control = UIControl()

        control.addAction(UIAction { [weak self] _ in self?.onStartAction?() }, for: .touchUpInside)

        return control
    }()

    /// 播放态：书封。
    private lazy var coverView: UIImageView = {

        let view = UIImageView()

        view.contentMode = .scaleAspectFill

        view.layer.cornerRadius = coverRadius

        view.layer.masksToBounds = true

        view.isUserInteractionEnabled = true

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(clickCover)))

        return view
    }()

    /// 播放态：进度环 + 中央暂停/播放图标。全部代码绘制，不占资源。
    private lazy var toggleView: ReaderSpeechDockToggle = {

        let view = ReaderSpeechDockToggle()

        view.onTap = { [weak self] in self?.onToggleAction?() }

        return view
    }()

    /// 播放态：关闭。X 形也是代码绘制。
    private lazy var closeView: ReaderSpeechDockCloseButton = {

        let view = ReaderSpeechDockCloseButton()

        view.onTap = { [weak self] in self?.onCloseAction?() }

        return view
    }()

    // MARK: - 构造

    public override init(frame: CGRect) {

        super.init(frame: frame)

        layer.cornerRadius = cornerRadius

        layer.masksToBounds = true

        addSubview(entryControl)

        entryControl.addSubview(entryIconView)

        addSubview(coverView)

        addSubview(toggleView)

        addSubview(closeView)

        adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)

        refreshContent()

        applyVisibility(for: form)

        reviseGeometry(animated: false)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 形态

    /// 切换形态。
    ///
    /// 动画分三条独立的线同时跑，刻意不共用一条曲线：
    ///
    /// 1. **容器**用 spring 从右下飞到左下并改变尺寸。位移接近 280pt，纯 ease 曲线在这个
    ///    距离上显得又慢又僵，轻微回弹才像「被甩过去停住」。
    /// 2. **离场内容**快速淡出（前 1/4 时间内），避免它在收缩的盒子里被裁着变形 ——
    ///    那是上一版最明显的毛刺。
    /// 3. **入场内容**延迟一点再淡入，等盒子长到大半再出现，否则会看到元素贴在裁切边缘上跳。
    ///
    /// 用 `isHidden` 一刀切是上一版的做法，看起来就是「内容瞬间变了、盒子才慢慢跟上」。
    open func apply(_ newForm: ReaderSpeechDockForm, animated: Bool) {

        // 形态没变也要刷内容：播放 / 暂停图标与进度是随时在变的
        refreshContent()

        guard newForm != form else { return }

        let outgoing = form

        form = newForm

        guard animated else {

            applyVisibility(for: newForm)

            reviseGeometry(animated: false)

            return
        }

        // 过渡期间两套内容同时在场，靠 alpha 交叉；离场那套等动画结束才真正隐藏
        for item in views(for: newForm) {

            item.isHidden = false

            item.alpha = 0
        }

        for item in views(for: outgoing) { item.alpha = 1 }

        reviseGeometry(animated: true)

        // 离场：短促。0.13s 是「还没来得及看清它被裁掉」的量级
        UIView.animate(withDuration: 0.13, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {

            for item in self.views(for: outgoing) { item.alpha = 0 }

        } completion: { _ in

            // 只有形态没有再次变回去时才隐藏，避免快速连点造成两套内容都不见
            guard self.form != outgoing else { return }

            for item in self.views(for: outgoing) { item.isHidden = true }
        }

        // 入场：让容器先走掉大半行程（0.12s ≈ spring 的前 1/4）再露出来
        UIView.animate(withDuration: 0.26, delay: 0.12, options: [.curveEaseIn, .allowUserInteraction]) {

            for item in self.views(for: newForm) { item.alpha = 1 }
        }
    }

    /// 某个形态下参与显示的元素。
    private func views(for form: ReaderSpeechDockForm) -> [UIView] {

        switch form {

        case .entry: return [entryControl]

        case .playing: return [coverView, toggleView, closeView]
        }
    }

    /// 无动画地切换两套内容的显隐。
    private func applyVisibility(for form: ReaderSpeechDockForm) {

        let isEntry = form == .entry

        entryControl.isHidden = !isEntry

        entryControl.alpha = 1

        for item in [coverView, toggleView, closeView] as [UIView] {

            item.isHidden = isEntry

            item.alpha = 1
        }
    }

    /// 刷新与形态无关的内容（图标、播放态、进度）。
    private func refreshContent() {

        entryIconView.image = ReaderEnvironment.images.speechDockEntry()

        toggleView.isPlaying = isPlaying

        toggleView.progress = progress
    }

    /// 设置书封。URL 为空时只贴占位图。
    open func adoptCover(url: String?) {

        let placeholder = ReaderEnvironment.images.coverPlaceholder()

        guard let url, !url.isEmpty else {

            coverView.image = placeholder

            return
        }

        // 远程图加载能力由接入方注入（库内不带网络图片库），未注入时默认实现只贴占位图
        ReaderEnvironment.images.loadRemoteImage(coverView, url, placeholder)
    }

    // MARK: - 布局

    /// 当前形态下的尺寸。
    private var preferredSize: CGSize {

        switch form {

        case .entry: return CGSize(width: Self.entrySide, height: Self.entrySide)

        case .playing: return Self.playingSize
        }
    }

    /// 按锚点与形态重算 frame。
    private func reviseGeometry(animated: Bool) {

        let size = preferredSize

        // 入口态贴右、播放态贴左
        let x: CGFloat

        switch form {

        case .entry: x = containerWidth - Self.horizontalMargin - size.width

        case .playing: x = Self.horizontalMargin
        }

        let target = CGRect(x: x, y: anchorBottomY - size.height, width: size.width, height: size.height)

        guard animated else {

            frame = target

            setNeedsLayout()

            layoutIfNeeded()

            return
        }

        // 位移与尺寸**分开两条曲线**，不要合成一次 frame 动画。
        //
        // 两者的观感诉求不同：位移要有惯性（280pt 的距离，带一点回弹才像被甩过去停住），
        // 尺寸变化却不能回弹 —— 宽度过冲会让盒子先超出目标再缩回来，边缘明显抖一下。
        // 合成一次 frame 动画只能共用一条曲线，必然牺牲其中一个。
        //
        // `center` + `bounds.size` 两者合起来等价于设置 frame，且各自可独立动画。
        // 尺寸动画比位移短（0.34 vs 0.52），所以盒子先定形、再滑到位停住，
        // 而不是一路边走边变形。
        UIView.animate(withDuration: 0.52,
                       delay: 0,
                       usingSpringWithDamping: 0.84,
                       initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {

            self.center = CGPoint(x: target.midX, y: target.midY)
        }

        UIView.animate(withDuration: 0.34,
                       delay: 0,
                       options: [.curveEaseInOut, .allowUserInteraction]) {

            self.bounds.size = target.size

            self.layoutIfNeeded()
        }
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        switch form {

        case .entry:

            entryControl.frame = bounds

            entryIconView.frame = CGRect(x: (bounds.width - entryIconSide) / 2,
                                         y: (bounds.height - entryIconSide) / 2,
                                         width: entryIconSide,
                                         height: entryIconSide)

        case .playing:

            // 书封左上角贴内边距，其余元素在内容区垂直居中
            coverView.frame = CGRect(x: playingInsets.left,
                                     y: playingInsets.top,
                                     width: coverSide,
                                     height: coverSide)

            var cursor = playingInsets.left + coverSide + playingItemGap

            toggleView.frame = CGRect(x: cursor,
                                      y: (bounds.height - toggleSide) / 2,
                                      width: toggleSide,
                                      height: toggleSide)

            cursor += toggleSide + playingItemGap

            closeView.frame = CGRect(x: cursor,
                                     y: (bounds.height - closeSide) / 2,
                                     width: closeSide,
                                     height: closeSide)
        }
    }

    // MARK: - 换肤

    /// dock 在设计稿里是**固定深色**，不随阅读主题变化（六套主题下都是同一块深底白字），
    /// 所以这里只取主题里那一个语义色槽，不做明暗反转。
    open func adoptThemeColors(_ colors: ReaderThemeColors) {

        backgroundColor = colors.fillSpeechDock

        entryIconView.tintColor = colors.textSpeechDock

        toggleView.adoptTintColor(colors.textSpeechDock)

        closeView.adoptTintColor(colors.textSpeechDock)
    }

    // MARK: - 动作


    @objc private func clickCover() { onCoverAction?() }
}

// MARK: - 进度环 + 中央图标

/// 播放态中央那个 36×36 控件：一圈进度环套一个暂停 / 播放图标。
///
/// 全部用 `CAShapeLayer` 画，不用图片：
/// - 环必须是动态的，本来就画不成静态图
/// - 暂停两根竖条与播放三角形足够简单，画出来还顺带免了「播放态该配什么图标」这个
///   设计稿里没给的问题，也不占资源（库内零资源，见 BOUNDARY.md）
final class ReaderSpeechDockToggle: UIView {

    /// 设计稿：环外径 30（36 里留 3 边距），环宽 3 → 路径半径 13.5
    private let ringWidth: CGFloat = 3

    /// 暂停竖条：1.333 宽、8 高、间距 4
    private let barSize = CGSize(width: 1.333, height: 8)
    private let barGap: CGFloat = 4

    var onTap: (() -> Void)?

    var progress: Double = 0 {

        didSet { reviseProgress() }
    }

    var isPlaying: Bool = true {

        didSet { reviseGlyph() }
    }

    private let trackLayer = CAShapeLayer()

    private let progressLayer = CAShapeLayer()

    private let glyphLayer = CAShapeLayer()

    private var tint: UIColor = .white

    override init(frame: CGRect) {

        super.init(frame: frame)

        // 环轨固定 20% 不透明度（设计稿 fill-opacity 0.2）
        trackLayer.fillColor = nil

        trackLayer.lineWidth = ringWidth

        layer.addSublayer(trackLayer)

        progressLayer.fillColor = nil

        progressLayer.lineWidth = ringWidth

        // 进度从 12 点方向顺时针增长，端头切平（设计稿是扇形边缘，非圆头）
        progressLayer.lineCap = .butt

        layer.addSublayer(progressLayer)

        layer.addSublayer(glyphLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        adoptTintColor(tint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        let radius = (min(bounds.width, bounds.height) - ringWidth) / 2

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // 起点扳到 12 点方向：UIBezierPath 的 0 弧度在 3 点方向
        let start = -CGFloat.pi / 2

        let ring = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: start,
                                endAngle: start + .pi * 2,
                                clockwise: true)

        trackLayer.frame = bounds

        trackLayer.path = ring.cgPath

        progressLayer.frame = bounds

        progressLayer.path = ring.cgPath

        glyphLayer.frame = bounds

        reviseProgress()

        reviseGlyph()
    }

    private func reviseProgress() {

        // strokeEnd 直接表达「画到整圈的百分之几」，比按角度重建 path 便宜且可动画
        progressLayer.strokeEnd = CGFloat(min(1, max(0, progress)))
    }

    private func reviseGlyph() {

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let path = UIBezierPath()

        if isPlaying {

            // 暂停：两根竖条
            let totalWidth = barSize.width * 2 + barGap

            let left = center.x - totalWidth / 2

            let top = center.y - barSize.height / 2

            path.append(UIBezierPath(rect: CGRect(x: left, y: top, width: barSize.width, height: barSize.height)))

            path.append(UIBezierPath(rect: CGRect(x: left + barSize.width + barGap,
                                                  y: top,
                                                  width: barSize.width,
                                                  height: barSize.height)))

        }else{

            // 播放：等高的三角形。宽度取暂停图标的整体宽度，两态视觉重量才接近
            let width = barSize.width * 2 + barGap

            let height = barSize.height

            let left = center.x - width / 2

            let top = center.y - height / 2

            path.move(to: CGPoint(x: left, y: top))

            path.addLine(to: CGPoint(x: left, y: top + height))

            path.addLine(to: CGPoint(x: left + width, y: center.y))

            path.close()
        }

        glyphLayer.path = path.cgPath
    }

    func adoptTintColor(_ color: UIColor) {

        tint = color

        trackLayer.strokeColor = color.withAlphaComponent(0.2).cgColor

        progressLayer.strokeColor = color.cgColor

        glyphLayer.fillColor = color.cgColor
    }

    @objc private func handleTap() { onTap?() }
}

// MARK: - 关闭按钮

/// 播放态最右侧那个 20×20 的 X。代码绘制，设计稿整体 80% 不透明度。
final class ReaderSpeechDockCloseButton: UIView {

    /// 设计稿：描边 1.389，X 的四个端点距边框各 5.833（即 20 里内缩约 29%）
    private let strokeWidth: CGFloat = 1.389
    private let insetRatio: CGFloat = 5.833 / 20

    var onTap: (() -> Void)?

    private let crossLayer = CAShapeLayer()

    override init(frame: CGRect) {

        super.init(frame: frame)

        crossLayer.fillColor = nil

        crossLayer.lineWidth = strokeWidth

        crossLayer.opacity = 0.8

        layer.addSublayer(crossLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        crossLayer.frame = bounds

        let inset = min(bounds.width, bounds.height) * insetRatio

        let path = UIBezierPath()

        path.move(to: CGPoint(x: inset, y: inset))

        path.addLine(to: CGPoint(x: bounds.width - inset, y: bounds.height - inset))

        path.move(to: CGPoint(x: bounds.width - inset, y: inset))

        path.addLine(to: CGPoint(x: inset, y: bounds.height - inset))

        crossLayer.path = path.cgPath
    }

    /// 点击热区放大到 44×44 可点下限：视觉只有 20，直接点很难命中。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {

        let minimum: CGFloat = 44

        let dx = max(0, (minimum - bounds.width) / 2)

        let dy = max(0, (minimum - bounds.height) / 2)

        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }

    func adoptTintColor(_ color: UIColor) { crossLayer.strokeColor = color.cgColor }

    @objc private func handleTap() { onTap?() }
}
