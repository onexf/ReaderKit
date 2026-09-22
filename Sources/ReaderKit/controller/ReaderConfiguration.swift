//
//  ReaderConfiguration.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/28.
//

import UIKit


/// 主题颜色
nonisolated(unsafe) public var READER_COLOR_MAIN: UIColor = READER_COLOR_253_85_103

/// 菜单默认颜色
nonisolated(unsafe) public var READER_COLOR_MENU_COLOR: UIColor = READER_COLOR_230_230_230

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

//  阅读配置 —— 用户在设置面板里选的那些：主题、字号、行高、翻页方式。
//
//  ## 存储属性就是配置本身
//
//  这里**没有「索引」层**：主题就是 `ReaderThemeType`，翻页方式就是 `ReaderEffectType`。
//  1.24.0 之前是十个 `@objc open var xxxIndex: NSNumber!`，落盘走 `setValuesForKeys`
//  的 KVC 回路。那套有三个毛病，而且**都不报错**：
//
//  - `setValue(_:forUndefinedKey:)` 是空实现 —— 键名写错、类型不对都被吞掉，
//    表现是用户的阅读设置每次启动静默回到默认值。
//  - 十个 IUO。每个读取点都要 `.intValue` / `.boolValue`，每个写入点都要 `NSNumber(value:)`。
//  - `effectType` 这类访问器是 `ReaderEffectType!`（从 Int 反查枚举），
//    也就是把「这个 Int 是不是合法枚举值」推到了运行时。
//
//  现在每个键都在 `load(from:)` 里显式读一次，读不出来就保留属性声明处的默认值。
//  漏一个键是看得见的（那一行不存在），不再是静默回落。

open class ReaderConfiguration {
    
    // MARK: 阅读页面配置
    
    /// 开启长按菜单功能 (滚动模式是不支持长按功能的)
    open var openLongPress: Bool = true
    
    
    // MARK: 阅读内容配置
    
    /// 当前阅读主题。
    open var themeType: ReaderThemeType = .lightDefault
    
    /// 翻页方式。只有左右翻页与上下滚动两种。
    open var effectType: ReaderEffectType = .scroll
    
    /// 字体档位。设置面板目前没有入口，正文字体走 `ReaderEnvironment.fonts`。
    open var fontType: ReaderFontType = .system
    
    /// 行间距档位。设置面板目前没有入口。
    open var spacingType: ReaderSpacingType = .small
    
    /// 底部进度的显示方式：分页进度 or 全书进度。
    ///
    /// 全书进度需要整本书的章节总数、以及当前章节带有从 0 开始的排序索引。
    /// 想在拖动进度条时显示章节名，改 `ReaderMenuProgressPanel.bubbleText(for:)`。
    open var progressType: ReaderProgressType = .page
    
    /// 正文字号（pt）。范围 `READER_FONT_SIZE_MIN`…`READER_FONT_SIZE_MAX`。
    open var fontSize: Int = READER_FONT_SIZE_DEFAULT
    
    /// 行高百分比：`160` 表示 1.6 倍字号。
    ///
    /// 用整数百分比而不是 `CGFloat` 倍数：这个值要进分页签名做相等比较
    /// （见 `ReaderChapterModel.activePagingSignature()`），浮点数没法判相等。
    open var lineHeightPercent: Int = 160
    
    /// 用户是否手动选择过阅读主题。选过之后就不再跟随系统深色模式。
    open var themeChosenByUser = false
    
    /// 阅读方式是否已确定（首次由第一本小说的篇幅决定，或用户手动切过）。
    open var effectChosenByUser = false
    
    /// 磁盘上那份配置的主题方案版本号，只用于一次性索引迁移。对外没有意义。
    private var themeSchemaVersion = READER_THEME_SCHEMA_VERSION
    
    
    // MARK: 快捷获取
    
    /// 当前主题颜色集
    open var currentThemeColors: ReaderThemeColors {
        return ReaderPalette.shared.activeColors()
    }
    
    /// 背景颜色 - 根据当前主题获取
    open var bgColor: UIColor! {
        return currentThemeColors.page
    }
    
    /// 字体颜色 - 根据当前主题获取
    open var textColor: UIColor! {
        return currentThemeColors.textBody
    }
    
    /// 状态栏字体颜色 - 根据当前主题获取
    open var statusTextColor: UIColor! {
        return currentThemeColors.textFaint
    }
    
    /// 是否为夜间模式
    open var isDarkTheme: Bool {
        return themeType == .night
    }
    
    /// 用户没手动选过主题时，按系统深色开关同步阅读主题。
    ///
    /// - Returns: 主题是否变了。变了的话调用方要刷 UI。
    ///
    /// **调用点在 `ReaderViewController.initialize()` 与 `viewWillAppear`，由库自己管**
    /// —— 接入方不需要调。1.24.1 之前这个方法一个调用者都没有，于是「跟随系统深色」整个功能
    /// 是死的：全新安装 + 系统深色，第一次进阅读页是浅色。
    ///
    /// 检测方式见 `detectSystemDarkVariant()`：读 scene 级 traitCollection。
    /// 不接收调用方的 traitCollection —— VC 的 trait 继承自 window，而 window 被
    /// 接入方的 AppDelegate 可能强制为 .light，传进来的值同样无法反映系统设置。
    @discardableResult
    open func syncWithSystemDarkVariantIfRequired() -> Bool {
        guard !themeChosenByUser else { return false }
        
        let target: ReaderThemeType = Self.detectSystemDarkVariant() ? .night : .lightDefault
        guard themeType != target else { return false }
        
        themeType = target
        save()
        return true
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
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // 多 scene（iPad 分屏）时取前台那个，取错会读到后台 scene 的陈旧 trait。
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        
        if let style = scene?.traitCollection.userInterfaceStyle, style != .unspecified {
            return style == .dark
        }
        
        // scene 还没建起来（极早的启动时序）时退到屏幕的 trait。它同样不受 window
        // override 影响，只是不区分多 scene。
        let screenStyle = UIScreen.main.traitCollection.userInterfaceStyle
        return screenStyle == .dark
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
        
        let size = readerScaled(CGFloat(fontSize + (isTitle ? READER_FONT_SIZE_SPACE_TITLE : 0)))
        
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
        let lineHeightMultiplier = CGFloat(lineHeightPercent) / 100.0
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
    
    
    // MARK: - 持久化
    
    /// 磁盘上的键名。
    ///
    /// **和属性名刻意不一致**：属性名是现在的命名，这几个字符串是已经写进用户
    /// `UserDefaults` 的历史格式。一经发布就不要再改 —— 改了读不到旧键，用户的阅读设置
    /// 会静默回到默认值。
    private enum StoreKey {
        static let theme = "bgColorIndex"
        static let effect = "effectIndex"
        static let font = "fontIndex"
        static let spacing = "spacingIndex"
        static let progress = "progressIndex"
        static let fontSize = "fontSize"
        static let lineHeight = "lineHeightMultipleValue"
        static let userSelectedTheme = "hasUserSelectedTheme"
        static let userSelectedEffect = "hasUserSelectedEffect"
        static let schemaVersion = "themeSchemaVersion"
    }
    
    /// 写盘。整份配置存成 `UserDefaults` 里的一个字典。
    ///
    /// 布尔也存成 0/1：读回来时 plist 的布尔与整数都能用同一个 `as? NSNumber` 取，
    /// 少一条分支。
    open func save() {
        
        let dict: [String: Int] = [
            StoreKey.theme: themeType.rawValue,
            StoreKey.effect: effectType.rawValue,
            StoreKey.font: fontType.rawValue,
            StoreKey.spacing: spacingType.rawValue,
            StoreKey.progress: progressType.rawValue,
            StoreKey.fontSize: fontSize,
            StoreKey.lineHeight: lineHeightPercent,
            StoreKey.userSelectedTheme: themeChosenByUser ? 1 : 0,
            StoreKey.userSelectedEffect: effectChosenByUser ? 1 : 0,
            StoreKey.schemaVersion: themeSchemaVersion,
        ]
        
        ReaderDefaults.setObject(dict, READER_KEY_CONFIGURE)
    }
    
    /// 逐键读回。
    ///
    /// 每一项的语义都一样：**读不出来、或者不是合法值，就保留属性声明处的默认值。**
    /// 所以这里没有「补默认值」的代码 —— 默认值只写在属性声明上一处。
    ///
    /// - Returns: 是否需要立刻回写（只有主题方案迁移会要求）。
    private func load(from stored: [String: Any]?) -> Bool {
        
        guard let stored else { return false }
        
        if let raw = Self.storedInt(stored, StoreKey.effect),
           let value = ReaderEffectType(rawValue: raw) {
            // 解不出枚举就留默认（滚动）。历史配置里可能存着已经移除的
            // 仿真(0) / 覆盖(1) / 无效果(4)，它们现在没有对应的 case。
            effectType = value
        }
        if let raw = Self.storedInt(stored, StoreKey.font),
           let value = ReaderFontType(rawValue: raw) {
            fontType = value
        }
        if let raw = Self.storedInt(stored, StoreKey.spacing),
           let value = ReaderSpacingType(rawValue: raw) {
            spacingType = value
        }
        if let raw = Self.storedInt(stored, StoreKey.progress),
           let value = ReaderProgressType(rawValue: raw) {
            progressType = value
        }
        if let raw = Self.storedInt(stored, StoreKey.fontSize),
           raw >= READER_FONT_SIZE_MIN, raw <= READER_FONT_SIZE_MAX {
            fontSize = raw
        }
        if let raw = Self.storedInt(stored, StoreKey.lineHeight), raw > 0 {
            lineHeightPercent = raw
        }
        if let raw = Self.storedInt(stored, StoreKey.userSelectedTheme) {
            themeChosenByUser = raw != 0
        }
        if let raw = Self.storedInt(stored, StoreKey.userSelectedEffect) {
            effectChosenByUser = raw != 0
        }
        
        return loadTheme(from: stored)
    }
    
    /// 主题单独读：它有一次跨方案的索引迁移。
    ///
    /// - Returns: 是否发生了迁移（需要回写，否则每次启动都要从旧值重算一遍）。
    private func loadTheme(from stored: [String: Any]) -> Bool {
        
        guard let raw = Self.storedInt(stored, StoreKey.theme) else { return false }
        
        let storedVersion = Self.storedInt(stored, StoreKey.schemaVersion) ?? 0
        
        if storedVersion >= READER_THEME_SCHEMA_VERSION {
            // 越界（例如将来主题数量收缩）时回落浅色基准主题。
            themeType = ReaderThemeType(rawValue: raw) ?? .lightDefault
            themeSchemaVersion = storedVersion
            return false
        }
        
        // 旧方案 5 套主题 → 新方案 6 套的一次性索引迁移。
        if raw >= 0, raw < READER_THEME_LEGACY_INDEX_MAP.count {
            themeType = ReaderThemeType(rawValue: READER_THEME_LEGACY_INDEX_MAP[raw]) ?? .lightDefault
        } else {
            themeType = .lightDefault
        }
        themeSchemaVersion = READER_THEME_SCHEMA_VERSION
        return true
    }
    
    /// 从存下来的字典里取一个整数。
    ///
    /// 走 `NSNumber` 而不是 `as? Int`：plist 里的布尔读回来是 `__NSCFBoolean`，
    /// `as? Int` 会失败，而 `NSNumber` 能同时接住布尔与整数 —— 历史配置里
    /// `hasUserSelected*` 两个键存的就是布尔。
    private static func storedInt(_ stored: [String: Any], _ key: String) -> Int? {
        return (stored[key] as? NSNumber)?.intValue
    }
    
    
    // MARK: - 构造
    
    /// 获取对象
    public class func shared() ->ReaderConfiguration {
        
        if configure == nil { configure = ReaderConfiguration(ReaderDefaults.object(READER_KEY_CONFIGURE)) }
        
        return configure!
    }
    
    public init(_ stored: Any? = nil) {
        
        if load(from: stored as? [String: Any]) { save() }
    }
}
