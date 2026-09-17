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
    var textT0: UIColor { get }       // 强调色/品牌色
    var textT1: UIColor { get }       // 主文字
    var textT2: UIColor { get }       // 次要文字
    var textT3: UIColor { get }       // 辅助文字
    var textDisable: UIColor { get }  // 禁用文字
    
    // Reader Icon
    var iconDefault: UIColor { get }  // 默认图标
    var iconDisable: UIColor { get }  // 禁用图标
    
    // Reader Fill
    var fillPopup: UIColor { get }    // 弹窗背景
    var fill: UIColor { get }         // 填充色
    var fill2: UIColor { get }        // 强调填充
    var fill3: UIColor { get }        // 极端色（黑/白）
    var fillControl: UIColor { get }  // 控件填充（设置面板 A- / A+ 胶囊底色）
    
    // Reader Line
    var dividerLine: UIColor { get }  // 分割线
    var line: UIColor { get }         // 线条
    
    // Reader Accent
    var accent: UIColor { get }       // 强调色（行高滑块已填充轨道、阅读方向选中段底色）
    
    // Reader Speech
    var speechHighlightFill: UIColor { get }  // 朗读高亮填充（背景色块样式的底色、下划线样式的线色）
    var speechHighlightText: UIColor { get }  // 朗读高亮文字色（文字变色样式）
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
}

// MARK: - 主题颜色结构体

/// 16 个颜色全部独立存储，不做计算属性派生
public struct ReaderTintAssign: ReaderThemeColors {
    public let page: UIColor
    public let textT0: UIColor
    public let textT1: UIColor
    public let textT2: UIColor
    public let textT3: UIColor
    public let textDisable: UIColor
    public let iconDefault: UIColor
    public let iconDisable: UIColor
    public let fillPopup: UIColor
    public let fill: UIColor
    public let fill2: UIColor
    public let fill3: UIColor
    public let fillControl: UIColor
    public let dividerLine: UIColor
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
                textT0: UIColor,
                textT1: UIColor,
                textT2: UIColor,
                textT3: UIColor,
                textDisable: UIColor,
                iconDefault: UIColor,
                iconDisable: UIColor,
                fillPopup: UIColor,
                fill: UIColor,
                fill2: UIColor,
                fill3: UIColor,
                fillControl: UIColor,
                dividerLine: UIColor,
                line: UIColor,
                accent: UIColor,
                speechHighlightFill: UIColor? = nil,
                speechHighlightText: UIColor? = nil) {
        self.page = page
        self.textT0 = textT0
        self.textT1 = textT1
        self.textT2 = textT2
        self.textT3 = textT3
        self.textDisable = textDisable
        self.iconDefault = iconDefault
        self.iconDisable = iconDisable
        self.fillPopup = fillPopup
        self.fill = fill
        self.fill2 = fill2
        self.fill3 = fill3
        self.fillControl = fillControl
        self.dividerLine = dividerLine
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
    /// 浅色主题下未选中时的描边色（选中时改用当前主题的 textT1）
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
