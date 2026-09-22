//
//  ReaderBookmarkDeleteSheet.swift
//  ReaderKit
//
//  书签长按删除底部弹层 + "全部清除"确认弹窗
//  对照 Figma:
//  - 底部 sheet(10481-37152 → 11091:10296):拖拽条 + Remove(红) / Clear All(红) / Cancel(深),0.7 遮罩
//  - 全部清除确认(11011-47268):居中弹窗 + Confirm / Cancel
//

import UIKit

// MARK: - 删除底部弹层

final public class ReaderBookmarkDeleteSheet: UIView {

    private let dimView = UIControl()
    private let containerView = UIView()
    private let handleBar = UIView()
    // 文案 label(负责精确视觉位置) + 透明按钮(负责点击热区)
    private let removeLabel = UILabel()
    private let clearAllLabel = UILabel()
    private let cancelLabel = UILabel()
    private let removeButton = UIButton(type: .custom)
    private let clearAllButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .custom)
    private let divider1 = UIView()
    private let divider2 = UIView()

    private var onRemove: (() -> Void)?
    private var onClearAll: (() -> Void)?
    private var onClearAllClick: (() -> Void)?
    private var onCancel: (() -> Void)?

    /// 是否正在执行展开/收起动画(动画期间跳过容器重排,避免 transform 与 frame 冲突导致动画诡异)
    private var isAnimating = false

    /// 危险操作（删除）的强调色。用系统语义色而非硬编码，随系统与深色模式适配。
    private let redColor = UIColor.systemRed

    /// 在 window 上弹出删除 sheet
    /// - Parameters:
    ///   - onRemove: 点击 Remove(删除当前书签)
    ///   - onClearAll: Clear All 二次确认后回调(真正执行清除)
    ///   - onClearAllClick: 点击 Clear All 按钮即回调(用于点击埋点,早于二次确认)
    ///   - onCancel: 取消(点击 Cancel 或点遮罩关闭)
    public static func show(onRemove: @escaping () -> Void,
                     onClearAll: @escaping () -> Void,
                     onClearAllClick: (() -> Void)? = nil,
                     onCancel: (() -> Void)? = nil) {
        guard let window = ReaderScreenMetrics.keyWindow else { return }
        let sheet = ReaderBookmarkDeleteSheet(frame: window.bounds)
        sheet.onRemove = onRemove
        sheet.onClearAll = onClearAll
        sheet.onClearAllClick = onClearAllClick
        sheet.onCancel = onCancel
        window.addSubview(sheet)
        sheet.present()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    private func configureViews() {

        let themeColors = ReaderConfiguration.shared().currentThemeColors

        // 遮罩
        dimView.frame = bounds
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        dimView.alpha = 0
        dimView.addAction(UIAction { [weak self] _ in self?.dismissSheet() }, for: .touchUpInside)
        addSubview(dimView)

        // 容器(底部白卡,顶部圆角 28)
        containerView.backgroundColor = themeColors.fillPopup
        containerView.layer.cornerRadius = 28
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.clipsToBounds = true
        addSubview(containerView)

        // 拖拽条(Figma:32 x 4,#C5C5C5,距顶 10)
        handleBar.backgroundColor = ReaderConfiguration.shared().currentThemeColors.dividerLine
        handleBar.layer.cornerRadius = 2
        containerView.addSubview(handleBar)

        // 选项文案使用同步后的多语言 key(Lexend Deca Regular 16,Remove/Clear All 红,Cancel 主题深色)
        configureChoiceLabel(removeLabel, title: ReaderEnvironment.strings.bookmarkDeleteOne, color: redColor)
        configureChoiceLabel(clearAllLabel, title: ReaderEnvironment.strings.bookmarkDeleteAll, color: redColor)
        configureChoiceLabel(cancelLabel, title: ReaderEnvironment.strings.cancel, color: themeColors.textT1)

        // 分割线(Figma:通栏 #E6E6E6,走主题分割线色)
        divider1.backgroundColor = themeColors.dividerLine
        divider2.backgroundColor = themeColors.dividerLine
        containerView.addSubview(divider1)
        containerView.addSubview(divider2)

        // 透明点击热区(覆盖整行,叠在 label 之上)
        configurePressBtn(removeButton) { [weak self] in self?.handleRemove() }
        configurePressBtn(clearAllButton) { [weak self] in self?.handleClearAll() }
        configurePressBtn(cancelButton) { [weak self] in self?.handleCancel() }
    }

    private func configureChoiceLabel(_ label: UILabel, title: String, color: UIColor) {
        label.text = title
        label.textColor = color
        label.font = ReaderEnvironment.fonts.uiRegular(16)
        label.textAlignment = .center
        containerView.addSubview(label)
    }

    private func configurePressBtn(_ button: UIButton, action: @escaping () -> Void) {
        button.backgroundColor = .clear
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        containerView.addSubview(button)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds

        // 动画期间不重排容器(容器用 transform 做位移,此时再设 frame 会与 transform 冲突)
        if isAnimating { return }

        let safeBottom = ReaderScreenMetrics.safeAreaBottom
        let w = bounds.width

        // Figma 标注(node 11975-61555),整体高 196:
        // 拖拽条距顶 10,其后选项区起点 30
        // 选项文案行高 24、行间距 32(中心间距 56),分割线居于两行中心之间
        // 选项区底部 padding 30(已覆盖 Home Indicator 区域,不再额外叠加安全区)
        let handleTop: CGFloat = 10
        let handleHeight: CGFloat = 4
        let optionsTop: CGFloat = 30
        let textHeight: CGFloat = 24
        let centerSpacing: CGFloat = 56                            // 24 文案 + 32 间距
        // 底部留白:取设计稿 30 与设备安全区中较大者,避免叠加导致 sheet 偏高
        let bottomPadding: CGFloat = max(30, safeBottom)

        // 三行文案中心(相对容器顶部)
        let center1 = optionsTop + textHeight / 2                  // 42
        let center2 = center1 + centerSpacing                      // 98
        let center3 = center2 + centerSpacing                      // 154
        let divider1Y = (center1 + center2) / 2                    // 70
        let divider2Y = (center2 + center3) / 2                    // 126

        let contentHeight = center3 + textHeight / 2 + bottomPadding

        containerView.frame = CGRect(x: 0, y: bounds.height - contentHeight,
                                     width: w, height: contentHeight)

        handleBar.frame = CGRect(x: (w - 32) / 2, y: handleTop, width: 32, height: handleHeight)

        // 文案 label(通栏居中)
        removeLabel.frame = CGRect(x: 20, y: center1 - textHeight / 2, width: w - 40, height: textHeight)
        clearAllLabel.frame = CGRect(x: 20, y: center2 - textHeight / 2, width: w - 40, height: textHeight)
        cancelLabel.frame = CGRect(x: 20, y: center3 - textHeight / 2, width: w - 40, height: textHeight)

        // 分割线通栏(x:0,宽度铺满)
        let hairline = 1.0 / UIScreen.main.scale
        divider1.frame = CGRect(x: 0, y: divider1Y, width: w, height: hairline)
        divider2.frame = CGRect(x: 0, y: divider2Y, width: w, height: hairline)

        // 点击热区(以分割线/边界划分,文案居中其中)
        removeButton.frame = CGRect(x: 0, y: handleTop + handleHeight, width: w, height: divider1Y - (handleTop + handleHeight))
        clearAllButton.frame = CGRect(x: 0, y: divider1Y, width: w, height: divider2Y - divider1Y)
        cancelButton.frame = CGRect(x: 0, y: divider2Y, width: w, height: center3 + textHeight / 2 - divider2Y)
    }

    // MARK: - 动画

    private func present() {
        layoutIfNeeded()
        isAnimating = true
        containerView.transform = CGAffineTransform(translationX: 0, y: containerView.frame.height)
        UIView.animate(withDuration: 0.25, animations: {
            self.dimView.alpha = 1
            self.containerView.transform = .identity
        }) { _ in
            self.isAnimating = false
        }
    }

    private func dismissSheet() {
        isAnimating = true
        UIView.animate(withDuration: 0.25, animations: {
            self.dimView.alpha = 0
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.containerView.frame.height)
        }) { _ in
            self.removeFromSuperview()
        }
    }
    
    /// 点击 Cancel 按钮:上报取消(点遮罩关闭不算 Cancel 点击,不上报)
    private func handleCancel() {
        let cb = onCancel
        dismissThen { cb?() }
    }

    private func handleRemove() {
        let cb = onRemove
        dismissThen { cb?() }
    }

    private func handleClearAll() {
        // 点击 Clear All 即上报点击(早于二次确认框,确认与否都算点过)
        onClearAllClick?()
        // 关闭 sheet 后弹出"全部清除"确认弹窗,确认后才真正清除
        let cb = onClearAll
        dismissThen {
            ReaderBookmarkClearAllAlert.show(onConfirm: { cb?() })
        }
    }

    private func dismissThen(_ completion: @escaping () -> Void) {
        isAnimating = true
        UIView.animate(withDuration: 0.25, animations: {
            self.dimView.alpha = 0
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.containerView.frame.height)
        }) { _ in
            self.removeFromSuperview()
            completion()
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 全部清除确认弹窗

final public class ReaderBookmarkClearAllAlert: UIView {

    private let dimView = UIControl()
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let confirmButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .custom)

    private var onConfirm: (() -> Void)?

    public static func show(onConfirm: @escaping () -> Void) {
        guard let window = ReaderScreenMetrics.keyWindow else { return }
        let alert = ReaderBookmarkClearAllAlert(frame: window.bounds)
        alert.onConfirm = onConfirm
        window.addSubview(alert)
        alert.present()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    private func configureViews() {
        // 跟随阅读器当前主题做配色适配，六套主题统一走语义 token：
        //   卡片背景 -> fillPopup;标题/Confirm 文字 -> textT1;Confirm 底 -> fill;Cancel 底 -> fill2(强调填充);Cancel 字固定白色
        let theme = ReaderConfiguration.shared().currentThemeColors

        let cardBgColor: UIColor = theme.fillPopup
        let titleColor: UIColor = theme.textT1
        let confirmBgColor: UIColor = theme.fill
        let confirmTextColor: UIColor = theme.textT1
        let cancelBgColor: UIColor = theme.fill2

        dimView.frame = bounds
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        dimView.alpha = 0
        dimView.addAction(UIAction { [weak self] _ in self?.dismissAlert() }, for: .touchUpInside)
        addSubview(dimView)

        // 卡片背景
        cardView.backgroundColor = cardBgColor
        cardView.layer.cornerRadius = 16
        cardView.clipsToBounds = true
        addSubview(cardView)

        // 标题与按钮文案使用同步后的多语言 key
        titleLabel.text = ReaderEnvironment.strings.bookmarkDeleteAlertTitle
        titleLabel.font = ReaderEnvironment.fonts.uiRegular(14)
        titleLabel.textColor = titleColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        cardView.addSubview(titleLabel)

        // Confirm:填充底 + 主文字色
        confirmButton.setTitle(ReaderEnvironment.strings.bookmarkDeleteAlertConfirm, for: .normal)
        confirmButton.setTitleColor(confirmTextColor, for: .normal)
        confirmButton.titleLabel?.font = ReaderEnvironment.fonts.uiMedium(16)
        confirmButton.backgroundColor = confirmBgColor
        confirmButton.layer.cornerRadius = 24
        confirmButton.clipsToBounds = true
        confirmButton.addAction(UIAction { [weak self] _ in self?.handleConfirm() }, for: .touchUpInside)
        cardView.addSubview(confirmButton)

        // Cancel:强调底 + 固定白字
        cancelButton.setTitle(ReaderEnvironment.strings.cancel, for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = ReaderEnvironment.fonts.uiMedium(16)
        cancelButton.backgroundColor = cancelBgColor
        cancelButton.layer.cornerRadius = 24
        cancelButton.clipsToBounds = true
        cancelButton.addAction(UIAction { [weak self] _ in self?.dismissAlert() }, for: .touchUpInside)
        cardView.addSubview(cancelButton)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds

        let cardWidth: CGFloat = 295
        let padding: CGFloat = 20
        let titleWidth = cardWidth - padding * 2
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height
        let buttonHeight: CGFloat = 48
        let cardHeight = padding + titleHeight + 20 + buttonHeight + padding

        cardView.frame = CGRect(x: (bounds.width - cardWidth) / 2,
                                y: (bounds.height - cardHeight) / 2,
                                width: cardWidth, height: cardHeight)

        titleLabel.frame = CGRect(x: padding, y: padding, width: titleWidth, height: titleHeight)

        let gap: CGFloat = 8
        let btnWidth = (cardWidth - padding * 2 - gap) / 2
        let btnY = titleLabel.frame.maxY + 20
        confirmButton.frame = CGRect(x: padding, y: btnY, width: btnWidth, height: buttonHeight)
        cancelButton.frame = CGRect(x: confirmButton.frame.maxX + gap, y: btnY, width: btnWidth, height: buttonHeight)
    }

    private func present() {
        cardView.alpha = 0
        cardView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.2) {
            self.dimView.alpha = 1
            self.cardView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    private func dismissAlert() {
        UIView.animate(withDuration: 0.2, animations: {
            self.dimView.alpha = 0
            self.cardView.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }

    private func handleConfirm() {
        let cb = onConfirm
        UIView.animate(withDuration: 0.2, animations: {
            self.dimView.alpha = 0
            self.cardView.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            cb?()
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
