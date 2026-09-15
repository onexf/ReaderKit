//
//  ReaderHostConfiguring.swift
//  Reader Engine — Contracts
//
//  宿主环境配置注入点：把引擎零散依赖的「宿主远程配置 / 平台能力」收口到一处，
//  避免为每个小配置各开一个协议。
//
//  目前收口两项：
//  1. 图片压缩 URL 处理（含 CDN 域名切换）——属接入方的 CDN 调度与远程开关
//  2. 书签数量上限——通常由接入方的远程配置下发
//
//  未注入时用库内默认实现（不改 URL、书签上限给一个合理默认值），保证引擎可独立运行。
//

import Foundation

/// 宿主环境配置。宿主实现并注入。
public protocol ReaderHostConfiguring: AnyObject {

    /// 书签数量上限。宿主一般从远程配置下发。
    var bookmarkMaxCount: Int { get }

    /// 处理封面等图片的压缩 URL。
    ///
    /// 宿主在此接入 CDN 域名切换与压缩参数拼接；引擎只提供原始 URL 与目标像素尺寸。
    /// - Parameters:
    ///   - url: 原始图片 URL
    ///   - width: 目标宽度（点）
    ///   - height: 目标高度（点）
    /// - Returns: 处理后的 URL；未接入时返回原串
    func compressedImageURL(_ url: String, width: Int, height: Int) -> String
}

/// 库内默认实现：不接 CDN、书签上限给保守默认值。宿主未注入时使用。
///
/// 声明 `public init()` 与 `ReaderDefaultThemeProvider` 保持一致：该类型出现在公开
/// API 里（`ReaderEnvironment.hostConfiguration` 的默认值），接入方需要能实例化它，
/// 例如只想覆盖其中一项、其余沿用默认时把它作为兜底委托。
final public class ReaderDefaultHostConfiguration: ReaderHostConfiguring {

    public init() {}

    public var bookmarkMaxCount: Int { 99 }

    public func compressedImageURL(_ url: String, width: Int, height: Int) -> String {
        url
    }
}
