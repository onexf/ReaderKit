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

    // MARK: - 屏幕

    public static var screenBounds: CGRect { UIScreen.main.bounds }
    public static var screenSize: CGSize { UIScreen.main.bounds.size }
    public static var screenWidth: CGFloat { UIScreen.main.bounds.width }
    public static var screenHeight: CGFloat { UIScreen.main.bounds.height }

    // MARK: - 安全区

    /// 当前窗口安全区（取不到窗口时为 .zero）
    public static var safeAreaInsets: UIEdgeInsets { currentWindow?.safeAreaInsets ?? .zero }

    /// 安全区顶部高度（刘海 / 灵动岛 / 状态栏占位）
    public static var safeAreaTop: CGFloat { safeAreaInsets.top }

    /// 安全区底部高度（Home Indicator 占位）
    public static var safeAreaBottom: CGFloat { safeAreaInsets.bottom }

    // MARK: - 导航栏

    /// 导航栏高度（安全区顶部 + 44 导航条）
    public static var navBarHeight: CGFloat { safeAreaTop + 44 }
}
