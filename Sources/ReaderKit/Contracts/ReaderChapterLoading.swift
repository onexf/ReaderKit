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
    /// - Returns: 请求是否已真正派发。返回 `false` 表示被节流（冷却中或超过重试上限），
    ///   此时 `successBlock` / `failureBlock` 都不会被调用，调用方需自行收尾
    ///   （隐藏 loading、清理待加载标记、恢复手势）。
    @discardableResult
    func loadChapter(chapterId: Int,
                     isManualRetry: Bool,
                     fallbackChapterName: String?,
                     successBlock: @escaping (ReaderChapterModel) -> Void,
                     failureBlock: ((Error) -> Void)?) -> Bool
}

extension ReaderChapterLoading {

    /// 便捷重载：常规加载（非手动重试、无章节名兜底）。
    @discardableResult
    public func loadChapter(chapterId: Int,
                     successBlock: @escaping (ReaderChapterModel) -> Void,
                     failureBlock: ((Error) -> Void)? = nil) -> Bool {
        loadChapter(chapterId: chapterId,
                    isManualRetry: false,
                    fallbackChapterName: nil,
                    successBlock: successBlock,
                    failureBlock: failureBlock)
    }
}
