//
//  ReaderTheme.swift
//  ReaderKit
//
//  根据 Figma Design System Reader Variables 自动生成
//

import UIKit

// MARK: - 阅读器主题类型

/// 阅读器支持的 6 种主题，索引顺序与 bgColorIndex 保持一致（按 UI 稿的色块排列顺序）
public enum ReaderThemeType: Int, CaseIterable {
    case warmWhite  = 0  // 暖白
    case parchment  = 1  // 羊皮纸
    case eyeGreen   = 2  // 护眼绿
    case gray       = 3  // 灰色
    case basicWhite = 4  // 基础白
    case night      = 5  // 夜间
    
    /// 浅色基准主题：首次安装的默认值，也是日/夜间互切时的白天侧
    /// 设计稿「展示说明」第 5 条明确默认颜色为基础白
    public static let lightDefault: ReaderThemeType = .basicWhite
    
    /// 设置面板里色块的展示顺序（设计稿顺序，不含夜间：夜间由 tab 栏的日/夜间按钮切换）
    public static let swatchOrder: [ReaderThemeType] = [.basicWhite, .warmWhite, .parchment, .eyeGreen, .gray]
    
    /// 埋点用的主题标识，顺序与 rawValue 一致
    public var traceName: String {
        switch self {
        case .warmWhite:  return "warm_white"
        case .parchment:  return "parchment"
        case .eyeGreen:   return "green"
        case .gray:       return "gray"
        case .basicWhite: return "light"
        case .night:      return "night"
        }
    }
}

// MARK: - 阅读器主题颜色协议

/// 每个主题需要提供的 16 个语义颜色，全部独立存储
/// 即使当前值相同，也保持独立，方便 UI 后续单独调整
public protocol ReaderThemeColors {
    // Reader BG
    var page: UIColor { get }
    
    // Reader Text
    var textStrong: UIColor { get }       // 强调色/品牌色
    var textBody: UIColor { get }       // 主文字
    var textSubtle: UIColor { get }       // 次要文字
    var textFaint: UIColor { get }       // 辅助文字
    var textMuted: UIColor { get }  // 禁用文字
    
    // Reader Icon
    var iconStandard: UIColor { get }  // 默认图标
    var iconMuted: UIColor { get }  // 禁用图标
    
    // Reader Fill
    var fillSheet: UIColor { get }    // 弹窗背景
    var fill: UIColor { get }         // 填充色
    var fillAccent: UIColor { get }        // 强调填充
    var fillExtreme: UIColor { get }        // 极端色（黑/白）
    var fillControl: UIColor { get }  // 控件填充（设置面板 A- / A+ 胶囊底色）
    
    // Reader Line
    var separatorTint: UIColor { get }  // 分割线
    var line: UIColor { get }         // 线条
    
    // Reader Accent
    var accent: UIColor { get }       // 强调色（行高滑块已填充轨道、阅读方向选中段底色）
    
    // Reader Speech
    var speechHighlightFill: UIColor { get }  // 朗读高亮填充（背景色块样式的底色、下划线样式的线色）
    var speechHighlightText: UIColor { get }  // 朗读高亮文字色（文字变色样式）
    var speechCapsuleFill: UIColor { get }    // 朗读控制胶囊底色
    var speechCapsuleText: UIColor { get }    // 朗读控制胶囊的图标与文字色
    var speechCapsuleDivider: UIColor { get } // 朗读控制胶囊内的分隔线色
    var fillSpeechDock: UIColor { get }       // 呼出菜单上朗读 dock 的底色
    var textSpeechDock: UIColor { get }       // 朗读 dock 内的图标色
}

// MARK: - 朗读高亮色的默认实现

/// 朗读高亮的两个色槽给协议默认实现，由 `accent` 派生。
///
/// 为什么不做成必填：本协议是接入方要实现的契约，加必填属性会让**已有**的
/// conformer 直接编译不过（`ReaderTintAssign` 的成员初始化器是显式声明的，
/// 加字段等于改公开 API）。给默认实现则老接入方零改动即可拿到可用的高亮色，
/// 有设计稿的接入方再覆盖。
public extension ReaderThemeColors {

    /// 默认取强调色的低透明度版本。
    ///
    /// 透明度压到 0.22 是为了让正文文字仍然清晰可读 —— 高亮是辅助定位的，
    /// 不该盖过它标记的那句话。深色主题下 `accent` 本身较亮，同一透明度也够醒目。
    var speechHighlightFill: UIColor { accent.withAlphaComponent(0.22) }

    /// 默认直接取强调色。文字变色样式下高亮字本身就是前景，不能带透明度。
    var speechHighlightText: UIColor { accent }

    /// 朗读控制胶囊底色。
    ///
    /// 默认由主文字色降透明度得到，而不是写死一个灰值：这样六套主题自动各得一个
    /// 与自身正文色协调的胶囊底 —— 浅色主题下是半透明深灰（≈ 设计稿的 `#6C6C6C`），
    /// 夜间主题下自动变成半透明浅灰，不至于在深底上糊成一片。
    ///
    /// 设计稿目前只给了浅色态的 `#6C6C6C`；六套主题的值齐了之后由接入方覆盖。
    var speechCapsuleFill: UIColor { textBody.withAlphaComponent(0.62) }

    /// 胶囊内图标与文字色。
    ///
    /// 默认取页面背景色。这是个反色关系：浅色主题下页面是近白色（≈ 设计稿的 `#F8F8F8`），
    /// 落在深灰胶囊上正好；夜间主题下页面是深色，落在浅灰胶囊上同样成立。
    var speechCapsuleText: UIColor { page }

    /// 胶囊内分隔线色。默认在图文色基础上压透明度，弱于图文但仍可见。
    var speechCapsuleDivider: UIColor { speechCapsuleText.withAlphaComponent(0.5) }

    /// 呼出菜单上朗读 dock 的底色。
    ///
    /// 与页脚胶囊不同，dock 在设计稿里是**六套主题统一的深色块**（`#222222`）——
    /// 它浮在菜单遮罩之上，遮罩本身已经把正文压暗，dock 再跟着主题变浅反而会糊进遮罩里。
    /// 所以默认值不从主题色派生，而是固定深色；接入方要改再覆盖。
    var fillSpeechDock: UIColor { UIColor(white: 0.133, alpha: 1) }

    /// dock 内图标色。固定近白色，与固定深底配对。
    var textSpeechDock: UIColor { UIColor(white: 0.973, alpha: 1) }
}

// MARK: - 主题颜色结构体

/// 16 个颜色全部独立存储，不做计算属性派生
public struct ReaderTintAssign: ReaderThemeColors {
    public let page: UIColor
    public let textStrong: UIColor
    public let textBody: UIColor
    public let textSubtle: UIColor
    public let textFaint: UIColor
    public let textMuted: UIColor
    public let iconStandard: UIColor
    public let iconMuted: UIColor
    public let fillSheet: UIColor
    public let fill: UIColor
    public let fillAccent: UIColor
    public let fillExtreme: UIColor
    public let fillControl: UIColor
    public let separatorTint: UIColor
    public let line: UIColor
    public let accent: UIColor

    /// 朗读高亮填充色。为 nil 时走协议默认实现（由 `accent` 派生）。
    private let speechHighlightFillValue: UIColor?

    /// 朗读高亮文字色。为 nil 时走协议默认实现（取 `accent`）。
    private let speechHighlightTextValue: UIColor?

    public var speechHighlightFill: UIColor { speechHighlightFillValue ?? accent.withAlphaComponent(0.22) }

    public var speechHighlightText: UIColor { speechHighlightTextValue ?? accent }

    /// 供接入方在自己的 `ReaderThemeProviding` 实现里构造配色。
    /// Swift 不会把 struct 的隐式成员初始化器暴露到模块外，故显式声明。
    ///
    /// 末尾两个朗读高亮色带默认值 nil，所以既有调用处无需改动；
    /// 拿到设计稿后按主题传入即可覆盖派生兜底。
    public init(page: UIColor,
                textStrong: UIColor,
                textBody: UIColor,
                textSubtle: UIColor,
                textFaint: UIColor,
                textMuted: UIColor,
                iconStandard: UIColor,
                iconMuted: UIColor,
                fillSheet: UIColor,
                fill: UIColor,
                fillAccent: UIColor,
                fillExtreme: UIColor,
                fillControl: UIColor,
                separatorTint: UIColor,
                line: UIColor,
                accent: UIColor,
                speechHighlightFill: UIColor? = nil,
                speechHighlightText: UIColor? = nil) {
        self.page = page
        self.textStrong = textStrong
        self.textBody = textBody
        self.textSubtle = textSubtle
        self.textFaint = textFaint
        self.textMuted = textMuted
        self.iconStandard = iconStandard
        self.iconMuted = iconMuted
        self.fillSheet = fillSheet
        self.fill = fill
        self.fillAccent = fillAccent
        self.fillExtreme = fillExtreme
        self.fillControl = fillControl
        self.separatorTint = separatorTint
        self.line = line
        self.accent = accent
        self.speechHighlightFillValue = speechHighlightFill
        self.speechHighlightTextValue = speechHighlightText
    }
}

// MARK: - 主题色块展示样式

/// 设置面板里 5 个主题色块的展示样式
///
/// 设计稿在夜间主题下给色块换了一套更饱和的填充色、并且去掉了描边（深底上描边无意义），
/// 所以浅色态与夜间态分两套存，不能只用各主题自己的 page 色。
public struct ReaderSwatchStyle {
    /// 浅色主题下的填充色
    public let lightFill: UIColor
    /// 浅色主题下未选中时的描边色（选中时改用当前主题的 textBody）
    public let lightBorder: UIColor
    /// 夜间主题下的填充色（夜间未选中不描边）
    public let nightFill: UIColor

    /// 供接入方构造色块样式（同上，隐式成员初始化器不跨模块可见）。
    public init(lightFill: UIColor, lightBorder: UIColor, nightFill: UIColor) {
        self.lightFill = lightFill
        self.lightBorder = lightBorder
        self.nightFill = nightFill
    }
}
