//
//  ReaderPalette.swift
//  ReaderKit
//
//  阅读主题配色的读取入口。
//
//  本身不存配色：具体色值由接入方经 `ReaderEnvironment.themeProvider` 注入
//  （配色属设计资产，见 Contracts/ReaderThemeProviding.swift）。
//  保留这层 facade 是为了让引擎内部有统一、稳定的取色口径。
//

import UIKit

final public class ReaderPalette {

    public static let shared = ReaderPalette()

    private init() {}

    private var provider: ReaderThemeProviding { ReaderEnvironment.themeProvider }

    /// 根据主题类型获取颜色集
    public func colors(for theme: ReaderThemeType) -> ReaderThemeColors {
        return provider.colors(for: theme)
    }

    /// 根据索引获取颜色集（兼容持久化里的 bgColorIndex）
    public func colors(forIndex index: Int) -> ReaderThemeColors {
        let all = ReaderThemeType.allCases
        let safeIndex = max(0, min(index, all.count - 1))
        return provider.colors(for: all[safeIndex])
    }

    /// 获取当前阅读器配置对应的主题颜色
    public func activeColors() -> ReaderThemeColors {
        let index = ReaderConfiguration.shared().bgColorIndex.intValue
        return colors(forIndex: index)
    }

    /// 获取某个主题在设置面板色块里的展示样式
    public func swatchStyle(for theme: ReaderThemeType) -> ReaderSwatchStyle {
        return provider.swatchStyle(for: theme)
    }

    /// 所有主题的背景色列表
    public var allPageColors: [UIColor] {
        return ReaderThemeType.allCases.map { provider.colors(for: $0).page }
    }

    /// 主题数量
    public var themeCount: Int {
        return ReaderThemeType.allCases.count
    }
}
