//
//  ReaderFonts.swift
//  Reader Engine — Contracts
//
//  阅读器引擎所需的字体。
//
//  设计取舍：与 ReaderStrings / ReaderImages 同为**配置结构体 + 内置默认值**。
//  库自带一套默认字型（Lexend Deca 作 UI 字体、Newsreader 作正文衬线字体），
//  保证不配置也能跑；接入方想用自己的设计字型时整体覆盖即可。
//
//  为什么可配置而非引擎写死：字体属各项目的设计体系，不同接入方字型不同。
//  这与屏幕度量（ReaderScreenMetrics，物理固定值）不同，后者才该由引擎写死。
//
//  字段是 `(CGFloat) -> UIFont` 闭包而非字体名字符串：接入方的字体可能需要
//  合成斜体、按字重映射、或走自己的字体加载缓存，给闭包比给名字灵活。
//
//  字体文件的注册责任在接入方：默认值用的 LexendDeca-* / Newsreader-* 需由
//  宿主 bundle 注册（Info.plist 的 UIAppFonts）。抽成 pod 后若希望库自带默认字体，
//  需把 ttf 打进 pod 的 resource bundle 并注册，否则默认值会降级到系统字体。
//

import UIKit

/// 阅读器引擎使用的字体表。
///
/// 所有字段都有默认值（库自带字型），宿主只需覆盖想要定制的项：
/// ```swift
/// var fonts = ReaderFonts()
/// fonts.bodyText = { UIFont.myBrandSerif($0) }
/// ReaderEnvironment.fonts = fonts
/// ```
public struct ReaderFonts {

    // MARK: - 正文（随字号设置变化）

    /// 正文字体。引擎按用户选择的字号调用。
    /// 默认用系统衬线字体（`.serif` design），阅读长文比无衬线更合适。
    public var bodyText: (CGFloat) -> UIFont = { ReaderFonts.systemSerif($0, weight: .regular) }

    /// 正文内的章节标题字体（字号已由引擎叠加标题增量）。
    public var bodyTitle: (CGFloat) -> UIFont = { ReaderFonts.systemSerif($0, weight: .semibold) }

    /// 顶部页眉的章节名字体。
    public var chapterHeader: (CGFloat) -> UIFont = { ReaderFonts.systemSerif($0, weight: .medium) }

    // MARK: - 界面文字

    /// 界面常规文字：页码、目录项、书签摘要、菜单标签等。
    public var uiRegular: (CGFloat) -> UIFont = { .systemFont(ofSize: $0, weight: .regular) }

    /// 界面强调文字：书名、分组标题、弹窗按钮等。
    public var uiMedium: (CGFloat) -> UIFont = { .systemFont(ofSize: $0, weight: .medium) }

    /// 界面弱化文字：作者名、底部标签栏、时间等。
    public var uiLight: (CGFloat) -> UIFont = { .systemFont(ofSize: $0, weight: .light) }

    public init() {}

    // MARK: - 系统字体

    /// 系统衬线字体。取不到衬线 design 时退回普通系统字体。
    ///
    /// 库不携带任何字体文件：字体文件有各自的授权条款，随库分发等于代为再分发；
    /// 且字体属接入方的设计体系。需要特定字型的接入方覆盖对应字段即可。
    public static func systemSerif(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
