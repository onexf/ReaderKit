//
//  ReaderSpeechScreenController.swift
//  ReaderKit — ReadView
//
//  朗读播放器页（整屏）。唯一入口是呼出菜单上 `ReaderSpeechDock` 播放态里的小书封。
//
//  ---------------------------------------------------------------------------
//  本页**依附于阅读器存在**：朗读状态、章节全文、跨章能力全部来自
//  `ReaderSpeechController`，而后者与 `ReaderViewController` 强绑定（26 处依赖）。
//  所以它只能由阅读器 present，不能当作「书架上继续听书」的独立入口 ——
//  那需要先把朗读从阅读器上解耦，属另一件事。
//  ---------------------------------------------------------------------------
//
//  库内零资源：向下箭头与三个播放控件全部 `CAShapeLayer` 绘制，
//  书封走 `ReaderImages.loadRemoteImage` 注入点。
//

import UIKit

/// 朗读播放器页。
open class ReaderSpeechScreenController: UIViewController {

    // MARK: - 设计稿尺寸（375×812 基准，纵向按「上固定 + 下固定 + 中间弹性」适配）

    /// 顶部导航行高度
    private let headerHeight: CGFloat = 40

    /// 导航行与标题区的间距
    private let headerToTitleGap: CGFloat = 20

    /// 左右页边距
    private let horizontalMargin: CGFloat = 20

    /// 书封尺寸与圆角
    private let coverSize = CGSize(width: 156, height: 208)
    private let coverRadius: CGFloat = 16

    /// 正文窗口所占的**版位**高度与左右内边距。
    ///
    /// 窗口的实际高度是「满 3 行的真实高度」，按行边界算出来（见 `reviseTextWindow()`），
    /// 所以不等于这个值。这里保留设计稿的 123 只用来给书封与控件定位 ——
    /// 让实际高度参与定位的话，段间距导致的几 pt 差异会把书封和控件位置带着晃。
    private let textWindowBandHeight: CGFloat = 123
    private let textWindowInset: CGFloat = 30

    /// 正文窗口显示的行数（设计稿 3 行）。
    ///
    /// 按**整行**显示，不允许露出半行：窗口高度写死时行边界对不上，
    /// 底部会露出下一行的上半截，看着像没裁干净。
    private let visibleLineCount = 3

    /// 书封底边到正文窗口顶边
    private let coverTextInset: CGFloat = 64

    /// 正文窗口底边到控件行顶边
    private let textToControlsGap: CGFloat = 47

    /// 控件尺寸与间距
    private let sideControlSide: CGFloat = 28
    private let centerControlSide: CGFloat = 64
    private let controlGap: CGFloat = 48

    /// 控件行中心距安全区底边
    private let controlsCenterToSafeBottom: CGFloat = 79

    // MARK: - 正文窗口的固定排版

    /// 正文字号。**固定值，不跟随阅读器的字号设置** ——
    /// 播放器页的窗口只有 123pt 高，跟随大字号会退化成只看得见一行。
    private let bodyFontSize: CGFloat = 20

    /// 行高倍数（设计稿 1.6em）
    private let bodyLineHeightMultiple: CGFloat = 1.6

    /// 段后间距（设计稿 10）
    private let bodyParagraphSpacing: CGFloat = 10

    /// 窗口里额外带几段上下文。
    ///
    /// 取 1 是因为窗口只有 123pt（约 3 行）：当前句所在段落 + 前后各一段足够把窗口填满，
    /// 再多只是白排版。按**段落**而不是按字符数取，是为了让换行位置自然 ——
    /// 从段中间截断会让窗口第一行以半个词开头。
    private let contextParagraphCount = 1

    // MARK: - 依赖

    /// 朗读编排层。页面所有状态都问它要。
    private weak var speech: ReaderSpeechController?

    /// 书籍数据（书名、封面）。
    private weak var book: ReaderBookModel?

    /// 正文窗口的版位（固定高度），由 `layoutManually()` 算出、`reviseTextWindow()` 取用。
    private var textWindowBand: CGRect = .zero

    // MARK: - 子视图

    /// 背景：放大的书封。
    private lazy var backdropView: UIImageView = {

        let view = UIImageView()

        view.contentMode = .scaleAspectFill

        view.clipsToBounds = true

        return view
    }()

    /// 背景：高斯模糊。
    private lazy var blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))

    /// 背景：主题色罩。
    ///
    /// 设计稿是「模糊层本身带主题底色」，实现上拆成模糊 + 色罩两层 ——
    /// `UIVisualEffectView` 的 `backgroundColor` 会被它自己的材质覆盖，压不住。
    private lazy var tintView = UIView()

    /// 顶部向下箭头（收起本页）。
    private lazy var dismissControl: ReaderSpeechScreenChevron = {

        let view = ReaderSpeechScreenChevron()

        view.onTap = { [weak self] in self?.dismiss(animated: true) }

        return view
    }()

    private lazy var bookTitleLabel: UILabel = {

        let label = UILabel()

        label.numberOfLines = 1

        label.lineBreakMode = .byTruncatingTail

        return label
    }()

    private lazy var chapterTitleLabel: UILabel = {

        let label = UILabel()

        label.numberOfLines = 1

        label.lineBreakMode = .byTruncatingTail

        return label
    }()

    /// 书封。
    private lazy var coverView: UIImageView = {

        let view = UIImageView()

        view.contentMode = .scaleAspectFill

        view.layer.cornerRadius = coverRadius

        view.layer.masksToBounds = true

        return view
    }()

    /// 正文窗口的裁切容器。
    private lazy var textWindowView: UIView = {

        let view = UIView()

        view.clipsToBounds = true

        // 纯展示，不接手势：需求明确「自动跟随、不能手动滚」
        view.isUserInteractionEnabled = false

        return view
    }()

    /// 正文渲染视图。复用阅读页那一套 CoreText 绘制与朗读高亮。
    private lazy var textView = ReaderPageView()

    private lazy var previousControl: ReaderSpeechScreenSkipButton = {

        let view = ReaderSpeechScreenSkipButton(direction: .backward)

        view.onTap = { [weak self] in self?.speech?.skipToPreviousChapter() }

        return view
    }()

    private lazy var nextControl: ReaderSpeechScreenSkipButton = {

        let view = ReaderSpeechScreenSkipButton(direction: .forward)

        view.onTap = { [weak self] in self?.speech?.skipToNextChapter() }

        return view
    }()

    private lazy var toggleControl: ReaderSpeechScreenToggleButton = {

        let view = ReaderSpeechScreenToggleButton()

        view.onTap = { [weak self] in self?.handleToggle() }

        return view
    }()

    // MARK: - 下拉关闭

    /// 下拉关闭手势。
    private lazy var dismissPan: UIPanGestureRecognizer = {

        let pan = UIPanGestureRecognizer(target: self, action: #selector(screenDismissDragged))

        return pan
    }()

    /// 触发关闭的下拉距离，按屏高比例取。
    ///
    /// 用比例而不是固定 pt：小屏上固定阈值显得"怎么拖都关不掉"，大屏上又太灵敏。
    private static let dismissDistanceRatio: CGFloat = 0.22

    /// 触发关闭的下拉速度（pt/s）。快速下滑时不必拖够距离。
    private static let dismissVelocity: CGFloat = 1000

    // MARK: - 构造

    /// - Parameters:
    ///   - speech: 朗读编排层
    ///   - book: 书籍数据，用于书名与封面
    public init(speech: ReaderSpeechController, book: ReaderBookModel?) {

        self.speech = speech

        self.book = book

        super.init(nibName: nil, bundle: nil)

        // 从底部升起。设计稿顶部是向下箭头而非返回箭头，语义就是「收起」。
        //
        // 用 `.overFullScreen` 而不是 `.fullScreen`：后者会在转场结束后把阅读器从层级里摘掉，
        // 下拉关闭时跟手露出来的就是一片黑。`.overFullScreen` 保留下层，
        // 拖动过程中露出的是阅读器本身，才是「把这一页往下推走」的观感。
        modalPresentationStyle = .overFullScreen

        modalTransitionStyle = .coverVertical
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 生命周期

    open override func viewDidLoad() {

        super.viewDidLoad()

        setupSubviews()

        adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)

        reviseStaticContent()

        revise()
    }

    open override func viewDidLayoutSubviews() {

        super.viewDidLayoutSubviews()

        layoutManually()

        // 布局尺寸变化后正文窗口要重排（窗口宽度参与排版）
        reviseTextWindow()
    }

    private func setupSubviews() {

        view.backgroundColor = .clear

        view.addSubview(backdropView)

        view.addSubview(blurView)

        view.addSubview(tintView)

        view.addSubview(dismissControl)

        view.addSubview(bookTitleLabel)

        view.addSubview(chapterTitleLabel)

        view.addSubview(coverView)

        view.addSubview(textWindowView)

        textWindowView.addSubview(textView)

        view.addSubview(previousControl)

        view.addSubview(toggleControl)

        view.addSubview(nextControl)

        view.addGestureRecognizer(dismissPan)
    }

    // MARK: - 下拉关闭

    /// 跟手下拉关闭。
    ///
    /// 位移用 `transform` 而不是改 `frame`：`frame` 会触发 `layoutSubviews`，
    /// 而本页是手动布局的，每帧重算一次全部子视图纯属浪费，还会让正文窗口跟着重排。
    @objc private func screenDismissDragged(_ pan: UIPanGestureRecognizer) {

        let translation = pan.translation(in: view).y

        switch pan.state {

        case .changed:

            view.transform = CGAffineTransform(translationX: 0, y: resistedOffset(for: translation))

        case .ended:

            let velocity = pan.velocity(in: view).y

            let passedDistance = translation > view.bounds.height * Self.dismissDistanceRatio

            let passedVelocity = velocity > Self.dismissVelocity

            // 向上甩的时候不关，哪怕位移已经够（用户在往回收）
            if (passedDistance || passedVelocity), velocity > -Self.dismissVelocity {

                finishDismiss(fromOffset: resistedOffset(for: translation), velocity: velocity)

            }else{

                restorePosition()
            }

        case .cancelled, .failed:

            restorePosition()

        default:

            break
        }
    }

    /// 把原始位移换成实际位移：只跟向下，向上一律不动。
    ///
    /// **向上不能给橡皮筋。** 本页是 `.overFullScreen`，下层是阅读器；向上挪哪怕几 pt，
    /// 底边就会露出阅读器（菜单呼出时露的是菜单那一条），看起来像页面没铺满。
    /// 这与「列表顶部下拉」不是一回事 —— 那里橡皮筋露出的是同一个滚动容器的背景。
    private func resistedOffset(for translation: CGFloat) -> CGFloat {

        max(0, translation)
    }

    /// 顺着当前速度把页面推出屏幕，再无动画地 dismiss。
    ///
    /// 不直接 `dismiss(animated: true)`：那会让 UIKit 从**原始** frame 开始做转场动画，
    /// 而此刻页面已经被 transform 挪到半路，视觉上会先跳回原位再滑下去。
    private func finishDismiss(fromOffset offset: CGFloat, velocity: CGFloat) {

        let remaining = max(0, view.bounds.height - offset)

        // 用剩余距离除以当前速度估时长，这样松手瞬间的速度能延续下去，不会突然变快或变慢。
        // 夹在 0.16~0.4 之间：太短像闪断，太长像卡住。
        let duration = max(0.16, min(0.4, TimeInterval(remaining / max(600, velocity))))

        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {

            self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)

        } completion: { [weak self] _ in

            self?.dismiss(animated: false)
        }
    }

    /// 松手没到阈值，弹回原位。
    private func restorePosition() {

        UIView.animate(withDuration: 0.34,
                       delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {

            self.view.transform = .identity
        }
    }

    // MARK: - 布局

    /// 手动布局。
    ///
    /// 纵向策略是「上固定 + 下固定 + 中间弹性」：导航行与标题从上往下排、
    /// 控件行与正文窗口从下往上排，剩下的空隙留给书封居中。
    /// 直接照设计稿的绝对 y 摆会在非 812 高的屏幕上失准（小屏挤、大屏空）。
    private func layoutManually() {

        let width = view.bounds.width

        let height = view.bounds.height

        let safeTop = view.safeAreaInsets.top

        let safeBottom = view.safeAreaInsets.bottom

        backdropView.frame = view.bounds

        blurView.frame = view.bounds

        tintView.frame = view.bounds

        // 自上而下：导航行 → 标题 → 章节名
        dismissControl.frame = CGRect(x: horizontalMargin,
                                      y: safeTop + (headerHeight - ReaderSpeechScreenChevron.side) / 2,
                                      width: ReaderSpeechScreenChevron.side,
                                      height: ReaderSpeechScreenChevron.side)

        let titleWidth = width - horizontalMargin * 2

        let bookTitleHeight = ceil(bookTitleLabel.font.lineHeight)

        let chapterTitleHeight = ceil(chapterTitleLabel.font.lineHeight)

        let titleTop = safeTop + headerHeight + headerToTitleGap

        bookTitleLabel.frame = CGRect(x: horizontalMargin, y: titleTop,
                                      width: titleWidth, height: bookTitleHeight)

        chapterTitleLabel.frame = CGRect(x: horizontalMargin,
                                         y: bookTitleLabel.frame.maxY + 4,
                                         width: titleWidth,
                                         height: chapterTitleHeight)

        // 自下而上：控件行 → 正文窗口
        let controlsCenterY = height - safeBottom - controlsCenterToSafeBottom

        toggleControl.frame = CGRect(x: (width - centerControlSide) / 2,
                                     y: controlsCenterY - centerControlSide / 2,
                                     width: centerControlSide,
                                     height: centerControlSide)

        let sideY = controlsCenterY - sideControlSide / 2

        previousControl.frame = CGRect(x: toggleControl.frame.minX - controlGap - sideControlSide,
                                       y: sideY,
                                       width: sideControlSide,
                                       height: sideControlSide)

        nextControl.frame = CGRect(x: toggleControl.frame.maxX + controlGap,
                                   y: sideY,
                                   width: sideControlSide,
                                   height: sideControlSide)

        // 版位（固定 123）负责定位；窗口的实际高度由 `reviseTextWindow()` 按行边界定，
        // 并在版位内垂直居中
        let textWindowTop = toggleControl.frame.minY - textToControlsGap - textWindowBandHeight

        textWindowBand = CGRect(x: textWindowInset,
                                y: textWindowTop,
                                width: width - textWindowInset * 2,
                                height: textWindowBandHeight)

        // 先按版位铺满，`reviseTextWindow()` 会按行高收成整行
        textWindowView.frame = textWindowBand

        // 书封在标题与正文窗口之间居中
        let coverBandTop = chapterTitleLabel.frame.maxY

        let coverBandHeight = textWindowTop - coverTextInset - coverBandTop

        let coverY = coverBandTop + max(0, (coverBandHeight - coverSize.height) / 2)

        coverView.frame = CGRect(x: (width - coverSize.width) / 2,
                                 y: coverY,
                                 width: coverSize.width,
                                 height: coverSize.height)
    }

    // MARK: - 内容

    /// 填入整页生命周期内不变的内容。
    private func reviseStaticContent() {

        bookTitleLabel.text = book?.storyName

        let placeholder = ReaderEnvironment.images.coverPlaceholder()

        guard let url = book?.coverURL, !url.isEmpty else {

            coverView.image = placeholder

            backdropView.image = placeholder

            return
        }

        ReaderEnvironment.images.loadRemoteImage(coverView, url, placeholder)

        ReaderEnvironment.images.loadRemoteImage(backdropView, url, placeholder)
    }

    /// 按当前朗读状态刷新整页。
    ///
    /// 由阅读器在朗读状态变化时调用（逐句推进、暂停、继续、跨章都会走到）。
    open func revise() {

        let activity = speech?.activity ?? .idle

        // `.preparing` 按播放中呈现，口径与胶囊、dock 一致：
        // 用户点了播放、意图已生效，显示成播放中不算假状态
        toggleControl.isPlaying = activity != .paused && activity != .idle

        chapterTitleLabel.text = speech?.speakingChapterTitle

        // 边界置灰与锁屏同源：两侧按钮读的是同一套跳章目标解析
        previousControl.isEnabled = speech?.hasPreviousChapterForSkip ?? false

        nextControl.isEnabled = speech?.hasNextChapterForSkip ?? false

        reviseTextWindow()
    }

    /// 重排正文窗口并把当前朗读句居中。
    private func reviseTextWindow() {

        guard textWindowView.bounds.width > 0 else { return }

        guard let speech,
              let chapterText = speech.speakingChapterText,
              let sentenceRange = speech.speakingRange else {

            textView.isHidden = true

            return
        }

        textView.isHidden = false

        let full = chapterText as NSString

        guard sentenceRange.location >= 0,
              sentenceRange.location + sentenceRange.length <= full.length else { return }

        // 取「当前句所在段落 + 前后各若干段」作为窗口内容。
        // 按段落取而不是按字符数：从段中间截断会让窗口第一行以半个词开头。
        let windowRange = paragraphWindow(around: sentenceRange, in: full)

        let windowText = full.substring(with: windowRange)

        let attributed = NSAttributedString(string: windowText, attributes: bodyAttributes())

        let contentWidth = textWindowView.bounds.width

        let contentHeight = ReaderCoreText.attributedStringHeight(attrString: attributed, maxW: contentWidth)

        textView.adoptContent(attributed, typesetSize: CGSize(width: contentWidth, height: contentHeight))

        textView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        // 高亮范围要换算到窗口内坐标
        let localLocation = sentenceRange.location - windowRange.location

        textView.speechHighlightRange = NSRange(location: localLocation, length: sentenceRange.length)

        // 按真实行边界取一段满 `visibleLineCount` 行的可见区间
        guard let span = visibleLineSpan(containing: localLocation, contentHeight: contentHeight) else {

            // 取不到行信息（排版还没落定）：退回版位高度顶部对齐，下一次刷新会纠正
            textWindowView.frame = textWindowBand

            textView.frame.origin.y = 0

            return
        }

        // 窗口收成整行高度，并在版位内垂直居中 —— 这样书封与控件的位置不受行高差异影响
        var windowFrame = textWindowBand

        windowFrame.size.height = span.height

        windowFrame.origin.y = textWindowBand.midY - span.height / 2

        textWindowView.frame = windowFrame

        textView.frame.origin.y = -span.top
    }

    /// 求「包含指定字符、且占满 `visibleLineCount` 行」的可见区间。
    ///
    /// 直接按 `rect(forRange:)` 居中会露出半行：那个矩形是**句子**的，而句子可能跨行、
    /// 也可能只占一行的一部分，按它居中之后窗口上下边界落在行中间。
    /// 所以改为取 CTFrame 的行原点，按**行**对齐。
    ///
    /// - Returns: `top` 为区间顶边（相对正文视图），`height` 为区间高度；无行信息时为 nil。
    private func visibleLineSpan(containing location: Int, contentHeight: CGFloat) -> (top: CGFloat, height: CGFloat)? {

        guard let ctFrame = textView.ctFrame else { return nil }

        let lines = CTFrameGetLines(ctFrame) as? [CTLine] ?? []

        guard !lines.isEmpty else { return nil }

        var origins = [CGPoint](repeating: .zero, count: lines.count)

        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)

        // 每行的顶边与底边（CoreText 原点在左下、以基线计，这里翻成 UIKit 的自上而下）
        var tops: [CGFloat] = []

        var bottoms: [CGFloat] = []

        var targetIndex = 0

        for index in 0..<lines.count {

            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0

            CTLineGetTypographicBounds(lines[index], &ascent, &descent, &leading)

            let baselineY = contentHeight - origins[index].y

            tops.append(baselineY - ascent)

            bottoms.append(baselineY + descent)

            let range = CTLineGetStringRange(lines[index])

            if location >= range.location && location < range.location + range.length {

                targetIndex = index
            }
        }

        // 目标行**居中**：三行窗口里它落在第二行。靠近首尾时整段前移/后移，
        // 而不是让窗口越界（越界会在上下留白）
        let count = min(visibleLineCount, lines.count)

        var first = targetIndex - (count - 1) / 2

        first = max(0, min(first, lines.count - count))

        let last = first + count - 1

        return (top: tops[first], height: bottoms[last] - tops[first])
    }

    /// 求「当前句所在段落 + 前后各 `contextParagraphCount` 段」的范围。
    private func paragraphWindow(around sentenceRange: NSRange, in full: NSString) -> NSRange {

        var window = full.paragraphRange(for: NSRange(location: sentenceRange.location, length: 0))

        // 往前扩
        var cursor = window.location

        for _ in 0..<contextParagraphCount {

            guard cursor > 0 else { break }

            let previous = full.paragraphRange(for: NSRange(location: cursor - 1, length: 0))

            window = NSRange(location: previous.location,
                             length: window.location + window.length - previous.location)

            cursor = previous.location
        }

        // 往后扩
        var tail = window.location + window.length

        for _ in 0..<contextParagraphCount {

            guard tail < full.length else { break }

            let next = full.paragraphRange(for: NSRange(location: tail, length: 0))

            window = NSRange(location: window.location, length: next.location + next.length - window.location)

            tail = next.location + next.length
        }

        // 句子必须完整落在窗口里（跨段的句子会让上面的段落扩展不够）
        let sentenceEnd = sentenceRange.location + sentenceRange.length

        if sentenceEnd > window.location + window.length {

            window = NSRange(location: window.location, length: min(full.length, sentenceEnd) - window.location)
        }

        return window
    }

    /// 正文窗口的固定排版属性。
    private func bodyAttributes() -> [NSAttributedString.Key: Any] {

        let font = ReaderEnvironment.fonts.bodyText(bodyFontSize)

        let style = NSMutableParagraphStyle()

        style.alignment = .left

        // 行高按倍数折算成行间距：CoreText 走 `lineSpacing`，
        // `lineHeightMultiple` 在 CTFrame 里表现与 UILabel 不一致，不用它
        style.lineSpacing = max(0, bodyFontSize * bodyLineHeightMultiple - font.lineHeight)

        style.paragraphSpacing = bodyParagraphSpacing

        return [.font: font,
                .foregroundColor: ReaderConfiguration.shared().currentThemeColors.textBody,
                .paragraphStyle: style]
    }

    // MARK: - 换肤

    /// 应用阅读主题。
    ///
    /// 背景色罩取主题的页面底色（`page`）：设计稿两张图分别是 Gray 与另一套主题的底色，
    /// 规则就是「跟随当前阅读主题」而不是从书封取色 —— 那样六套主题自动都有值，
    /// 也不会出现深色正文配浅色底这种组合。
    open func adoptThemeColors(_ colors: ReaderTintPalette) {

        tintView.backgroundColor = colors.page.withAlphaComponent(Self.tintAlpha)

        // 明暗取自配置而非主题协议：给 `ReaderTintPalette` 加 `isDark` 会变成
        // 接入方必须实现的新成员（那个协议的实现由宿主提供），代价不值
        blurView.effect = UIBlurEffect(style: ReaderConfiguration.shared().isDarkTheme ? .dark : .light)

        bookTitleLabel.textColor = colors.textBody

        bookTitleLabel.font = ReaderEnvironment.fonts.uiRegular(16)

        chapterTitleLabel.textColor = colors.textFaint

        chapterTitleLabel.font = ReaderEnvironment.fonts.uiLight(12)

        dismissControl.adoptTintColor(colors.textBody)

        previousControl.adoptTintColor(colors.textBody)

        nextControl.adoptTintColor(colors.textBody)

        toggleControl.adoptTintColor(colors.textBody)

        // 正文颜色写在属性里，换肤要重排一次
        reviseTextWindow()
    }

    /// 背景色罩的不透明度。
    ///
    /// 设计稿上书封几乎看不出来，只留一点色调。0.88 是「能感觉到封面的冷暖、
    /// 但不干扰正文阅读」的取值；调低会让文字压在封面细节上不好读。
    private static let tintAlpha: CGFloat = 0.88

    // MARK: - 动作

    private func handleToggle() {

        guard let speech else { return }

        switch speech.activity {

        case .paused: speech.resume()

        case .preparing, .playing: speech.pause()

        case .idle: speech.startFromCurrentPage()
        }
    }
}

// MARK: - 顶部向下箭头

/// 收起本页的向下箭头。
///
/// 视觉只有 14×7.5，热区撑到 44×44 —— 按图形尺寸做热区远低于可点下限。
final class ReaderSpeechScreenChevron: UIView {

    /// 热区边长
    static let side: CGFloat = 44

    /// 设计稿：`M25 16.5 L32 24 L39 16.5`，即宽 14、高 7.5、描边 2、端头切平
    private let glyphSize = CGSize(width: 14, height: 7.5)
    private let strokeWidth: CGFloat = 2

    var onTap: (() -> Void)?

    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {

        super.init(frame: frame)

        shapeLayer.fillColor = nil

        shapeLayer.lineWidth = strokeWidth

        // 设计稿是 square 端头，不是 round
        shapeLayer.lineCap = .square

        layer.addSublayer(shapeLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chevronTapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        shapeLayer.frame = bounds

        let left = (bounds.width - glyphSize.width) / 2

        let top = (bounds.height - glyphSize.height) / 2

        let path = UIBezierPath()

        path.move(to: CGPoint(x: left, y: top))

        path.addLine(to: CGPoint(x: left + glyphSize.width / 2, y: top + glyphSize.height))

        path.addLine(to: CGPoint(x: left + glyphSize.width, y: top))

        shapeLayer.path = path.cgPath
    }

    func adoptTintColor(_ color: UIColor) { shapeLayer.strokeColor = color.cgColor }

    @objc private func chevronTapped() { onTap?() }
}

// MARK: - 上一章 / 下一章

/// 上一章 / 下一章按钮：一个实心三角 + 一根竖条。
///
/// 代码绘制而非切图：图形足够简单，且库内不带资源（见 BOUNDARY.md）。
/// 设计稿的三角尖端带极轻微的圆角（cubic），28pt 下与直角三角形肉眼无差，故按直线画。
final class ReaderSpeechScreenSkipButton: UIView {

    enum Direction { case backward, forward }

    /// 设计稿基准边长。所有坐标按它归一化后缩放到实际 bounds
    private static let designSide: CGFloat = 28

    /// 竖条：宽 2.33、高 16.33，纵向居中
    private static let barWidth: CGFloat = 2.333
    private static let barHeight: CGFloat = 16.333

    /// 三角：底边高 16.8，与竖条之间留 2.6 空隙
    private static let triangleBase: CGFloat = 16.8
    private static let triangleWidth: CGFloat = 12.6
    private static let barToTriangleGap: CGFloat = 2.6

    private let direction: Direction

    var onTap: (() -> Void)?

    /// 是否可用。首章 / 末章时置 false，与锁屏那两个按钮的置灰同源。
    var isEnabled: Bool = true {

        didSet {

            // 置灰用不透明度而不是换色：图形是单色路径，降透明度就是设计语言里的禁用态，
            // 且不需要为此多一个主题色槽
            alpha = isEnabled ? 1 : 0.3
        }
    }

    private let shapeLayer = CAShapeLayer()

    init(direction: Direction) {

        self.direction = direction

        super.init(frame: .zero)

        shapeLayer.strokeColor = nil

        layer.addSublayer(shapeLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(skipTapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        shapeLayer.frame = bounds

        let scale = min(bounds.width, bounds.height) / Self.designSide

        let centerY = bounds.midY

        let barWidth = Self.barWidth * scale

        let barHeight = Self.barHeight * scale

        let triangleWidth = Self.triangleWidth * scale

        let triangleBase = Self.triangleBase * scale

        let gap = Self.barToTriangleGap * scale

        // 整组（竖条 + 间隙 + 三角）水平居中
        let groupWidth = barWidth + gap + triangleWidth

        let groupLeft = (bounds.width - groupWidth) / 2

        let path = UIBezierPath()

        switch direction {

        case .backward:

            // 竖条在左，三角尖端朝左
            path.append(UIBezierPath(rect: CGRect(x: groupLeft,
                                                  y: centerY - barHeight / 2,
                                                  width: barWidth,
                                                  height: barHeight)))

            let apexX = groupLeft + barWidth + gap

            let baseX = apexX + triangleWidth

            path.move(to: CGPoint(x: apexX, y: centerY))

            path.addLine(to: CGPoint(x: baseX, y: centerY - triangleBase / 2))

            path.addLine(to: CGPoint(x: baseX, y: centerY + triangleBase / 2))

            path.close()

        case .forward:

            // 三角尖端朝右，竖条在右
            let baseX = groupLeft

            let apexX = baseX + triangleWidth

            path.move(to: CGPoint(x: apexX, y: centerY))

            path.addLine(to: CGPoint(x: baseX, y: centerY - triangleBase / 2))

            path.addLine(to: CGPoint(x: baseX, y: centerY + triangleBase / 2))

            path.close()

            path.append(UIBezierPath(rect: CGRect(x: apexX + gap,
                                                  y: centerY - barHeight / 2,
                                                  width: barWidth,
                                                  height: barHeight)))
        }

        shapeLayer.path = path.cgPath
    }

    /// 热区撑到 44×44：视觉只有 28，直接点很难命中。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {

        let minimum: CGFloat = 44

        let dx = max(0, (minimum - bounds.width) / 2)

        let dy = max(0, (minimum - bounds.height) / 2)

        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }

    func adoptTintColor(_ color: UIColor) { shapeLayer.fillColor = color.cgColor }

    @objc private func skipTapped() {

        guard isEnabled else { return }

        onTap?()
    }
}

// MARK: - 播放 / 暂停

/// 中央的播放 / 暂停按钮：描边圆圈 + 中央图标。
///
/// 设计稿只给了播放态（三角）。暂停态的两根竖条按三角的整体尺寸推出来，
/// 两态视觉重量才接近 —— 与 `ReaderSpeechDock` 里那个小控件同一处理方式。
final class ReaderSpeechScreenToggleButton: UIView {

    /// 设计稿基准边长
    private static let designSide: CGFloat = 64

    /// 圆环描边宽度（设计稿 3.05）
    private static let ringWidth: CGFloat = 3.048

    /// 播放三角：宽 22、底边高 23.6
    private static let triangleWidth: CGFloat = 22
    private static let triangleBase: CGFloat = 23.6

    /// 暂停竖条：宽 3.4、高 23.6、间距 6
    private static let barWidth: CGFloat = 3.4
    private static let barHeight: CGFloat = 23.6
    private static let barGap: CGFloat = 6

    var onTap: (() -> Void)?

    /// true 显示暂停图标（当前在播），false 显示播放图标。
    var isPlaying: Bool = false {

        didSet { reviseGlyph() }
    }

    private let ringLayer = CAShapeLayer()

    private let glyphLayer = CAShapeLayer()

    private var tint: UIColor = .black

    override init(frame: CGRect) {

        super.init(frame: frame)

        ringLayer.fillColor = nil

        layer.addSublayer(ringLayer)

        glyphLayer.strokeColor = nil

        layer.addSublayer(glyphLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(playToggleTapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {

        super.layoutSubviews()

        let scale = min(bounds.width, bounds.height) / Self.designSide

        let lineWidth = Self.ringWidth * scale

        ringLayer.frame = bounds

        ringLayer.lineWidth = lineWidth

        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2

        ringLayer.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                                      radius: radius,
                                      startAngle: 0,
                                      endAngle: .pi * 2,
                                      clockwise: true).cgPath

        glyphLayer.frame = bounds

        reviseGlyph()
    }

    private func reviseGlyph() {

        guard bounds.width > 0 else { return }

        let scale = min(bounds.width, bounds.height) / Self.designSide

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let path = UIBezierPath()

        if isPlaying {

            let barWidth = Self.barWidth * scale

            let barHeight = Self.barHeight * scale

            let gap = Self.barGap * scale

            let totalWidth = barWidth * 2 + gap

            let left = center.x - totalWidth / 2

            let top = center.y - barHeight / 2

            path.append(UIBezierPath(rect: CGRect(x: left, y: top, width: barWidth, height: barHeight)))

            path.append(UIBezierPath(rect: CGRect(x: left + barWidth + gap, y: top,
                                                  width: barWidth, height: barHeight)))

        }else{

            let width = Self.triangleWidth * scale

            let base = Self.triangleBase * scale

            // 三角**视觉居中**要比几何居中略右偏：尖端朝右的三角形重心偏左，
            // 按外接矩形居中会显得整体偏左。偏移取宽度的 8%，是常见的光学修正量
            let left = center.x - width / 2 + width * 0.08

            path.move(to: CGPoint(x: left, y: center.y - base / 2))

            path.addLine(to: CGPoint(x: left, y: center.y + base / 2))

            path.addLine(to: CGPoint(x: left + width, y: center.y))

            path.close()
        }

        glyphLayer.path = path.cgPath
    }

    func adoptTintColor(_ color: UIColor) {

        tint = color

        ringLayer.strokeColor = color.cgColor

        glyphLayer.fillColor = color.cgColor
    }

    @objc private func playToggleTapped() { onTap?() }
}
