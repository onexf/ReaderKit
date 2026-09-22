//
//  ReaderEnvironment.swift
//  Reader Engine — Contracts
//
//  引擎的进程级环境容器，存放「整个阅读器共享、且与具体某次阅读无关」的配置。
//
//  为什么需要它：文案被 12 个文件使用，其中多数是 UIView / UITableViewCell
//  （目录 cell、书签 cell、菜单面板等），它们拿不到控制器实例。若改成逐层
//  注入，要动大量构造函数与属性传递链，收益与风险不成比例。
//
//  使用约束：
//  - 只放**无状态配置**（文案、外观常量这类），不要放阅读会话数据
//    （当前书籍、章节、进度等），那些必须走 dataSource / 实例属性
//  - **在展示阅读器之前配置一次**，之后视为只读。库内不对这些属性做同步。
//
//  并发标注说明：各属性标了 `nonisolated(unsafe)`。
//
//  这样接入方在 Swift 6 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`）下可以
//  直接 `import ReaderKit`，无需退化为 `@preconcurrency import`——由库自己承担
//  这些全局的责任，而不是把告警推给使用方。
//
//  为什么不用 `@MainActor`：阅读器绝大多数访问确实在主线程，但本地 txt 解析
//  （`ReaderFastTextFileParser.parser(url:completion:)`）跑在 `DispatchQueue.global()` 上，
//  其中 `reviseFont()` 会读 `fonts`。标 `@MainActor` 会与这条既有路径冲突。
//  故如实标为 unsafe：契约靠上面那条「先配置、后只读」保证，而非类型系统。
//

import Foundation
import UIKit

/// 阅读器引擎的共享环境。
public enum ReaderEnvironment {

    /// 引擎使用的文案表。宿主未配置时为英文默认值。
    ///
    /// 宿主应在展示阅读器之前设置，例如在阅读器入口处：
    /// ```swift
    /// ReaderEnvironment.strings = MyReaderStringsFactory.make()
    /// ```
    nonisolated(unsafe) public static var strings: ReaderStrings = .default

    /// 引擎使用的图片资源。宿主未配置时为库内默认资源。
    nonisolated(unsafe) public static var images: ReaderImages = .default

    /// 引擎使用的字体。宿主未配置时为库内自带字型。
    ///
    /// 字体属各接入方的设计体系，故可整体覆盖：
    /// ```swift
    /// var fonts = ReaderFonts()
    /// fonts.bodyText = { UIFont.myBrandSerif($0) }
    /// ReaderEnvironment.fonts = fonts
    /// ```
    nonisolated(unsafe) public static var fonts: ReaderFonts = ReaderFonts()

    /// 宿主环境配置（CDN 图片处理、书签上限等）。宿主未配置时为库内默认实现。
    ///
    /// 与文案同理放环境而非注入点：这些配置的使用处在 String / Model 扩展里，
    /// 拿不到阅读器控制器实例。
    nonisolated(unsafe) public static var hostConfiguration: ReaderHostConfiguring = ReaderDefaultHostConfiguration()

    /// 阅读主题配色来源。库自带中性默认配色，接入方应注入自己的设计配色。
    ///
    /// 库只定义主题槽位（`ReaderThemeType`），每个槽位的色值由接入方决定。
    nonisolated(unsafe) public static var themeProvider: ReaderThemeProviding = ReaderDefaultThemeProvider()

    /// 展示错误提示（Toast / Snackbar）。
    ///
    /// 引擎在章节加载失败等场景需要给用户一个轻提示，但 Toast 的样式、层级、
    /// 停留时长属接入方的设计体系，故由接入方提供实现。
    ///
    /// 默认空实现：不配置则不弹提示（引擎不会因此出错，只是少一次提示）。
    ///
    /// - Parameters:
    ///   - container: 触发提示的视图，接入方可据此决定挂载位置
    ///   - message: 已本地化的提示文案
    nonisolated(unsafe) public static var presentErrorNotice: (_ container: UIView, _ message: String) -> Void = { _, _ in }
    /// 造一个「加载中」指示视图。目前用在目录列表末尾（分页补全期间）。
    ///
    /// 转圈长什么样属接入方的设计体系 —— 系统菊花、Lottie、自绘都行 —— 所以由接入方造，
    /// 库只负责摆位置与显隐。和 `images` / `fonts` 同一个路子。
    ///
    /// 约定三条：
    ///
    /// - **返回的视图自己会动。** 库不会调 `startAnimating()` 一类的方法，
    ///   因为它不知道你给的是什么。
    /// - **返回的视图要能自己决定大小**（有固有尺寸，或自带宽高约束）。库用约束把它居中、
    ///   不设它的尺寸 —— 否则像 `LottieAnimationView` 这种没有固有尺寸的会是 0×0，
    ///   表现为「loading 出现了但什么都看不到」。
    /// - `tintColor` 是当前阅读主题的次要文字色。用不上可以忽略（Lottie 的配色烤在文件里）。
    ///
    /// 主题切换时库会**重建**这个视图，所以实现里只需按传入的颜色一次性配置好，
    /// 不必考虑后续换色。
    ///
    /// 默认实现是系统菊花，不注入也能用。
    nonisolated(unsafe) public static var makeLoadingIndicator: (_ tintColor: UIColor) -> UIView = { tintColor in
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = tintColor
        indicator.startAnimating()
        return indicator
    }

    /// 诊断日志出口。默认丢弃。
    ///
    /// 库内不直接 `print`：既污染接入方的日志系统，也会在 Release 里留下噪音。
    /// 接上接入方自己的日志设施后，朗读、远程控制这类**只能靠现象推断**的路径才有据可查 ——
    /// 锁屏与控制中心的状态问题反复出现过多轮，每轮都靠猜，代价很高。
    nonisolated(unsafe) public static var log: (_ message: String) -> Void = { _ in }

    /// 朗读时当前句的高亮样式。默认背景色块。
    ///
    /// 放环境而非 `ReaderConfiguration`：这是**接入方**的设计取向，不是终端用户
    /// 可调的阅读设置。`ReaderConfiguration` 的字段都会被持久化并出现在设置面板里，
    /// 把它塞进去会让「用户改过的设置」与「接入方定的样式」混在同一份存储里。
    ///
    /// 具体色值取自当前主题的 `speechHighlightFill` / `speechHighlightText`。
    nonisolated(unsafe) public static var speechHighlightStyle: ReaderSpeechHighlightStyle = .background
}

/// 阅读器引擎所需的图片资源。
///
/// 与文案同理用配置结构体注入，让引擎不直接引用接入方的业务图片枚举。
///
/// 字段类型是 `() -> UIImage?` 闭包而非 `ImageResource`：
/// - `ImageResource` 是 Xcode 按 App 的 `.xcassets` 生成的符号，且要求 iOS 17+，
///   库内不可用（库有自己的 resource bundle，接入方的 asset 名也各不相同）
/// - 用闭包让接入方自由决定图片来源（asset、bundle、网络缓存皆可），
///   返回可选值则允许「不提供该图」的情形
public struct ReaderImages {

    /// 书签列表空态插图（无记录）。返回 nil 时不显示插图。
    public var bookmarkEmpty: () -> UIImage? = { nil }

    // MARK: - 顶栏

    /// 返回按钮（阅读菜单顶栏）
    public var back: () -> UIImage? = { symbol("chevron.left") }

    /// 返回按钮（正文顶部状态栏）
    public var statusBarBack: () -> UIImage? = { symbol("chevron.left") }

    /// 反馈入口
    public var feedback: () -> UIImage? = { symbol("exclamationmark.bubble") }

    /// 加入书架
    public var addToBookshelf: () -> UIImage? = { symbol("plus.square") }

    /// 已在书架
    public var addedToBookshelf: () -> UIImage? = { symbol("checkmark.square") }

    // MARK: - 设置面板

    /// 缩小字号
    public var fontSizeDecrease: () -> UIImage? = { symbol("textformat.size.smaller") }

    /// 放大字号
    public var fontSizeIncrease: () -> UIImage? = { symbol("textformat.size.larger") }

    /// 减小行距
    public var lineSpacingDecrease: () -> UIImage? = { symbol("text.justify") }

    /// 增大行距
    public var lineSpacingIncrease: () -> UIImage? = { symbol("text.justify.leading") }

    /// 上下滚动模式
    public var readingModeVertical: () -> UIImage? = { symbol("arrow.up.arrow.down") }

    /// 左右翻页模式
    public var readingModeHorizontal: () -> UIImage? = { symbol("arrow.left.arrow.right") }

    /// 进度条滑块
    public var progressThumb: () -> UIImage? = { symbol("circle.fill") }

    // MARK: - 底部标签栏

    /// 目录标签
    public var tabCatalogue: () -> UIImage? = { symbol("list.bullet") }

    /// 书签标签（未选中）
    public var tabBookmark: () -> UIImage? = { symbol("bookmark") }

    /// 书签标签（选中）
    public var tabBookmarkSelected: () -> UIImage? = { symbol("bookmark.fill") }

    /// 切换到夜间
    public var nightMode: () -> UIImage? = { symbol("moon") }

    /// 切换到日间
    public var dayMode: () -> UIImage? = { symbol("sun.max") }

    // MARK: - 其它

    /// 电量外壳（含正极头）。
    ///
    /// **默认 nil，此时库自己画外壳**（几何照设计稿，见 `ReaderBatteryView`）。
    /// 想用自己的设计资产时注入即可，电量条仍由库绘制并跟随主题色。
    ///
    /// 1.13.0 之前默认值是 SF Symbol `battery.100` —— 那个图形**自带满格填充**，
    /// 库再把电量条叠上去就是一块实心疙瘩，凡是没注入自己切图的接入方开箱即错。
    /// 改为 nil 之后「不注入」这条路径才是正确的。
    ///
    /// **注入时请遵守外壳比例**：总宽 20 份中外壳占 19、正极头占 1，描边宽为高度的 1/10。
    /// 电量条按这个比例内缩绘制（四边各留 1pt 的缝，与设计稿一致），
    /// 外壳比例偏离太多时填充会对不上内腔。
    public var battery: () -> UIImage? = { nil }

    /// 书封占位图。系统无对应图形，默认不显示，接入方按需提供。
    public var coverPlaceholder: () -> UIImage? = { nil }

    /// 展开箭头（目录面板头部「当前章节」右侧的指示箭头，按主题染色）
    public var disclosureArrow: () -> UIImage? = { symbol("chevron.right") }

    // MARK: - 书签与锁定

    /// 书签徽标图标（书签 cell 左侧圆形徽标内的小图，按主题染色）
    public var bookmarkBadge: () -> UIImage? = { symbol("bookmark.fill") }

    /// 章节锁定图标（目录 cell 与书签分组头，按主题染色）
    public var chapterLocked: () -> UIImage? = { symbol("lock") }

    /// 书签列表中锁定章节提示区的插图。
    ///
    /// 参数为当前阅读主题，接入方可据此返回不同切图（该图通常是彩色插图、不做染色，
    /// 故需按主题分别提供）。库内默认不区分主题。
    public var bookmarkLockSeal: (ReaderThemeType) -> UIImage? = { _ in symbol("lock.fill") }

    // MARK: - 朗读

    /// 朗读入口（开始朗读）
    public var speechPlay: () -> UIImage? = { symbol("headphones") }

    /// 朗读控制条 - 暂停
    public var speechPause: () -> UIImage? = { symbol("pause.fill") }

    /// 朗读控制条 - 继续
    public var speechResume: () -> UIImage? = { symbol("play.fill") }

    /// 呼出菜单上朗读 dock 的入口图标（入口态那个 32×32 的耳机）。
    ///
    /// 与 `speechPlay` 分开而不是复用：页脚胶囊里那个图标只有 16pt，接入方的切图通常
    /// 就按 16pt 出（48px @3x），放到 32pt 会明显发虚。两处尺寸差一倍，各给一个槽。
    public var speechDockEntry: () -> UIImage? = { symbol("headphones") }

    /// 回到朗读位置（朗读中但用户已翻到别页时出现在控制胶囊最左侧）
    public var speechReturnToPlaying: () -> UIImage? = { symbol("arrow.uturn.left") }

    // MARK: - 远程图片

    /// 远程图片加载（当前仅用于目录抽屉里的书封）。
    ///
    /// 引擎不内置网络图片库：缓存策略、解码、占位与失败重试都属接入方的基础设施。
    /// 默认实现只贴占位图，保证不配置也能正常显示。
    ///
    /// - Parameters:
    ///   - imageView: 目标视图
    ///   - url: 图片地址（引擎已按需拼好压缩参数）
    ///   - placeholder: 加载中/失败时的占位图
    public var loadRemoteImage: (_ imageView: UIImageView, _ url: String, _ placeholder: UIImage?) -> Void = {
        imageView, _, placeholder in
        imageView.image = placeholder
    }

    /// 全部取系统 SF Symbols 的默认实现。
    ///
    /// 库不携带任何图片资源，接入方通常整体覆盖为自己设计体系里的图标；
    /// 不覆盖也能跑起来，只是外观是系统符号风格。
    public static let `default` = ReaderImages()

    public init() {}

    /// 取系统符号图标，统一按 template 渲染以便跟随阅读主题染色。
    private static func symbol(_ name: String) -> UIImage? {
        UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate)
    }
}
