//
//  ReaderConfiguration.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/28.
//

import UIKit


/// 主题颜色
public var READER_COLOR_MAIN: UIColor = READER_COLOR_253_85_103

/// 菜单默认颜色
public var READER_COLOR_MENU_COLOR: UIColor = READER_COLOR_230_230_230

/// 阅读背景颜色列表
public let READER_BG_COLORS: [UIColor] = [readerColor(246, 246, 246), READER_COLOR_238_224_202, READER_COLOR_205_239_205, READER_COLOR_206_233_241, READER_COLOR_58_52_54]

/// 阅读最小阅读字体大小
public let READER_FONT_SIZE_MIN: NSInteger = 12

/// 阅读最大阅读字体大小
public let READER_FONT_SIZE_MAX: NSInteger = 26

/// 阅读默认字体大小
public let READER_FONT_SIZE_DEFAULT: NSInteger = 20

/// 正文首行缩进（pt）
public let READER_FIRST_LINE_HEAD_INDENT: CGFloat = 26

/// 阅读字体大小叠加指数
public let READER_FONT_SIZE_SPACE: NSInteger = 1

/// 章节标题 - 在当前字体大小上叠加指数（设计稿：正文 20 / 标题 22）
public let READER_FONT_SIZE_SPACE_TITLE: NSInteger = 2

/// 章节标题固定行高倍数（设计稿 Reader/Chapter Title：1.6em，不跟随用户行高设置）
public let READER_TITLE_LINE_HEIGHT_MULTIPLE: CGFloat = 1.6

/// 正文段间距（设计稿「展示说明」第 4 条：段间距固定 10）
public let READER_PARAGRAPH_SPACING: CGFloat = 10

/// 章节标题与正文之间的间距（设计稿 2215:20664 标注 32）
///
/// 口径是「标题行框底 → 正文首行行框顶」，也就是 CoreText 里标题段落的 `paragraphSpacing`。
/// 标题与正文是同一段富文本（见 `ReaderChapterModel.entireContentAttrString()`），
/// 这里不是视图间距，改它会改变 CoreText 分页结果，所以必须同时进 `activePagingSignature()`，
/// 否则已归档的章节不会重排，改了看不到效果。
public let READER_TITLE_BOTTOM_SPACING: CGFloat = 32

/// 当前主题方案版本
/// 1 = 旧的 5 套主题（白 / 护眼黄 / 护眼绿 / 护眼蓝 / 夜间）
/// 2 = 新的 6 套主题（暖白 / 羊皮纸 / 护眼绿 / 灰色 / 基础白 / 夜间）
public let READER_THEME_SCHEMA_VERSION: NSInteger = 2

/// 旧方案索引 → 新方案索引的映射，下标为旧 bgColorIndex
/// 白 → 基础白、护眼黄 → 羊皮纸、护眼绿 → 护眼绿、护眼蓝 → 灰色（新方案已无蓝色）、夜间 → 夜间
public let READER_THEME_LEGACY_INDEX_MAP: [Int] = [
    ReaderThemeType.basicWhite.rawValue,
    ReaderThemeType.parchment.rawValue,
    ReaderThemeType.eyeGreen.rawValue,
    ReaderThemeType.gray.rawValue,
    ReaderThemeType.night.rawValue
]

/// 单利对象
private var configure: ReaderConfiguration?

open class ReaderConfiguration: NSObject {
    
    // MARK: 阅读页面配置
    
    /// 开启长按菜单功能 (滚动模式是不支持长按功能的)
    open var openLongPress: Bool = true
    
    
    // MARK: 阅读内容配置
    
    /// 背景颜色索引
    @objc open var bgColorIndex: NSNumber!
    
    /// 字体类型索引
    @objc open var fontIndex: NSNumber!
    
    /// 翻页类型索引
    @objc open var effectIndex: NSNumber!
    
    /// 间距类型索引
    @objc open var spacingIndex: NSNumber!
    
    /// 进度显示索引
    @objc open var progressIndex: NSNumber!
    
    /// 字体大小
    @objc open var fontSize: NSNumber!
    
    /// 行高倍数（如 1.0, 1.2, 1.6, 2.0），存储为整数百分比（120, 160, 200）
    @objc open var lineHeightMultipleValue: NSNumber!
    
    /// 用户是否手动选择过阅读主题（选择过则不再跟随系统深色模式）
    @objc open var hasUserSelectedTheme: NSNumber!
    
    /// 阅读模式是否已确定（首次由第一本小说的 novelLengthType 决定，或用户手动切换后标记为 true）
    @objc open var hasUserSelectedEffect: NSNumber!
    
    /// 主题方案版本号，用于 bgColorIndex 的历史索引迁移，见 READER_THEME_SCHEMA_VERSION
    @objc open var themeSchemaVersion: NSNumber!
    
    
    // MARK: 快捷获取
    
    /// 使用分页进度 || 总文章进度(网络文章也可以使用)
    /// 总文章进度注意: 总文章进度需要有整本书的章节总数,以及当前章节带有从0开始排序的索引。
    /// 如果还需要在拖拽底部功能条上进度条过程中展示章节名,则需要带上章节列表数据,并去 ReaderMenuProgressPanel 文件中找到 ASValueTrackingSliderDataSource 修改返回数据源为章节名。
    open var progressType: ReaderProgressType! { return ReaderProgressType(rawValue: progressIndex.intValue) }
    
    /// 翻页类型
    open var effectType: ReaderEffectType! { return ReaderEffectType(rawValue: effectIndex.intValue) }
    
    /// 字体类型
    open var fontType: ReaderFontType! { return ReaderFontType(rawValue: fontIndex.intValue) }
    
    /// 间距类型
    open var spacingType: ReaderSpacingType! { return ReaderSpacingType(rawValue: spacingIndex.intValue) }
    
    /// 当前主题颜色集（根据 bgColorIndex 从 ReaderPalette 获取）
    open var currentThemeColors: ReaderThemeColors {
        return ReaderPalette.shared.activeColors()
    }
    
    /// 背景颜色 - 根据当前主题获取
    open var bgColor: UIColor! {
        return currentThemeColors.page
    }
    
    /// 字体颜色 - 根据当前主题获取
    open var textColor: UIColor! {
        return currentThemeColors.textT1
    }
    
    /// 状态栏字体颜色 - 根据当前主题获取
    open var statusTextColor: UIColor! {
        return currentThemeColors.textT3
    }
    
    /// 是否为夜间模式
    open var isNightMode: Bool {
        return bgColorIndex.intValue == ReaderThemeType.night.rawValue
    }
    
    /// 如果用户未手动选择过主题，根据系统深色模式同步阅读器主题
    /// 返回 true 表示主题发生了变化，调用方需要刷新 UI
    ///
    /// 检测方式见 `detectSystemDarkVariant()`：读 scene 级 traitCollection。
    /// 不接收调用方的 traitCollection —— VC 的 trait 继承自 window，而 window 被
    /// 接入方的 AppDelegate 可能强制为 .light，传进来的值同样无法反映系统设置。
    @discardableResult
    open func syncWithSystemDarkVariantIfRequired() -> Bool {
        guard !hasUserSelectedTheme.boolValue else { return false }
        
        let isDark = Self.detectSystemDarkVariant()
        let targetIndex = isDark ? ReaderThemeType.night.rawValue : ReaderThemeType.lightDefault.rawValue
        if bgColorIndex.intValue != targetIndex {
            bgColorIndex = NSNumber(value: targetIndex)
            save()
            return true
        }
        return false
    }
    
    /// 检测系统真实的深色模式设置
    ///
    /// 必须读 **scene** 级 traitCollection，不能读 window 或任何 view/VC：
    /// 接入方可能在 `application(_:didFinishLaunchingWithOptions:)` 末尾执行
    /// `window?.overrideUserInterfaceStyle = .light`（App 整体强制浅色），
    /// 该 window 及其全部子视图的 userInterfaceStyle 从此恒为 .light，与系统设置脱钩。
    /// window 的 override 不会向上影响所属 scene，所以 scene 的 trait 仍是系统真值 ——
    /// 这也是那行 override 刻意用代码而非 Info.plist 实现的原因。
    ///
    /// 另需确保 base.plist 中没有 INFOPLIST_KEY_UIUserInterfaceStyle=Light，
    /// 否则连 scene 的 traitCollection 也会被锁成 .light（当前工程未设置该键）。
    public static func detectSystemDarkVariant() -> Bool {
        let sceneStyle = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .traitCollection
            .userInterfaceStyle
        if let sceneStyle, sceneStyle != .unspecified {
            return sceneStyle == .dark
        }
        return false
    }
    
    /// 行间距(请设置整数,因为需要比较是否需要重新分页,小数点没法判断相等)
    open var lineSpacing: CGFloat! {
    
        if spacingType == .big { // 大间距
            
            return READER_SPACE_10
            
        }else if spacingType == .middle { // 中间距
            
            return READER_SPACE_7
            
        }else{ // 小间距
            
            return READER_SPACE_5
        }
    }
    
    /// 段间距
    ///
    /// 设计稿「展示说明」第 4 条：段间距固定 10，不随字号、行高或间距档位变化。
    /// 原先按 spacingType 分 30/20/16 三档，但设置面板已经没有间距档位入口了。
    open var paragraphSpacing: CGFloat {
        
        return READER_PARAGRAPH_SPACING
    }
    
    /// 阅读字体
    open func font(isTitle: Bool = false) ->UIFont {
        
        let size = readerScaled(CGFloat(fontSize.intValue + (isTitle ? READER_FONT_SIZE_SPACE_TITLE : 0)))
        
        // 标题使用 Newsreader SemiBold，正文使用 Newsreader Medium（标题字号已在上方叠加 READER_FONT_SIZE_SPACE_TITLE）
        if isTitle {
            return ReaderEnvironment.fonts.bodyTitle(size)
        } else {
            return ReaderEnvironment.fonts.bodyText(size)
        }
        
        // 原来的字体类型选择逻辑（已注释）
//        let fontType = self.fontType
//        
//        if fontType == .one { // 黑体
//            
//            return UIFont(name: "EuphemiaUCAS-Italic", size: size)!
//            
//        }else if fontType == .two { // 楷体
//            
//            return UIFont(name: "AmericanTypewriter-Light", size: size)!
//            
//        }else if fontType == .three { // 宋体
//            
//            return UIFont(name: "Papyrus", size: size)!
//            
//        }else{ // 系统
//            
//            return UIFont.systemFont(ofSize: size)
//        }
    }
    
    /// 英文段间距（与中文一致，设计稿未区分）
    open var englishParagraphSpacing: CGFloat {
        
        return READER_PARAGRAPH_SPACING
    }
    
    /// 字体属性
    /// isPaging: 为YES的时候只需要返回跟分页相关的属性即可 (原因:包含UIColor,小数点相关的...不可返回,因为无法进行比较)
    /// isEnglish: 是否为英文
    open func attributes(isTitle: Bool, isPageing: Bool = false, isEnglish: Bool = false) ->[NSAttributedString.Key: Any] {
        
        // 段落配置
        let paragraphStyle = NSMutableParagraphStyle()
        
        // 行高 = 字体大小 × 行高百分比 / 100（160% = 1.6倍字体行高）
        let currentFont = font(isTitle: isTitle)
        let lineHeightMultiplier = CGFloat(lineHeightMultipleValue.intValue) / 100.0
        let targetLineHeight = currentFont.pointSize * lineHeightMultiplier
        
        if isTitle {
            
            // 标题不跟随用户的行高设置，固定按设计稿 1.6 倍字号
            let titleLineHeight = currentFont.pointSize * READER_TITLE_LINE_HEIGHT_MULTIPLE
            paragraphStyle.minimumLineHeight = titleLineHeight
            paragraphStyle.maximumLineHeight = titleLineHeight
            paragraphStyle.lineSpacing = 0
            paragraphStyle.paragraphSpacing = READER_TITLE_BOTTOM_SPACING
            paragraphStyle.alignment = .left
            
        }else{
            
            // 正文：通过 min/max lineHeight 精确控制行高
            paragraphStyle.minimumLineHeight = targetLineHeight
            paragraphStyle.maximumLineHeight = targetLineHeight
            // lineSpacing 置 0，行高完全由 min/maxLineHeight 控制
            paragraphStyle.lineSpacing = 0
            
            // 正文首行缩进 26pt（前缀全角空格已在内容拼装时统一去除）
            paragraphStyle.firstLineHeadIndent = READER_FIRST_LINE_HEAD_INDENT
            
            if isEnglish {
                paragraphStyle.lineBreakMode = .byWordWrapping
                paragraphStyle.paragraphSpacing = englishParagraphSpacing
            } else {
                paragraphStyle.lineBreakMode = .byCharWrapping
                paragraphStyle.paragraphSpacing = paragraphSpacing
            }
            
            paragraphStyle.alignment = .left
        }
        
        if isPageing {
            
            return [.font: font(isTitle: isTitle), .paragraphStyle: paragraphStyle]
            
        }else{
            
            return [.foregroundColor: textColor, .font: font(isTitle: isTitle), .paragraphStyle: paragraphStyle]
        }
    }
    
    
    // MARK: 辅助
    
    /// 保存(使用 ReaderDefaults 存储是方便配置修改)
    open func save() {
        
        let dict = ["fontIndex": fontIndex,
                    "effectIndex": effectIndex,
                    "spacingIndex": spacingIndex,
                    "progressIndex": progressIndex,
                    "fontSize": fontSize,
                    "lineHeightMultipleValue": lineHeightMultipleValue,
                    "bgColorIndex": bgColorIndex,
                    "hasUserSelectedTheme": hasUserSelectedTheme,
                    "hasUserSelectedEffect": hasUserSelectedEffect,
                    "themeSchemaVersion": themeSchemaVersion]
    
        ReaderDefaults.setObject(dict, READER_KEY_CONFIGURE)
    }
    
    
    // MARK: 构造
    
    /// 获取对象
    public class func shared() ->ReaderConfiguration {
        
        if configure == nil { configure = ReaderConfiguration(ReaderDefaults.object(READER_KEY_CONFIGURE)) }
        
        return configure!
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
  
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
        
        initData()
    }
    
    /// 初始化配置数据,以及处理初始化数据的增删
    private func initData() {
        
        /// 主题索引迁移后需要立即回写，避免每次启动都从旧值重算
        var needsPersist = false
        
        // 背景 - 用户未手动选择过主题时，跟随系统深色模式（在阅读控制器 viewWillAppear 中同步）
        if hasUserSelectedTheme == nil {
            hasUserSelectedTheme = NSNumber(value: false)
        }
        
        // 阅读模式是否已确定（首次打开小说后即标记为 true）
        if hasUserSelectedEffect == nil {
            hasUserSelectedEffect = NSNumber(value: false)
        }
        
        if bgColorIndex == nil {
            // 全新安装：直接落在当前方案的浅色基准主题上
            bgColorIndex = NSNumber(value: ReaderThemeType.lightDefault.rawValue)
            themeSchemaVersion = NSNumber(value: READER_THEME_SCHEMA_VERSION)
        }
        
        // 主题方案升级：把旧 5 套主题的索引迁移到新 6 套主题的对应索引
        if themeSchemaVersion == nil || themeSchemaVersion.intValue < READER_THEME_SCHEMA_VERSION {
            let legacyIndex = bgColorIndex.intValue
            if legacyIndex >= 0 && legacyIndex < READER_THEME_LEGACY_INDEX_MAP.count {
                bgColorIndex = NSNumber(value: READER_THEME_LEGACY_INDEX_MAP[legacyIndex])
            } else {
                bgColorIndex = NSNumber(value: ReaderThemeType.lightDefault.rawValue)
            }
            themeSchemaVersion = NSNumber(value: READER_THEME_SCHEMA_VERSION)
            needsPersist = true
        }
        
        // 兜底：索引越界（例如后续主题数量收缩）时回落到浅色基准主题
        if ReaderThemeType(rawValue: bgColorIndex.intValue) == nil {
            bgColorIndex = NSNumber(value: ReaderThemeType.lightDefault.rawValue)
        }
        
        // 行高百分比 - 默认 160（即 160%）
        if lineHeightMultipleValue == nil {
            lineHeightMultipleValue = NSNumber(value: 160)
        }
        
        // 字体类型
        if (fontIndex == nil) || (ReaderFontType(rawValue: fontIndex.intValue) == nil) {
            
            fontIndex = NSNumber(value: ReaderFontType.system.rawValue)
        }
        
        // 间距类型
        if (spacingIndex == nil) || (ReaderSpacingType(rawValue: spacingIndex.intValue) == nil) {
            
            spacingIndex = NSNumber(value: ReaderSpacingType.small.rawValue)
        }
        
        // 翻页类型 - 仅支持滚动（Up&Down）与平移（Left&Right）两种
        // 老用户归档里可能存着已移除的仿真(0)/覆盖(1)/无效果(4)，这些 rawValue 现在解不出枚举，统一归一为滚动
        if (effectIndex == nil) || (ReaderEffectType(rawValue: effectIndex.intValue) == nil) {
            effectIndex = NSNumber(value: ReaderEffectType.scroll.rawValue)
        }
        
        // 字体大小
        if (fontSize == nil) || (fontSize.intValue > READER_FONT_SIZE_MAX || fontSize.intValue < READER_FONT_SIZE_MIN) {
            
            fontSize = NSNumber(value: READER_FONT_SIZE_DEFAULT)
        }
        
        // 显示进度类型
        if (progressIndex == nil) || (ReaderProgressType(rawValue: progressIndex.intValue) == nil) {
            
            progressIndex = NSNumber(value: ReaderProgressType.page.rawValue)
        }
        
        if needsPersist { save() }
    }
    
    public class func model(_ dict: Any?) ->ReaderConfiguration  { return ReaderConfiguration(dict) }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
