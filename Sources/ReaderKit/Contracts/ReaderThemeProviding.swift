//
//  ReaderThemeProviding.swift
//  Reader Engine — Contracts
//
//  阅读主题配色注入点。
//
//  库定义「有哪些主题槽位」（`ReaderThemeType`，6 个，rawValue 参与持久化，
//  用户选过的主题按索引存在偏好里，故槽位数量与顺序属库的稳定契约），
//  但**每个槽位长什么样由接入方决定** —— 配色是设计资产，不该由库夹带。
//
//  库自带一套中性默认配色，保证不注入也能正常阅读。
//
//  本文件属 Engine/Contracts/，按约定不加前缀，见库根 README。
//

import UIKit

/// 阅读主题配色来源。
public protocol ReaderThemeProviding {

    /// 某个主题槽位的 16 个语义色。
    func colors(for theme: ReaderThemeType) -> ReaderThemeColors

    /// 某个主题在设置面板色块里的展示样式（填充、描边）。
    func swatchStyle(for theme: ReaderThemeType) -> ReaderSwatchStyle
}

/// 库内默认配色：一套中性的浅色到夜间过渡，不取自任何具体产品的设计稿。
///
/// 目的只是「不注入也能读」。接入方应实现 `ReaderThemeProviding` 提供自己的设计配色。
public struct ReaderDefaultThemeProvider: ReaderThemeProviding {

    public init() {}

    public func colors(for theme: ReaderThemeType) -> ReaderThemeColors {
        switch theme {
        case .basicWhite: return Self.make(page: .white, ink: .black)
        case .warmWhite:  return Self.make(page: UIColor(white: 0.98, alpha: 1), ink: UIColor(white: 0.15, alpha: 1))
        case .parchment:  return Self.make(page: UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1),
                                           ink: UIColor(red: 0.24, green: 0.20, blue: 0.15, alpha: 1))
        case .eyeGreen:   return Self.make(page: UIColor(red: 0.88, green: 0.93, blue: 0.87, alpha: 1),
                                           ink: UIColor(red: 0.16, green: 0.24, blue: 0.17, alpha: 1))
        case .gray:       return Self.make(page: UIColor(white: 0.90, alpha: 1), ink: UIColor(white: 0.18, alpha: 1))
        case .night:      return Self.make(page: UIColor(white: 0.11, alpha: 1), ink: UIColor(white: 0.78, alpha: 1))
        }
    }

    public func swatchStyle(for theme: ReaderThemeType) -> ReaderSwatchStyle {
        let page = colors(for: theme).page
        return ReaderSwatchStyle(lightFill: page,
                                 lightBorder: UIColor(white: 0.80, alpha: 1),
                                 nightFill: page)
    }

    /// 由「纸色 + 墨色」推导出 16 个语义色，避免默认实现里堆硬编码色值。
    private static func make(page: UIColor, ink: UIColor) -> ReaderTintAssign {
        ReaderTintAssign(
            page: page,
            textT0: ink,
            textT1: ink,
            textT2: ink.withAlphaComponent(0.75),
            textT3: ink.withAlphaComponent(0.55),
            textDisable: ink.withAlphaComponent(0.35),
            iconDefault: ink,
            iconDisable: ink.withAlphaComponent(0.35),
            fillPopup: page,
            fill: ink.withAlphaComponent(0.08),
            fill2: ink,
            fill3: ink,
            fillControl: ink.withAlphaComponent(0.12),
            dividerLine: ink.withAlphaComponent(0.15),
            line: ink,
            accent: ink.withAlphaComponent(0.60)
        )
    }
}
