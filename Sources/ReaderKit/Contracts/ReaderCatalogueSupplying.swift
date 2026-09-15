//
//  ReaderCatalogueSupplying.swift
//  Reader Engine — Contracts
//
//  目录补齐注入点。
//
//  背景：目录是分页加载的，阅读器可能在目录尚未加载完整时就翻到了已加载章节的边界。
//  此时不能判定为「已是最后一章」，必须请宿主补齐后续目录，否则会卡住或误判末章。
//
//  引擎负责「发现需要补目录」（三处触发：目录列表滚到底、书签跳转的章节不在已加载目录里、
//  翻章翻到已加载边界），宿主负责「怎么补」（分页续传、全量校准、防重入都归宿主）。
//

import Foundation

/// 引擎请求补目录的触发场景，供宿主区分处理策略与埋点。
public enum ReaderCatalogueDemand {
    /// 目录列表滚动到底部
    case catalogueScrolledToBottom
    /// 书签指向的章节不在已加载目录中
    case bookmarkTargetMissing
    /// 翻章时到达已加载章节的边界
    case chapterBoundaryReached
}

/// 目录补齐能力。宿主实现并注入；未注入时引擎按「目录已完整」处理。
public protocol ReaderCatalogueSupplying: AnyObject {

    /// 请求补齐后续目录。
    ///
    /// 实现方需自行处理防重入与「目录已完整则直接返回」。
    /// - Parameter demand: 触发场景
    func supplyMoreCatalogue(for demand: ReaderCatalogueDemand)
}
