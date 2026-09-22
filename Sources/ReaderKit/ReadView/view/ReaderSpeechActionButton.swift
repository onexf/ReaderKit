//
//  ReaderSpeechActionButton.swift
//  ReaderKit
//
//  朗读控制胶囊：一个四态复用的悬浮控件，位于正文页脚上方居中。
//
//  四个状态与内容（尺寸色值来自设计稿，见 .kiro/specs/readerkit-tts/design.md 2.1）：
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │ .idle     │ 🎧 从这里开始读                                  │
//  │ .playing  │ ⏸ 暂停                                          │
//  │ .paused   │ ▶ 继续                                          │
//  │ .offPage  │ ↩ │ 🎧 从这里开始读     ← 多出「回到朗读位置」段  │
//  └─────────────────────────────────────────────────────────────┘
//
//  `.offPage` 是「正在朗读，但用户已手动翻到别页」。此时胶囊有**两个独立点击区**：
//  左侧箭头回到朗读位置，右侧从当前页重新开始读。其余状态只有一个点击区。
//
//  布局用手动 frame 而非 Auto Layout：本库全部 22 个自绘视图都是手动 frame，
//  混用两套布局体系会让维护者每进一个文件都要先分辨用的是哪套。手动 frame 在这里
//  也更顺手 —— 状态切换时胶囊宽度会变，直接对 frame 做动画比改约束再 layout 更直观。
//

import UIKit

/// 朗读控制胶囊的状态。
public enum ReaderSpeechActionState: Equatable {

    /// 未朗读。
    case idle

    /// 正在朗读，且朗读位置在当前展示页。
    case playing

    /// 已暂停，且朗读位置在当前展示页。
    case paused

    /// 正在朗读（或已暂停），但朗读位置不在当前展示页。
    case offPage
}

/// 朗读控制胶囊。
open class ReaderSpeechActionButton: UIView {

    // MARK: - 设计稿尺寸

    /// 胶囊高度
    public static let capsuleHeight: CGFloat = 32

    /// 胶囊圆角
    private let capsuleRadius: CGFloat = 6

    /// 左右内边距
    private let horizontalInset: CGFloat = 12

    /// 元素间距
    private let itemGap: CGFloat = 4

    /// 图标边长（返回箭头与主图标同尺寸）
    private let iconSide: CGFloat = 16

    /// 分隔线尺寸
    private let dividerSize = CGSize(width: 1, height: 13)

    /// 文字字号
    private let titleFontSize: CGFloat = 12

    // MARK: - 对外

    /// 当前状态。改这个属性等同于 `apply(_:animated:)` 且带动画。
    public private(set) var state: ReaderSpeechActionState = .idle

    /// 点击主区域（从这里开始读 / 暂停 / 继续）。
    open var onPrimaryAction: (() -> Void)?

    /// 点击左侧箭头（回到朗读位置）。仅 `.offPage` 状态下可触发。
    open var onReturnAction: (() -> Void)?

    /// 胶囊的中心锚点。
    ///
    /// 由持有方设定（通常是「水平居中、纵向贴页脚上方」）。胶囊宽度随状态变化，
    /// 但**中心保持不动**，所以让视图自己按锚点算 frame，比让持有方每次重算更可靠。
    open var anchorCenter: CGPoint = .zero {

        didSet { reviseGeometry(animated: false) }
    }

    // MARK: - 子视图

    /// 回到朗读位置。整个左段的点击区。
    private lazy var returnControl: UIControl = {
        let control = UIControl()
        control.addAction(UIAction { [weak self] _ in self?.onReturnAction?() }, for: .touchUpInside)
        return control
    }()

    private lazy var returnIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var dividerView = UIView()

    /// 主区域点击区。覆盖分隔线右侧的全部范围。
    private lazy var primaryControl: UIControl = {
        let control = UIControl()
        control.addAction(UIAction { [weak self] _ in self?.onPrimaryAction?() }, for: .touchUpInside)
        return control
    }()

    private lazy var primaryIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        return label
    }()

    // MARK: - 构造

    public override init(frame: CGRect) {

        super.init(frame: frame)

        layer.cornerRadius = capsuleRadius

        layer.masksToBounds = true

        addSubview(returnControl)

        returnControl.addSubview(returnIconView)

        addSubview(dividerView)

        addSubview(primaryControl)

        primaryControl.addSubview(primaryIconView)

        primaryControl.addSubview(titleLabel)

        adoptThemeColors(ReaderConfiguration.shared().currentThemeColors)

        applyContent(for: state)

        reviseGeometry(animated: false)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 状态

    /// 切换到指定状态。
    ///
    /// - Parameter animated: 是否走动画。首次布局与主题切换时传 false。
    open func apply(_ newState: ReaderSpeechActionState, animated: Bool) {

        guard newState != state else { return }

        let showedReturn = state == .offPage

        state = newState

        // 图标与文字用交叉溶解换，而不是直接赋值：直接赋值时「暂停 → 继续」会硬切，
        // 在一个只有 32pt 高的小控件上很扎眼。
        if animated {

            UIView.transition(with: primaryIconView,
                              duration: READER_MENU_MOTION_TIME,
                              options: [.transitionCrossDissolve, READER_MENU_MOTION_OPTIONS],
                              animations: { self.applyContent(for: newState) })

            UIView.transition(with: titleLabel,
                              duration: READER_MENU_MOTION_TIME,
                              options: [.transitionCrossDissolve, READER_MENU_MOTION_OPTIONS],
                              animations: {})

        }else{

            applyContent(for: newState)
        }

        // 返回段的出现 / 消失单独淡入淡出。它和宽度动画同时跑：
        // 宽度从 136 变到 161 的同时箭头淡入，观感是胶囊「长出」左段。
        let willShowReturn = newState == .offPage

        if showedReturn != willShowReturn {

            if willShowReturn {

                returnControl.alpha = 0

                dividerView.alpha = 0

                returnControl.isHidden = false

                dividerView.isHidden = false
            }

            let alterAlpha = {

                self.returnControl.alpha = willShowReturn ? 1 : 0

                self.dividerView.alpha = willShowReturn ? 1 : 0
            }

            if animated {

                UIView.animate(withDuration: READER_MENU_MOTION_TIME,
                               delay: 0,
                               options: READER_MENU_MOTION_OPTIONS,
                               animations: alterAlpha) { _ in

                    self.returnControl.isHidden = !willShowReturn

                    self.dividerView.isHidden = !willShowReturn
                }

            }else{

                alterAlpha()

                returnControl.isHidden = !willShowReturn

                dividerView.isHidden = !willShowReturn
            }
        }

        reviseGeometry(animated: animated)
    }

    /// 按状态填充图标与文字。
    private func applyContent(for state: ReaderSpeechActionState) {

        let images = ReaderEnvironment.images

        let strings = ReaderEnvironment.strings

        switch state {

        case .idle, .offPage:

            primaryIconView.image = images.speechPlay()

            titleLabel.text = strings.speechStartHere

        case .playing:

            primaryIconView.image = images.speechPause()

            titleLabel.text = strings.speechPause

        case .paused:

            primaryIconView.image = images.speechResume()

            titleLabel.text = strings.speechResume
        }

        returnIconView.image = images.speechReturnToPlaying()
    }

    // MARK: - 布局

    /// 当前状态下胶囊的宽度。
    ///
    /// 宽度是内容撑出来的（设计稿里是 hug），所以每次状态变化都要重算。
    open var preferredWidth: CGFloat {

        var width = horizontalInset

        if state == .offPage {

            width += iconSide + itemGap + dividerSize.width + itemGap
        }

        width += iconSide + itemGap + titleWidth + horizontalInset

        return ceil(width)
    }

    /// 文字所需宽度。
    private var titleWidth: CGFloat {

        guard let text = titleLabel.text, !text.isEmpty else { return 0 }

        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: Self.capsuleHeight),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: titleLabel.font as Any],
            context: nil
        )

        return ceil(bounding.width)
    }

    /// 按锚点与当前内容重算 frame 与内部布局。
    private func reviseGeometry(animated: Bool) {

        let target = CGRect(x: anchorCenter.x - preferredWidth / 2,
                            y: anchorCenter.y - Self.capsuleHeight / 2,
                            width: preferredWidth,
                            height: Self.capsuleHeight)

        guard animated else {

            frame = target

            setNeedsLayout()

            layoutIfNeeded()

            return
        }

        UIView.animate(withDuration: READER_MENU_MOTION_TIME,
                       delay: 0,
                       options: READER_MENU_MOTION_OPTIONS) {

            self.frame = target

            self.layoutIfNeeded()
        }
    }

    open override func layoutSubviews() {

        super.layoutSubviews()

        var cursor = horizontalInset

        if state == .offPage {

            // 返回段的点击区从胶囊左边缘一直吃到分隔线之前，
            // 不只是图标那 16pt —— 16pt 的点击区在真机上很难点中
            returnControl.frame = CGRect(x: 0,
                                        y: 0,
                                        width: horizontalInset + iconSide + itemGap,
                                        height: bounds.height)

            returnIconView.frame = CGRect(x: horizontalInset,
                                          y: (bounds.height - iconSide) / 2,
                                          width: iconSide,
                                          height: iconSide)

            cursor += iconSide + itemGap

            dividerView.frame = CGRect(x: cursor,
                                       y: (bounds.height - dividerSize.height) / 2,
                                       width: dividerSize.width,
                                       height: dividerSize.height)

            cursor += dividerSize.width + itemGap
        }

        // 主区域点击区吃掉分隔线右侧到胶囊右边缘的全部范围
        primaryControl.frame = CGRect(x: cursor,
                                      y: 0,
                                      width: max(0, bounds.width - cursor),
                                      height: bounds.height)

        primaryIconView.frame = CGRect(x: 0,
                                       y: (primaryControl.bounds.height - iconSide) / 2,
                                       width: iconSide,
                                       height: iconSide)

        titleLabel.frame = CGRect(x: iconSide + itemGap,
                                  y: 0,
                                  width: max(0, primaryControl.bounds.width - iconSide - itemGap - horizontalInset),
                                  height: primaryControl.bounds.height)
    }

    // MARK: - 主题换肤

    open func adoptThemeColors(_ colors: ReaderThemeColors) {

        backgroundColor = colors.speechCapsuleFill

        dividerView.backgroundColor = colors.speechCapsuleDivider

        titleLabel.textColor = colors.speechCapsuleText

        titleLabel.font = ReaderEnvironment.fonts.uiRegular(readerScaled(titleFontSize))

        // 图标按 template 提供（`ReaderImages` 的约定），这里统一染色即可跟随主题
        primaryIconView.tintColor = colors.speechCapsuleText

        returnIconView.tintColor = colors.speechCapsuleText

        // 字体可能随主题一起变，重算宽度
        reviseGeometry(animated: false)
    }

    // MARK: - 事件


}
