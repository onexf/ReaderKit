//
//  ReaderBookshelfManaging.swift
//  Reader Engine — Contracts
//
//  书架 / 收藏注入点。
//
//  引擎需要它做这些事：
//  1. 菜单上的收藏按钮要显示当前是否已收藏，并在状态变化时刷新
//  2. 用户点收藏、或满足自动加书架条件时，请宿主执行加入书架
//  3. 章节切换后请宿主刷新一次书籍状态（收藏、解锁等由服务端下发的状态）
//
//  「什么时候该加书架」的判定（阅读时长阈值、已读章节数阈值）留在引擎，
//  因为那是阅读行为；「加书架这件事怎么做」（接口、参数、通知广播）归宿主。
//
//  状态变化用回调而非 Combine `@Published`：协议不绑定响应式框架，
//  纯 UIKit 项目也能实现。宿主内部照旧可以用 Combine，只是在变化时调回调。
//

import Foundation

/// 加入书架的触发来源。宿主可据此区分「用户主动点」与「阅读达标自动加」的接口参数或上报。
public enum ReaderShelfTrigger {
    /// 用户在阅读菜单点击收藏
    case userTapped
    /// 阅读行为达标后自动加入（引擎按阅读时长 / 已读章节数判定）
    case readingMilestone(chapterId: Int)
}

/// 书架能力。宿主实现并注入；未注入时阅读器无收藏功能（菜单按钮应由宿主自行隐藏）。
public protocol ReaderBookshelfManaging: AnyObject {

    /// 当前书籍是否已在书架中。
    ///
    /// 引擎用它决定收藏按钮状态，并避免重复加入。宿主状态变化后需调用
    /// `onShelfStateChanged` 通知引擎刷新 UI。
    var isOnShelf: Bool { get }

    /// 加入书架。
    ///
    /// - Parameters:
    ///   - trigger: 触发来源
    ///   - readingSeconds: 本次累计阅读时长（秒），宿主可用于上报或风控
    func addToShelf(trigger: ReaderShelfTrigger, readingSeconds: Int)

    /// 请求刷新书籍状态（收藏态、章节解锁态等服务端下发字段）。引擎在章节切换后调用。
    func refreshBookStatus(chapterId: Int)

    /// 引擎注册状态回调。宿主在收藏态变化、或收藏失败时回调，引擎据此刷新按钮与提示。
    ///
    /// - Parameters:
    ///   - onShelfStateChanged: 收藏态变化，参数为最新状态
    ///   - onError: 收藏操作失败，参数为可直接展示给用户的错误文案
    func observeShelfState(onShelfStateChanged: @escaping (Bool) -> Void,
                           onError: @escaping (String) -> Void)
}
