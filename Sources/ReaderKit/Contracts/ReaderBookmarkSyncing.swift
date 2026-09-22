//
//  ReaderBookmarkSyncing.swift
//  Reader Engine — Contracts
//
//  书签远端同步注入点。
//
//  职责边界：书签的**本地模型与列表 UI 归引擎**（ReaderBookmarkModel、书签面板都在引擎内），
//  这里只抽「与服务端同步」这一段。宿主实现网络细节，引擎不感知接口与鉴权。
//
//  同步策略保持现状不变：悲观更新——服务端成功后引擎才写本地、切图标、刷新列表。
//

import Foundation

/// 新增书签时提交给宿主的中立请求体。
///
/// 不复用接入方的业务网络模型，否则库会带着业务模型走。
public struct ReaderBookmarkDraft {
    /// 书籍 ID
    public let storyId: Int
    /// 章节 ID
    public let chapterId: Int
    /// 书签起点：章节内字符偏移（`typesetContent` 坐标系，含标题与排版后正文，UTF-16）。定位主键。
    public let textLocation: Int
    /// 文字摘要：章节内容变更导致 offset 失配时的兜底锚点，非定位主键。
    public let excerptText: String?

    public init(storyId: Int, chapterId: Int, textLocation: Int, excerptText: String?) {
        self.storyId = storyId
        self.chapterId = chapterId
        self.textLocation = textLocation
        self.excerptText = excerptText
    }
}

/// 新增书签成功后，宿主回给引擎的中立结果。
public struct ReaderBookmarkReceipt {
    /// 服务端分配的书签 ID，引擎回填到本地模型
    public let remoteMarkID: Int
    /// 服务端创建时间（**毫秒**）。引擎按秒存储，故会除以 1000。
    public let createdAtMilliseconds: Int?

    public init(remoteMarkID: Int, createdAtMilliseconds: Int?) {
        self.remoteMarkID = remoteMarkID
        self.createdAtMilliseconds = createdAtMilliseconds
    }
}

/// 书签远端同步能力。宿主实现并注入；未注入时书签只存本地、不与服务端同步。
public protocol ReaderBookmarkSyncing: AnyObject {

    /// 进入阅读器后台同步：先拉服务端书签与本地合并，再上报本地独有的书签。
    ///
    /// - Parameter storyId: 书籍 ID
    func syncBookmarks(storyId: Int)

    /// 新增书签。
    ///
    /// 引擎采用悲观更新：仅当回调 `.success` 时才写入本地并切换 UI。
    func addBookmark(_ draft: ReaderBookmarkDraft,
                     completion: @escaping (Result<ReaderBookmarkReceipt, Error>) -> Void)

    /// 删除单条书签。
    ///
    /// 实现方应把「服务端返回书签不存在」也视为成功，避免本地残留删不掉。
    func removeBookmark(storyId: Int, remoteMarkID: Int, completion: @escaping (Bool) -> Void)

    /// 批量删除书签。空列表应直接回 `true`。
    func removeBookmarks(storyId: Int, remoteMarkIDs: [Int], completion: @escaping (Bool) -> Void)

    /// 按书清空全部书签。
    func removeAllBookmarks(storyId: Int, completion: @escaping (Bool) -> Void)
}
