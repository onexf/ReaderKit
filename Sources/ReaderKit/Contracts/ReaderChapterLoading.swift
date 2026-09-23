//
//  ReaderChapterLoading.swift
//  Reader Engine — Contracts
//
//  章节内容加载注入点。
//
//  引擎在需要某一章的正文时（翻章、跳章、滚动预加载）调用它。
//  「从哪拿内容」——接口、CDN 调度、解密、缓存策略——全归宿主，引擎只要拿到章节模型。
//
//  返回值类型仍是引擎的 `ReaderChapterModel`：它是引擎的章节本地模型
//  （分页结果、正文富文本都在其中），属引擎资产而非业务模型，故可出现在协议里。
//

import Foundation

/// 一次加载请求的派发结果。
///
/// ## 为什么不是 `Bool`
///
/// 1.29.x 之前这里是 `Bool`，语义是「请求是否已真正派发」。文档写明 `false` 只表示
/// 被节流，但实现方很自然地也拿 `false` 表示「同一章已在途，去重了」——
/// 两者对调用方的要求完全相反：
///
/// - 被节流 → 回调不会来，调用方必须自己收尾
/// - 去重 → 在途那次会完成，回调**应该**送达
///
/// 混用的后果是引擎把「去重」当成「回调不会来」而提前收尾。朗读那条路径的收尾是
/// `stop()`，于是**连续切章时朗读会莫名暂停** —— 而且只在操作够快、撞上在途请求时
/// 才出现，很难复现。换成枚举是为了让这个区分在**编译期**存在：实现方必须表态。
public enum ReaderChapterLoadDispatch: Sendable {

    /// 已发起加载，两个回调之一一定会来。
    case dispatched

    /// 同一章已有在途请求，本次回调挂在那一次上，一定会来。
    ///
    /// 对引擎而言和 `.dispatched` 等价（都是「等回调」），单列出来是为了让实现方
    /// 在去重时有一个**语义正确**的返回值可选，不必被迫回 `.throttled`。
    case joined

    /// 被节流（冷却中或超过重试上限）。**两个回调都不会来**，调用方需自行收尾
    /// （隐藏 loading、清理待加载标记、恢复手势、停止朗读）。
    case throttled

    /// 回调会不会来。引擎判断「要不要自己收尾」只看这一个。
    public var willCallBack: Bool { self != .throttled }
}

/// 章节加载能力。由宿主（或引擎子类）实现。
public protocol ReaderChapterLoading: AnyObject {

    /// 请求指定章节的内容。
    ///
    /// - Parameters:
    ///   - chapterId: 章节 ID
    ///   - isManualRetry: 是否用户手动重试。实现方可据此绕开失败节流。
    ///   - fallbackChapterName: 章节名兜底，用于加载失败时的提示文案
    ///   - successBlock: 成功回调，返回引擎章节模型
    ///   - failureBlock: 失败回调
    /// - Returns: 本次请求的派发结果，见 `ReaderChapterLoadDispatch`。
    ///   **同一章已在途时请返回 `.joined`，不要返回 `.throttled`。**
    @discardableResult
    func loadChapter(chapterId: Int,
                     isManualRetry: Bool,
                     fallbackChapterName: String?,
                     successBlock: @escaping (ReaderChapterModel) -> Void,
                     failureBlock: ((Error) -> Void)?) -> ReaderChapterLoadDispatch
}

extension ReaderChapterLoading {

    /// 便捷重载：常规加载（非手动重试、无章节名兜底）。
    @discardableResult
    public func loadChapter(chapterId: Int,
                     successBlock: @escaping (ReaderChapterModel) -> Void,
                     failureBlock: ((Error) -> Void)? = nil) -> ReaderChapterLoadDispatch {
        loadChapter(chapterId: chapterId,
                    isManualRetry: false,
                    fallbackChapterName: nil,
                    successBlock: successBlock,
                    failureBlock: failureBlock)
    }
}
