//
//  ReaderPlaceholderProviding.swift
//  Reader Engine — Contracts
//
//  空态视图注入点：首次加载失败（网络错误、可重试）时展示的占位视图。
//
//  引擎负责「何时显示、何时隐藏、点重试后重新加载」，宿主负责「长什么样」。
//  这样各接入方可以用自己设计体系里的空态组件。
//

import UIKit

/// 加载失败占位视图需要向引擎暴露的能力。
public protocol ReaderPlaceholderView: AnyObject {

    /// 点击重试的回调。引擎在创建后设置，用户点击时触发重新加载。
    var onRetry: (() -> Void)? { get set }

    /// 点击返回的回调。引擎在创建后设置。
    var onBack: (() -> Void)? { get set }
}

/// 占位视图：既是 `UIView`（引擎需要把它加进视图层级），又满足 `ReaderPlaceholderView`。
public typealias ReaderPlaceholderViewType = UIView & ReaderPlaceholderView

/// 空态视图工厂。宿主实现并注入；未注入时加载失败不显示占位视图。
public protocol ReaderPlaceholderProviding: AnyObject {

    /// 创建「加载失败，可重试」占位视图。
    func makeLoadFailurePlaceholder() -> ReaderPlaceholderViewType
}
