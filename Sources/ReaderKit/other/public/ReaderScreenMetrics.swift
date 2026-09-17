//
//  ReaderScreenMetrics.swift
//  Reader Engine
//
//  引擎自包含的屏幕度量：屏幕尺寸、安全区、导航栏高度。
//
//  为什么不复用接入方的屏幕度量工具：那类工具的取窗口逻辑往往带有对特定三方弹窗库的
//  特判，引擎不该感知。引擎只需一个通用、无业务依赖的度量来源，故在此自实现，
//  取「首个前台激活场景的 keyWindow」，对阅读器场景足够。
//

import UIKit

/// 阅读器引擎使用的屏幕度量。全部为只读计算属性，无状态、无业务依赖。
public enum ReaderScreenMetrics {

    /// 当前用于取安全区、也用于承载浮层（如清空书签确认弹窗）的窗口。
    ///
    /// 引擎内需要把视图挂到 window 上时统一走这里，不要各处再自行遍历 scene。
    public static var keyWindow: UIWindow? { currentWindow }

    /// 当前用于取安全区的窗口：优先前台激活场景的 keyWindow，兜底任意 keyWindow。
    private static var currentWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first
    }

    /// 处于**前台激活**场景时的安全区。非前台、或窗口尚未布局好时返回 nil。
    private static var foregroundSafeAreaInsets: UIEdgeInsets? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        // 只认前台激活场景：后台（含锁屏）场景的窗口安全区不可信
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }

        let insets = window.safeAreaInsets

        // 全面屏设备上顶部安全区恒大于 0；取到 0 说明窗口还没布局好，同样不可信
        guard insets.top > 0 else { return nil }

        return insets
    }

    /// 最近一次在前台取到的有效安全区。
    ///
    /// **存在理由**：后台（含锁屏）时取不到可信的窗口安全区，而朗读跨章会在后台触发
    /// 重新分页（`ReaderChapterModel.reviseFont()`），分页尺寸直接依赖安全区。
    /// 一旦后台算出与前台不同的尺寸，回到前台后正文就会按那份错误分页渲染 ——
    /// 实际表现为页数不对（8 页 / 7 页来回变）、首页大片空白、章节标题重复出现。
    ///
    /// 所以后台一律沿用前台缓存值，保证「后台分的页」与「前台渲染用的尺寸」一致。
    nonisolated(unsafe) private static var cachedSafeAreaInsets: UIEdgeInsets?

    // MARK: - 屏幕

    public static var screenBounds: CGRect { UIScreen.main.bounds }
    public static var screenSize: CGSize { UIScreen.main.bounds.size }
    public static var screenWidth: CGFloat { UIScreen.main.bounds.width }
    public static var screenHeight: CGFloat { UIScreen.main.bounds.height }

    // MARK: - 安全区

    /// 当前窗口安全区。
    ///
    /// 前台取实时值并缓存；后台（含锁屏）沿用缓存 —— 理由见 `cachedSafeAreaInsets`。
    /// 进入阅读器必然经过前台，所以缓存不会为空；真为空才回落 `.zero`。
    public static var safeAreaInsets: UIEdgeInsets {

        if let insets = foregroundSafeAreaInsets {

            cachedSafeAreaInsets = insets

            return insets
        }

        return cachedSafeAreaInsets ?? .zero
    }

    /// 安全区顶部高度（刘海 / 灵动岛 / 状态栏占位）
    public static var safeAreaTop: CGFloat { safeAreaInsets.top }

    /// 安全区底部高度（Home Indicator 占位）
    public static var safeAreaBottom: CGFloat { safeAreaInsets.bottom }

    // MARK: - 导航栏

    /// 导航栏高度（安全区顶部 + 44 导航条）
    public static var navBarHeight: CGFloat { safeAreaTop + 44 }
}
