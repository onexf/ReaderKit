//
//  ReaderBookModel+Reconcile.swift
//  ReaderKit
//
//  缓存目录与服务端对账:删除服务端已下架(本地缓存残留)的章节,
//  并清理其残留(章节内容缓存、书签),修正阅读记录。
//
//  调用前提:authoritativeIds 必须是「服务端完整章节 id 全集」。
//  仅在后台目录补全「全量成功」后调用;补全有任何一页彻底失败时不可调用,
//  否则会把未加载页里的章节误判为已删除。
//

import UIKit

extension ReaderBookModel {

    /// 用服务端权威 id 全集对账本地缓存目录。
    /// - Parameters:
    ///   - authoritativeIds: 服务端权威章节 id 全集(后台补全全量成功后收集到的)
    ///   - keepCurrentReadingId: 当前正在阅读的章节 id;即使服务端已删也不移除,
    ///     避免打断正在进行的阅读会话(下次进入会再次对账清理)
    /// - Returns: 被移除的章节 id 列表
    @discardableResult
    public func reconcileChapters(authoritativeIds: Set<Int>, keepCurrentReadingId: Int?) -> [Int] {

        guard let list = chapterListModels, !list.isEmpty, !authoritativeIds.isEmpty else { return [] }

        var removed: [Int] = []
        let kept = list.filter { model in
            guard let id = model.id?.intValue, id > 0 else { return true } // 无效 id 不动
            if authoritativeIds.contains(id) { return true }
            if let keep = keepCurrentReadingId, keep == id { return true }
            removed.append(id)
            return false
        }

        guard !removed.isEmpty else { return [] }

        chapterListModels = kept

        let removedSet = Set(removed)

        // 1. 清理被删章节的内容缓存文件(归档文件名 = chapterID 字符串)
        for id in removed {
            ReaderArchiver.remove(folderName: storyID, fileName: "\(id)")
        }

        // 2. 清理落在被删章节上的书签
        if let bookmarks = markModels, !bookmarks.isEmpty {
            let filtered = bookmarks.filter { mark in
                return !removedSet.contains(mark.chapterID.intValue)
            }
            if filtered.count != bookmarks.count {
                markModels = filtered
            }
        }

        // 3. 阅读记录修正:当前阅读章节已通过 keepCurrentReadingId 保留,记录仍有效;
        //    相邻章节链(previous/next)在下次翻章/加载时由 requestChapter 按 chapterListModels 重建,
        //    此处无需额外处理。

        save()

        // log("🧹 [目录对账] 移除已下架章节 \(removed.count) 个: \(removed)")

        return removed
    }
}
