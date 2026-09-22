//
//  ReaderMenuSettingsPanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/08.
//

import UIKit

/// 行高百分比最小值
private let kLineHeightPercentMin: Int = 120
/// 行高百分比最大值
private let kLineHeightPercentMax: Int = 200
/// 行高百分比步进
private let kLineHeightPercentStep: Int = 10

// MARK: - 设置面板设计稿尺寸

/// 面板左右安全边距
private let kPanelMargin: CGFloat = 20
/// 面板顶部留白（底部留白由 tab 栏自带的 20 顶部留白承担）
private let kPanelTopPadding: CGFloat = 20
/// 行与行之间的间距
private let kPanelRowGap: CGFloat = 16
/// 第一行（行高滑块）高度
private let kLineHeightRowHeight: CGFloat = 24
/// 第二行（字号）高度
private let kFontSizeRowHeight: CGFloat = 50
/// 第三行（主题色块）高度
private let kBgColorRowHeight: CGFloat = 50
/// 第四行（阅读方向）高度
private let kReadingModeRowHeight: CGFloat = 40
/// 行高滑块两侧图标尺寸
private let kLineHeightIconSize: CGFloat = 24
/// 行高滑块与两侧图标的间距
private let kLineHeightIconGap: CGFloat = 12
/// 字号胶囊按钮高度（宽度按剩余空间均分，375 宽下等于设计稿的 118）
private let kFontSizeButtonHeight: CGFloat = 30
/// 字号行内元素间距
private let kFontSizeRowGap: CGFloat = 20
/// "Size" 标题宽度
private let kFontSizeTitleWidth: CGFloat = 24
/// 字号数值宽度
private let kFontSizeValueWidth: CGFloat = 15
/// 主题色块直径
private let kBgColorSwatchSize: CGFloat = 36
/// 阅读方向分段控件内边距
private let kReadingModeInset: CGFloat = 4
/// 阅读方向两段之间的间距
private let kReadingModeSegmentGap: CGFloat = 4

open class ReaderMenuSettingsPanel: ReaderMenuPanel, ReaderMenuTabRailDelegate {

    // MARK: - 设置面板容器（Setting 激活时显示）
    
    /// 设置面板整体容器
    private var settingPanelView: UIView!
    
    /// 设置面板是否处于展开态
    ///
    /// 不用 `settingPanelView.isHidden` 当状态位：收起动画期间面板必须还看得见（靠
    /// bottomView 裁剪逐步遮住），等动画结束再真正隐藏，否则会直接“啪”一下消失。
    private var isSettingPanelExpanded: Bool = false
    
    // MARK: - 第一行：行高滑块
    
    /// 行高行容器
    private var lineHeightRowView: UIView!
    /// 行高减小图标按钮
    private var lineHeightDecreaseButton: UIButton!
    /// 行高滑块
    private var lineHeightSlider: ReaderLineHeightSlider!
    /// 行高增大图标按钮
    private var lineHeightIncreaseButton: UIButton!
    
    // MARK: - 第二行：字号
    
    /// 字号行容器
    private var fontSizeRowView: UIView!
    /// "Size" 标题
    private var fontSizeTitleLabel: UILabel!
    /// A- 胶囊按钮
    private var decreaseButton: UIButton!
    /// 当前字号
    private var fontSizeLabel: UILabel!
    /// A+ 胶囊按钮
    private var increaseButton: UIButton!
    
    // MARK: - 第三行：阅读背景主题色块
    
    /// 背景模式容器
    private var bgColorRowView: UIView!
    /// 背景色圆形按钮数组，顺序与 ReaderThemeType.swatchOrder 一致
    private var bgColorButtons: [UIButton] = []
    
    // MARK: - 第四行：阅读方向（上下滑动 / 左右翻页）
    
    /// 阅读方向分段控件容器（带 1pt 边框的胶囊）
    private var readingModeRowView: UIView!
    /// 上下滑动按钮（滚动模式）
    private var verticalModeButton: UIButton!
    /// 左右翻页按钮（平移模式）
    private var horizontalModeButton: UIButton!
    
    /// 底部按钮栏（目录 / 日夜间 / 设置）
    public private(set) var bottomTabBar: ReaderMenuTabRail!
    
    public override init(frame: CGRect) { super.init(frame: frame) }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        backgroundColor = ReaderConfiguration.shared().bgColor
        
        setupSettingPanel()
        setupBottomTabBar()
    }

    // MARK: - 设置面板搭建
    
    private func setupSettingPanel() {
        
        // 设置面板容器（设计稿里面板与 tab 栏是同一块连续表面，所以不再画顶部分割线）
        settingPanelView = UIView()
        settingPanelView.backgroundColor = .clear
        settingPanelView.isHidden = true
        addSubview(settingPanelView)
        
        // 第一行：行高滑块
        lineHeightRowView = UIView()
        settingPanelView.addSubview(lineHeightRowView)
        
        setupLineHeightControls()
        
        // 第二行：字号
        fontSizeRowView = UIView()
        settingPanelView.addSubview(fontSizeRowView)
        
        setupFontSizeControls()
        
        // 第三行：阅读背景主题色块
        bgColorRowView = UIView()
        settingPanelView.addSubview(bgColorRowView)
        
        setupBgColorButtons()
        
        // 第四行：阅读方向分段控件
        readingModeRowView = UIView()
        readingModeRowView.layer.borderWidth = 1
        // 边框色必须在这里就给：adoptThemeColors 只在切换主题时才调，
        // 首次显示不走那条路，漏设就会渲染成 CALayer 默认的黑色边框
        readingModeRowView.layer.borderColor = ReaderConfiguration.shared().currentThemeColors.dividerLine.cgColor
        readingModeRowView.layer.masksToBounds = true
        settingPanelView.addSubview(readingModeRowView)
        
        setupReadingModeButtons()
        
        // 首次显示前先把可用/禁用态刷一遍（字号或行高可能已经停在边界值上）
        reviseBtnStates()
    }
    
    /// 搭建字号调整控件（Size 标题 + A- 胶囊 + 数值 + A+ 胶囊）
    private func setupFontSizeControls() {
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        // "Size" 标题
        fontSizeTitleLabel = UILabel()
        fontSizeTitleLabel.text = ReaderEnvironment.strings.settingSize
        fontSizeTitleLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        fontSizeTitleLabel.textColor = themeColors.textT1
        fontSizeTitleLabel.textAlignment = .left
        fontSizeRowView.addSubview(fontSizeTitleLabel)
        
        // A- 胶囊按钮
        decreaseButton = craftFontSizeBtn(
            icon: ReaderEnvironment.images.fontSizeDecrease(),
            colors: themeColors
        )
        decreaseButton.addAction(UIAction { [weak self] _ in self?.handleDecreaseFont() }, for: .touchUpInside)
        fontSizeRowView.addSubview(decreaseButton)
        
        // 字体大小显示
        fontSizeLabel = UILabel()
        fontSizeLabel.text = "\(ReaderConfiguration.shared().fontSize)"
        fontSizeLabel.font = ReaderEnvironment.fonts.uiRegular(12)
        fontSizeLabel.textColor = themeColors.textT1
        fontSizeLabel.textAlignment = .center
        fontSizeRowView.addSubview(fontSizeLabel)
        
        // A+ 胶囊按钮
        increaseButton = craftFontSizeBtn(
            icon: ReaderEnvironment.images.fontSizeIncrease(),
            colors: themeColors
        )
        increaseButton.addAction(UIAction { [weak self] _ in self?.handleIncreaseFont() }, for: .touchUpInside)
        fontSizeRowView.addSubview(increaseButton)
    }
    
    /// 生成字号胶囊按钮（118×30，全圆角，底色取 fillControl）
    private func craftFontSizeBtn(icon: UIImage?, colors: ReaderThemeColors) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(icon, for: .normal)
        button.tintColor = colors.iconDefault
        button.backgroundColor = colors.fillControl
        button.layer.cornerRadius = kFontSizeButtonHeight / 2
        button.layer.masksToBounds = true
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }
    
    /// 搭建行高滑块（左右两侧图标可点，中间滑块可拖）
    private func setupLineHeightControls() {
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        // 行高减小图标（设计稿是纯图标，不带底色胶囊）
        lineHeightDecreaseButton = UIButton(type: .custom)
        lineHeightDecreaseButton.setImage(ReaderEnvironment.images.lineSpacingDecrease(), for: .normal)
        lineHeightDecreaseButton.tintColor = themeColors.iconDefault
        lineHeightDecreaseButton.imageView?.contentMode = .scaleAspectFit
        lineHeightDecreaseButton.addAction(UIAction { [weak self] _ in self?.handleDecreaseLineHeight() }, for: .touchUpInside)
        lineHeightRowView.addSubview(lineHeightDecreaseButton)
        
        // 行高滑块
        lineHeightSlider = ReaderLineHeightSlider()
        lineHeightSlider.minimumValue = kLineHeightPercentMin
        lineHeightSlider.maximumValue = kLineHeightPercentMax
        lineHeightSlider.setValue(ReaderConfiguration.shared().lineHeightPercent)
        lineHeightSlider.adoptThemeColors(themeColors)
        // 拖动过程中实时把行距应用到正文（节流重排，见 applyLineHeightLive）
        lineHeightSlider.onValueChanging = { [weak self] value in
            self?.applyLineHeightLive(value)
        }
        // 抬手时落库并补一次权威重排
        lineHeightSlider.onValueCommitted = { [weak self] value in
            self?.finalizeLineHeightDrag(value)
        }
        lineHeightRowView.addSubview(lineHeightSlider)
        
        // 行高增大图标
        lineHeightIncreaseButton = UIButton(type: .custom)
        lineHeightIncreaseButton.setImage(ReaderEnvironment.images.lineSpacingIncrease(), for: .normal)
        lineHeightIncreaseButton.tintColor = themeColors.iconDefault
        lineHeightIncreaseButton.imageView?.contentMode = .scaleAspectFit
        lineHeightIncreaseButton.addAction(UIAction { [weak self] _ in self?.handleIncreaseLineHeight() }, for: .touchUpInside)
        lineHeightRowView.addSubview(lineHeightIncreaseButton)
    }
    
    /// 搭建背景色选择按钮（设计稿 5 个色块，不含夜间：夜间由 tab 栏的日/夜间按钮切换）
    private func setupBgColorButtons() {
        
        for theme in ReaderThemeType.swatchOrder {
            let button = UIButton(type: .custom)
            button.layer.cornerRadius = kBgColorSwatchSize / 2
            button.layer.masksToBounds = true
            // 闭包直接捕获 theme。以前靠 `button.tag = theme.rawValue` 传值，
            // 那是 target-action 只能传 sender 时代的写法 —— tag 当数据用一向容易和
            // 别处的 tag 语义撞车（本类另外四个按钮就用 tag 存「能不能点」）。
            button.addAction(UIAction { [weak self] _ in self?.selectTheme(theme) }, for: .touchUpInside)
            bgColorRowView.addSubview(button)
            bgColorButtons.append(button)
        }
        
        reviseBgColorSelection()
    }
    
    /// 搭建阅读方向（上下滑动 / 左右翻页）按钮
    private func setupReadingModeButtons() {
        verticalModeButton = craftReadingVariantBtn(
            icon: ReaderEnvironment.images.readingModeVertical(),
            title: ReaderEnvironment.strings.readingModeShort
        )
        verticalModeButton.addAction(UIAction { [weak self] _ in self?.alterReadingVariant(to: .scroll) }, for: .touchUpInside)
        readingModeRowView.addSubview(verticalModeButton)
        
        horizontalModeButton = craftReadingVariantBtn(
            icon: ReaderEnvironment.images.readingModeHorizontal(),
            title: ReaderEnvironment.strings.readingModeLong
        )
        horizontalModeButton.addAction(UIAction { [weak self] _ in self?.alterReadingVariant(to: .translation) }, for: .touchUpInside)
        readingModeRowView.addSubview(horizontalModeButton)
        
        reviseReadingVariantSelection()
    }
    
    /// 生成阅读方向分段按钮（图标+文字，圆角胶囊形）
    private func craftReadingVariantBtn(icon: UIImage?, title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(icon, for: .normal)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = ReaderEnvironment.fonts.uiRegular(12)
        button.imageView?.contentMode = .scaleAspectFit
        button.layer.masksToBounds = true
        // 图标在左，文字在右，间距 4
        let spacing: CGFloat = 4
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -spacing / 2, bottom: 0, right: spacing / 2)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: spacing / 2, bottom: 0, right: -spacing / 2)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: spacing / 2, bottom: 0, right: spacing / 2)
        return button
    }
    
    /// 更新阅读方向按钮的选中态（设计稿：选中段填 accent，未选中段透明，两态文字都用 textT1）
    private func reviseReadingVariantSelection() {
        let isVertical = ReaderConfiguration.shared().effectType == .scroll
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        adoptReadingVariantStyle(verticalModeButton, isSelected: isVertical, colors: themeColors)
        adoptReadingVariantStyle(horizontalModeButton, isSelected: !isVertical, colors: themeColors)
    }
    
    /// 应用阅读方向按钮样式
    private func adoptReadingVariantStyle(_ button: UIButton, isSelected: Bool, colors: ReaderThemeColors) {
        button.backgroundColor = isSelected ? colors.accent : .clear
        button.tintColor = colors.iconDefault
        button.setTitleColor(colors.textT1, for: .normal)
    }
    
    /// 搭建底部按钮栏
    private func setupBottomTabBar() {
        bottomTabBar = ReaderMenuTabRail()
        bottomTabBar.delegate = self
        addSubview(bottomTabBar)
    }

    // MARK: - ReaderMenuTabRailDelegate
    
    open func bottomTabBarDidClickCatalogue(_ tabBar: ReaderMenuTabRail) {
        readMenu?.delegate?.readerMenuDidTapCatalogue(readMenu)
    }
    
    open func bottomTabBarDidClickNightMode(_ tabBar: ReaderMenuTabRail) {
        let config = ReaderConfiguration.shared()
        
        // 日/夜间切换：夜间 ↔ 浅色基准主题
        config.themeType = config.isNightMode ? .lightDefault : .night
        config.hasUserSelectedTheme = true
        config.save()
        
        // 更新背景色按钮选中状态
        reviseBgColorSelection()
        
        // 更新日/夜间按钮图标
        bottomTabBar.isNightMode = config.isNightMode
        
        // 通知阅读控制器刷新
        readMenu?.delegate?.readerMenuDidChangeTheme(readMenu)
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
    }
    
    open func bottomTabBarDidClickSetting(_ tabBar: ReaderMenuTabRail) {
        clickSetting()
    }
    
    // MARK: - 目录相关
    
    /// 关闭目录视图（供外部调用）
    open func closeCatalogView() {
        bottomTabBar.catalogueButton.isSelected = false
        
        guard let bottomView = superview as? ReaderMenuBottomBar else { return }
        bottomView.catalogView.isHidden = true
        readMenu?.presentCatalogBackdrop(isShow: false, animated: true)
        
        reviseBaseViewHeight(animated: true)
    }
    
    /// 处理目录章节选中（供 ReaderMenuBottomBar 调用）
    open func processCatalogChapterPicked(_ chapterModel: ReaderChapterListItemModel) {
        readMenu?.presentDropdown(isShow: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let reader = self?.readMenu?.vc {
                if reader.readModel.recordModel.chapterModel.id != chapterModel.id {
                    reader.goToChapter(chapterModel.id)
                }
            }
        }
    }
    
    /// 设置阅读模型
    open func setReadModel(_ readModel: ReaderBookModel) {
        guard let bottomView = superview as? ReaderMenuBottomBar else { return }
        
        if readModel.recordModel.chapterModel == nil { return }
        
        bottomView.catalogView.readModel = readModel
    }
    
    // MARK: - 按钮状态更新
    
    /// 根据当前字号和行高值更新按钮的视觉禁用状态（保持 isEnabled=true 防止点击穿透）
    ///
    /// 禁用只改 tintColor，不再换 `*_disable` 那套图：四个图标都是 `.alwaysTemplate` 渲染，
    /// 换图只换到了被 tint 覆盖掉的预置色，纯冗余；而两套图一旦留白不一致，禁用瞬间图标
    /// 还会跟着变形。
    private func reviseBtnStates() {
        let currentFontSize = ReaderConfiguration.shared().fontSize
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        
        let canDecrease = currentFontSize > READER_FONT_SIZE_MIN
        decreaseButton.tag = canDecrease ? 1 : 0
        decreaseButton.tintColor = canDecrease ? themeColors.iconDefault : themeColors.iconDisable
        
        let canIncrease = currentFontSize < READER_FONT_SIZE_MAX
        increaseButton.tag = canIncrease ? 1 : 0
        increaseButton.tintColor = canIncrease ? themeColors.iconDefault : themeColors.iconDisable
        
        // 行高的当前值以滑块为准：拖动过程中配置还没落库，只有抬手才写入
        let currentLineHeight = lineHeightSlider.value
        
        let canDecreaseLineHeight = currentLineHeight > kLineHeightPercentMin
        lineHeightDecreaseButton.tag = canDecreaseLineHeight ? 1 : 0
        lineHeightDecreaseButton.tintColor = canDecreaseLineHeight ? themeColors.iconDefault : themeColors.iconDisable
        
        let canIncreaseLineHeight = currentLineHeight < kLineHeightPercentMax
        lineHeightIncreaseButton.tag = canIncreaseLineHeight ? 1 : 0
        lineHeightIncreaseButton.tintColor = canIncreaseLineHeight ? themeColors.iconDefault : themeColors.iconDisable
    }
    
    // MARK: - 字号操作
    
    /// 减小字体
    private func handleDecreaseFont() {
        guard decreaseButton.tag == 1 else { return }
        let size = ReaderConfiguration.shared().fontSize - READER_FONT_SIZE_SPACE
        
        if !(size < READER_FONT_SIZE_MIN) {
            fontSizeLabel.text = "\(size)"
            ReaderConfiguration.shared().fontSize = size
            ReaderConfiguration.shared().save()
            readMenu?.delegate?.readerMenuDidChangeFontSize(readMenu)
            
            // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
        }
        reviseBtnStates()
    }
    
    /// 增大字体
    private func handleIncreaseFont() {
        guard increaseButton.tag == 1 else { return }
        let size = ReaderConfiguration.shared().fontSize + READER_FONT_SIZE_SPACE
        
        if !(size > READER_FONT_SIZE_MAX) {
            fontSizeLabel.text = "\(size)"
            ReaderConfiguration.shared().fontSize = size
            ReaderConfiguration.shared().save()
            readMenu?.delegate?.readerMenuDidChangeFontSize(readMenu)
            
            // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
        }
        reviseBtnStates()
    }
    
    // MARK: - 行间距操作
    
    /// 减小行高（吸附到 10 的整数档，避免滑块停在非整档时 -10 得到零头值）
    private func handleDecreaseLineHeight() {
        guard lineHeightDecreaseButton.tag == 1 else { return }
        let newValue = steppedLineHeight(from: lineHeightSlider.value, increasing: false)
        
        commitLineHeight(newValue)
    }
    
    /// 增大行高（吸附到 10 的整数档）
    private func handleIncreaseLineHeight() {
        guard lineHeightIncreaseButton.tag == 1 else { return }
        let newValue = steppedLineHeight(from: lineHeightSlider.value, increasing: true)
        
        commitLineHeight(newValue)
    }
    
    /// 以 10 为档、朝指定方向取下一档行高值
    /// 当前值若不在整档上（如滑块停在 137），increasing 走到上方最近整档、decreasing 走到下方最近整档
    private func steppedLineHeight(from current: Int, increasing: Bool) -> Int {
        let step = kLineHeightPercentStep
        if increasing {
            let next = (current / step) * step + step
            return min(kLineHeightPercentMax, next)
        } else {
            let prev = (current % step == 0) ? current - step : (current / step) * step
            return max(kLineHeightPercentMin, prev)
        }
    }
    
    /// 上一次拖动实时重排的时间戳，用于节流
    private var lastLiveLineHeightRelayout: CFTimeInterval = 0
    
    /// 拖动过程中实时应用行高
    ///
    /// 只改内存中的配置值（不落库）并节流触发重排，让正文行距跟着滑块一起变。
    /// 重排（重新分页/重排版）是重活，节流到最多每 0.1s 一次，避免每帧都跑导致掉帧；
    /// 抬手时 finalizeLineHeightDrag 会再补一次权威重排，补上被节流丢掉的最后一帧。
    private func applyLineHeightLive(_ value: Int) {
        let config = ReaderConfiguration.shared()
        guard config.lineHeightPercent != value else { return }
        config.lineHeightPercent = value
        reviseBtnStates()
        
        let now = CACurrentMediaTime()
        guard now - lastLiveLineHeightRelayout >= 0.1 else { return }
        lastLiveLineHeightRelayout = now
        readMenu?.delegate?.readerMenuDidChangeLineHeight(readMenu)
    }
    
    /// 抬手/轻点提交行高：落库 + 权威重排 + 埋点
    private func finalizeLineHeightDrag(_ value: Int) {
        let config = ReaderConfiguration.shared()
        config.lineHeightPercent = value
        config.save()
        lineHeightSlider.setValue(value)
        reviseBtnStates()
        // 抬手必做一次重排：拖动节流可能把最后一帧丢了，这里保证正文停在最终行距上
        readMenu?.delegate?.readerMenuDidChangeLineHeight(readMenu)
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
    }
    
    /// 提交行高改动：落库 + 触发重排版 + 埋点（供两侧 +/- 图标调用）
    private func commitLineHeight(_ newValue: Int) {
        let config = ReaderConfiguration.shared()
        let current = config.lineHeightPercent
        
        lineHeightSlider.setValue(newValue)
        reviseBtnStates()
        
        guard newValue != current else { return }
        
        config.lineHeightPercent = newValue
        config.save()
        readMenu?.delegate?.readerMenuDidChangeLineHeight(readMenu)
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
    }
    
    // MARK: - 阅读模式操作
    
    /// 切换阅读模式
    private func alterReadingVariant(to mode: ReaderEffectType) {
        let config = ReaderConfiguration.shared()
        guard config.effectType != mode else { return }
        
        config.effectType = mode
        config.hasUserSelectedEffect = true
        config.save()
        
        reviseReadingVariantSelection()
        
        readMenu?.delegate?.readerMenuDidChangeReadingMode(readMenu)
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
    }
    
    // MARK: - 背景色操作
    
    /// 选中某个背景色块
    private func selectTheme(_ theme: ReaderThemeType) {
        let config = ReaderConfiguration.shared()
        guard theme != config.themeType else { return }
        
        config.themeType = theme
        config.hasUserSelectedTheme = true
        config.save()
        
        // 更新所有按钮的选中状态
        reviseBgColorSelection()
        
        readMenu?.delegate?.readerMenuDidChangeTheme(readMenu)
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
    }
    
    /// 更新色块的填充与选中描边
    ///
    /// 设计稿分两套：浅色主题下色块用自己的浅色填充 + 浅色描边；夜间主题下换成更饱和的
    /// 一套填充且不描边。两种情况下「当前选中」都用当前主题的 textT1 描 1pt。
    private func reviseBgColorSelection() {
        let config = ReaderConfiguration.shared()
        let currentTheme = config.themeType
        let themeProvider = ReaderPalette.shared
        let isNight = config.isNightMode
        let selectedBorderColor = config.currentThemeColors.textT1
        
        for (index, button) in bgColorButtons.enumerated() {
            guard index < ReaderThemeType.swatchOrder.count else { continue }
            let theme = ReaderThemeType.swatchOrder[index]
            let style = themeProvider.swatchStyle(for: theme)
            
            button.backgroundColor = isNight ? style.nightFill : style.lightFill
            
            if theme == currentTheme {
                button.layer.borderWidth = 1
                button.layer.borderColor = selectedBorderColor.cgColor
            } else if isNight {
                button.layer.borderWidth = 0
                button.layer.borderColor = UIColor.clear.cgColor
            } else {
                button.layer.borderWidth = 1
                button.layer.borderColor = style.lightBorder.cgColor
            }
        }
    }

    // MARK: - 设置按钮状态管理
    
    /// 点击设置
    open func clickSetting() {
        
        // 已展开则再次点击收起。判断依据统一用 isSettingPanelExpanded，
        // 不要再看 settingButton.isSelected —— 那是另一份状态，两边容易发散
        if isSettingPanelExpanded {
            restoreBtnStates()
            reviseBaseViewHeight(animated: true)
            return
        }
        
        // [埋点下线] 原此处经 readMenu.vc 回引阅读器上报菜单埋点，埋点已下线，连带移除对具体控制器类型的反向依赖
        
        bottomTabBar.catalogueButton.isSelected = false
        bottomTabBar.settingButton.isSelected = true
        settingPanelView.isHidden = false
        isSettingPanelExpanded = true
        
        // 刷新显示数据
        fontSizeLabel.text = "\(ReaderConfiguration.shared().fontSize)"
        lineHeightSlider.setValue(ReaderConfiguration.shared().lineHeightPercent)
        reviseBgColorSelection()
        reviseReadingVariantSelection()
        reviseBtnStates()
        
        // 隐藏目录和背景遮罩
        guard let bottomView = superview as? ReaderMenuBottomBar else { return }
        bottomView.catalogView.isHidden = true
        bottomView.catalogView.alpha = 0
        readMenu?.presentCatalogBackdrop(isShow: false, animated: true)
        
        reviseBaseViewHeight(animated: true)
    }
    
    /// 重置按钮状态为 normal
    ///
    /// 只标状态、不动 isHidden：收起动画期间面板要靠 bottomView 裁剪慢慢遮住，
    /// 立刻 isHidden 会让面板瞬间消失。真正的隐藏放在 reviseBaseViewHeight 的动画回调里。
    open func restoreBtnStates() {
        bottomTabBar.catalogueButton.isSelected = false
        bottomTabBar.settingButton.isSelected = false
        isSettingPanelExpanded = false
        
        guard let bottomView = superview as? ReaderMenuBottomBar else { return }
        bottomView.catalogView.isHidden = true
        readMenu?.presentCatalogBackdrop(isShow: false, animated: false)
    }
    
    /// 检查设置面板是否处于展开态
    open func isOptionPanelShown() -> Bool {
        return isSettingPanelExpanded
    }
    
    /// 菜单整体隐藏完成后的复位
    ///
    /// 菜单是带着展开的面板一起滑出屏幕的（这样收起过程看起来是整体下移，而不是面板先塌陷），
    /// 所以真正把面板藏起来要等滑出动画结束，也就是这里。
    open func restoreForMenuDismissed() {
        restoreBtnStates()
        settingPanelView.isHidden = true
    }
    
    // MARK: - 高度更新
    
    /// 更新 bottomView 高度
    ///
    /// funcView 的绝对位置在展开/收起两种状态下完全一致（见 ReaderMenuBottomBar.layoutSubviews），
    /// 所以这里只需要动 bottomView 的 frame，面板就是被容器顶边「拉开幕帘」露出来的，
    /// 不会出现面板横穿 tab 栏的观感。
    private func reviseBaseViewHeight(animated: Bool = false) {
        guard let bottomView = superview as? ReaderMenuBottomBar else { return }
        
        let newHeight = bottomView.getCurrentHeight()
        let newY = READER_CONTENT_VIEW_HEIGHT - newHeight
        let expanded = isSettingPanelExpanded
        
        // 面板展开时朗读 dock 让位（设计稿：展示更多设置内容时隐藏），收起时回来。
        //
        // 这是面板高度变化的唯一出口，挂在这里就覆盖了「点 Setting 展开 / 再点收起 /
        // 关目录」全部路径。dock 的锚点按收起态算死，所以不是「跟着面板上移」而是直接隐藏，
        // 省掉一条需要跟踪动画中间值的链路。
        readMenu?.vc?.presentSpeechDock(isShow: !expanded, animated: animated)
        
        if animated {
            UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: {
                bottomView.frame = CGRect(x: 0, y: newY, width: READER_CONTENT_VIEW_WIDTH, height: newHeight)
                bottomView.layoutIfNeeded()
            }) { [weak self] _ in
                // 收起动画结束后再真正隐藏，避免面板在动画首帧就消失
                if !expanded { self?.settingPanelView.isHidden = true }
            }
        } else {
            bottomView.frame = CGRect(x: 0, y: newY, width: READER_CONTENT_VIEW_WIDTH, height: newHeight)
            bottomView.layoutIfNeeded()
            if !expanded { settingPanelView.isHidden = true }
        }
    }
    
    // MARK: - Layout
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        // funcView 的高度恒为「面板 + tab 栏 + 安全区」，与展开状态无关（由 bottomView 裁剪
        // 决定露出多少），所以这里的内部布局是不变量，展开/收起过程中不会重排。
        let w = frame.size.width
        let contentWidth = w - kPanelMargin * 2
        
        settingPanelView.frame = CGRect(x: 0, y: 0, width: w, height: READER_MENU_SETTING_PANEL_HEIGHT)
        
        // MARK: 第一行：行高滑块（图标 24 + 12 + 滑块 + 12 + 图标 24）
        //
        // 视觉上这一行只有 24 高，但两侧图标按 24×24 算热区太小（低于 44 的可点尺寸下限），
        // 所以容器向上下各借 10pt（借的是面板顶部留白与行间距，不会压到别的控件），
        // 子视图仍摆在原来的视觉位置上。
        let lineHeightRowY = kPanelTopPadding
        let lineHeightRowInset: CGFloat = 10
        lineHeightRowView.frame = CGRect(x: kPanelMargin,
                                         y: lineHeightRowY - lineHeightRowInset,
                                         width: contentWidth,
                                         height: kLineHeightRowHeight + lineHeightRowInset * 2)
        
        let sliderWidth = contentWidth - (kLineHeightIconSize + kLineHeightIconGap) * 2
        lineHeightDecreaseButton.frame = CGRect(x: 0, y: lineHeightRowInset, width: kLineHeightIconSize, height: kLineHeightRowHeight)
        lineHeightSlider.frame = CGRect(x: kLineHeightIconSize + kLineHeightIconGap, y: lineHeightRowInset, width: max(0, sliderWidth), height: kLineHeightRowHeight)
        lineHeightIncreaseButton.frame = CGRect(x: contentWidth - kLineHeightIconSize, y: lineHeightRowInset, width: kLineHeightIconSize, height: kLineHeightRowHeight)
        
        // MARK: 第二行：字号（Size 24 + 20 + 胶囊 118 + 20 + 数值 15 + 20 + 胶囊 118）
        let fontSizeRowY = lineHeightRowY + kLineHeightRowHeight + kPanelRowGap
        fontSizeRowView.frame = CGRect(x: kPanelMargin, y: fontSizeRowY, width: contentWidth, height: kFontSizeRowHeight)
        
        let fontSizeButtonY = (kFontSizeRowHeight - kFontSizeButtonHeight) / 2
        // 胶囊宽度由剩余空间均分，375 宽下正好是设计稿的 118，更宽的屏幕上跟着拉伸
        let fontSizeButtonWidth = max(0, (contentWidth - kFontSizeTitleWidth - kFontSizeValueWidth - kFontSizeRowGap * 3) / 2)
        fontSizeTitleLabel.frame = CGRect(x: 0, y: 0, width: kFontSizeTitleWidth, height: kFontSizeRowHeight)
        
        var cursorX = kFontSizeTitleWidth + kFontSizeRowGap
        decreaseButton.frame = CGRect(x: cursorX, y: fontSizeButtonY, width: fontSizeButtonWidth, height: kFontSizeButtonHeight)
        cursorX += fontSizeButtonWidth + kFontSizeRowGap
        fontSizeLabel.frame = CGRect(x: cursorX, y: 0, width: kFontSizeValueWidth, height: kFontSizeRowHeight)
        cursorX += kFontSizeValueWidth + kFontSizeRowGap
        increaseButton.frame = CGRect(x: cursorX, y: fontSizeButtonY, width: fontSizeButtonWidth, height: kFontSizeButtonHeight)
        
        // MARK: 第三行：主题色块（5 个 36 圆，两端对齐后均分间隙）
        let bgColorRowY = fontSizeRowY + kFontSizeRowHeight + kPanelRowGap
        bgColorRowView.frame = CGRect(x: kPanelMargin, y: bgColorRowY, width: contentWidth, height: kBgColorRowHeight)
        
        let swatchCount = bgColorButtons.count
        if swatchCount > 0 {
            let swatchY = (kBgColorRowHeight - kBgColorSwatchSize) / 2
            let swatchGap = swatchCount > 1
                ? (contentWidth - kBgColorSwatchSize * CGFloat(swatchCount)) / CGFloat(swatchCount - 1)
                : 0
            for (index, button) in bgColorButtons.enumerated() {
                let x = CGFloat(index) * (kBgColorSwatchSize + swatchGap)
                button.frame = CGRect(x: x, y: swatchY, width: kBgColorSwatchSize, height: kBgColorSwatchSize)
            }
        }
        
        // MARK: 第四行：阅读方向分段控件（外框 335×40 圆角 20，内部两段 32 高圆角 16）
        let readingModeRowY = bgColorRowY + kBgColorRowHeight + kPanelRowGap
        readingModeRowView.frame = CGRect(x: kPanelMargin, y: readingModeRowY, width: contentWidth, height: kReadingModeRowHeight)
        readingModeRowView.layer.cornerRadius = kReadingModeRowHeight / 2
        
        let segmentHeight = kReadingModeRowHeight - kReadingModeInset * 2
        let segmentWidth = (contentWidth - kReadingModeInset * 2 - kReadingModeSegmentGap) / 2
        verticalModeButton.frame = CGRect(x: kReadingModeInset, y: kReadingModeInset, width: segmentWidth, height: segmentHeight)
        verticalModeButton.layer.cornerRadius = segmentHeight / 2
        horizontalModeButton.frame = CGRect(x: kReadingModeInset + segmentWidth + kReadingModeSegmentGap, y: kReadingModeInset, width: segmentWidth, height: segmentHeight)
        horizontalModeButton.layer.cornerRadius = segmentHeight / 2
        
        // MARK: 底部 tab 栏：恒定紧贴面板下方，绝对位置与展开状态无关
        bottomTabBar.frame = CGRect(x: 0, y: READER_MENU_SETTING_PANEL_HEIGHT, width: w, height: READER_MENU_BOTTOM_TAB_BAR_HEIGHT)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 主题换肤
    
    /// 应用主题颜色到 FuncView 及其子视图
    open func adoptThemeColors(_ colors: ReaderThemeColors) {
        backgroundColor = colors.fillPopup
        
        // 字号行：胶囊底色取 fillControl，文字取 textT1
        decreaseButton.backgroundColor = colors.fillControl
        increaseButton.backgroundColor = colors.fillControl
        fontSizeTitleLabel.textColor = colors.textT1
        fontSizeLabel.textColor = colors.textT1
        
        // 行高滑块
        lineHeightSlider.adoptThemeColors(colors)
        
        // 阅读方向分段控件外框
        readingModeRowView.layer.borderColor = colors.dividerLine.cgColor
        
        // 根据当前状态设置正确的图标和 tintColor
        reviseBtnStates()
        
        // 色块填充与选中描边更新
        reviseBgColorSelection()
        
        // 阅读方向按钮样式更新
        reviseReadingVariantSelection()
        
        // 底部按钮栏
        bottomTabBar.adoptThemeColors(colors)
    }
}
