//
//  ReaderBookModel+Mark.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/17.
//

import UIKit

/// 每本书书签数量上限(服务端 app_config.bookmarkMaxCount 未下发/非法时兜底 100)
public let READER_MARK_MAX_FALLBACK: Int = 100

/// 当前生效的书签上限:优先取宿主配置,无效时兜底
public var READER_MARK_MAX: Int {
    let configured = ReaderEnvironment.hostConfiguration.bookmarkMaxCount
    return configured > 0 ? configured : READER_MARK_MAX_FALLBACK
}

extension ReaderBookModel {

    /// 当前书签数是否已达上限
    public var isMarkLimitReached: Bool {
        return (bookmarkEntries?.count ?? 0) >= READER_MARK_MAX
    }

    /// 添加书签,默认使用当前阅读记录!(构造并立即写入,保留供本地直接添加路径使用)
    public func insetMark(readingRecord: ReaderReadRecordModel? = nil) {
        appendMark(buildMark(readingRecord: readingRecord))
    }
    
    /// 构造当前阅读位置的书签(锚定当前阅读记录,不写入 bookmarkEntries、不持久化)
    /// 用于"先上报服务端、成功后再写入"的悲观流程,保证书签数据锚定点击瞬间的位置
    public func buildMark(readingRecord: ReaderReadRecordModel? = nil) -> ReaderBookmarkModel {
        
        let readingRecord = (readingRecord ?? self.readingRecord)!
        
        let markModel = ReaderBookmarkModel()
        
        markModel.storyID = readingRecord.storyID
        
        markModel.chapterID = readingRecord.chapterModel.id
        
        if readingRecord.pageModel.isHomePage {
            
            markModel.name = ReaderEnvironment.strings.unnamedChapter
            
            markModel.content = storyName
            
            markModel.location = readingRecord.locationFirst
            
        }else{
            
            markModel.name = readingRecord.chapterModel.name
            
            // 滚动模式:由 page + 页内偏移反算精确字符位置,把"当前可见顶部"锚定为书签,
            // 避免只记 cell 起点导致跳转落到上一段(偏移)。其他翻页模式 cell 起点即页首,沿用 locationFirst。
            if ReaderConfiguration.shared().effectType == .scroll,
               let chapterModel = readingRecord.chapterModel,
               let full = chapterModel.typesetContent, full.length > 0 {
                
                let loc = chapterModel.location(forPage: readingRecord.page.intValue,
                                                inPageOffsetY: readingRecord.pageScrollAnchor)
                let clamped = min(max(loc, 0), full.length - 1)
                
                markModel.content = (full.string as NSString).substring(from: clamped).removeSEHeadAndTail.enterToSingleSpace
                markModel.location = NSNumber(value: clamped)
                
            } else {
                
                markModel.content = readingRecord.contentString.removeSEHeadAndTail.enterToSingleSpace
                markModel.location = readingRecord.locationFirst
            }
        }
        
        markModel.time = NSNumber(value: readerTimestamp())
        
        return markModel
    }
    
    /// 写入已构造的书签(插入到列表首位并持久化)
    public func appendMark(_ markModel: ReaderBookmarkModel) {
        
        // 去重:同章节同位置已存在则不重复写入(兜底悲观更新窗口内并发请求导致的重复添加)
        let exists = bookmarkEntries.contains {
            $0.chapterID.intValue == markModel.chapterID.intValue &&
            $0.location.intValue == markModel.location.intValue
        }
        if exists { return }
        
        if bookmarkEntries.isEmpty {
            
            bookmarkEntries.append(markModel)
            
        }else{
            
            bookmarkEntries.insert(markModel, at: 0)
        }
        
        save()
    }
    
    /// 移除当前书签
    public func discardMark(index: NSInteger) ->Bool {
        
        bookmarkEntries.remove(at: index)
        
        save()
        
        return true
    }
    
    /// 清空全部书签
    @discardableResult
    public func discardAllMarks() -> Bool {
        
        guard bookmarkEntries != nil, !bookmarkEntries.isEmpty else { return false }
        
        bookmarkEntries.removeAll()
        
        save()
        
        return true
    }
    
    /// 移除当前书签
    public func discardMark(readingRecord: ReaderReadRecordModel? = nil) ->Bool {
        
        let readingRecord = (readingRecord ?? self.readingRecord)!
        
        let markModel = isExistMark(readingRecord: readingRecord)
        
        if markModel != nil {
            
            let index = bookmarkEntries.index(of: markModel!)!
            
            return discardMark(index: index)
        }
        
        return false
    }
    
    /// 是否存在书签
    public func isExistMark(readingRecord: ReaderReadRecordModel? = nil) ->ReaderBookmarkModel? {
        
        if bookmarkEntries.isEmpty { return nil }
        
        let readingRecord = (readingRecord ?? self.readingRecord)!
        
        let locationFirst = readingRecord.locationFirst!
        
        let locationLast = readingRecord.locationLast!
        
        for markModel in bookmarkEntries {
            
            if markModel.chapterID == readingRecord.chapterModel.id {
                
                if (markModel.location.intValue >= locationFirst.intValue) && (markModel.location.intValue < locationLast.intValue) {
                    
                    return markModel
                }
            }
        }
        
        return nil
    }
}

// MARK: - 书签分组与排序

/// 书签分组(按章节聚合)
/// - chapterID:章节 ID
/// - chapterCaption:章节名称
/// - priority:章节排序序号(从 catalogueEntries 查得,查不到回退 Int.max 排到最后)
/// - isLocked:章节是否锁定(实时查 catalogueEntries)
/// - bookmarks:组内书签,按添加时间由近到远排列
public struct ReaderBookmarkCluster {
    public let chapterID: NSNumber
    public let chapterCaption: String
    public let priority: Int
    public let isLocked: Bool
    public var bookmarks: [ReaderBookmarkModel]
}

extension ReaderBookModel {

    /// 按 chapterID 查章节列表模型(用于取 priority / isLocked)
    public func chapterListModel(for chapterID: NSNumber?) -> ReaderChapterListItemModel? {
        guard let chapterID = chapterID else { return nil }
        return catalogueEntries?.first { $0.id == chapterID }
    }

    /// 生成书签分组列表
    /// - Parameter isAscendingOrder: 组间排序,true = 章节从小到大(默认),false = 从大到小
    /// - Returns: 分组数组;组内书签固定按时间由近到远(最新在前)
    public func markGroups(isAscendingOrder: Bool) -> [ReaderBookmarkCluster] {

        guard let bookmarks = bookmarkEntries, !bookmarks.isEmpty else { return [] }

        // 1. 按 chapterID 聚合(用字符串 key 避免 NSNumber 作为字典 key 的歧义)
        var buckets: [String: [ReaderBookmarkModel]] = [:]
        var order: [String] = []
        for mark in bookmarks {
            let key = (mark.chapterID ?? NSNumber(value: 0)).stringValue
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(mark)
        }

        // 2. 组装分组(组内按添加时间从远到近:旧的在前)
        var groups: [ReaderBookmarkCluster] = order.compactMap { key in
            guard let groupMarks = buckets[key], let first = groupMarks.first else { return nil }
            let sortedMarks = groupMarks.sorted { $0.time.intValue < $1.time.intValue }
            let listModel = chapterListModel(for: first.chapterID)
            return ReaderBookmarkCluster(
                chapterID: first.chapterID,
                chapterCaption: first.name ?? (listModel?.name ?? ""),
                priority: listModel?.priority?.intValue ?? Int.max,
                isLocked: listModel?.isLocked ?? false,
                bookmarks: sortedMarks
            )
        }

        // 3. 组间按 priority 排序(priority 相同回退按 chapterID)
        groups.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return isAscendingOrder ? (lhs.priority < rhs.priority) : (lhs.priority > rhs.priority)
            }
            let l = lhs.chapterID.intValue, r = rhs.chapterID.intValue
            return isAscendingOrder ? (l < r) : (l > r)
        }

        // 4. 锁定章节书签:只保留"最近一个"被锁定章节(priority 最小,离已读最近)的分组,其余锁定组不展示
        if let nearestLocked = groups.filter({ $0.isLocked }).min(by: { $0.priority < $1.priority }) {
            let keepChapterID = nearestLocked.chapterID.intValue
            groups = groups.filter { !$0.isLocked || $0.chapterID.intValue == keepChapterID }
        }

        return groups
    }

    /// 计算单条书签在「所属章节内」的阅读进度(0.0 ~ 1.0)
    /// = 书签 location / 该章富文本总长度;章节内容未加载或长度为 0 时返回 0
    public func markProgress(_ mark: ReaderBookmarkModel) -> Float {

        guard ReaderChapterModel.isExist(storyID: storyID, chapterID: mark.chapterID) else { return 0 }

        let chapterModel = ReaderChapterModel.model(storyID: storyID, chapterID: mark.chapterID, isUpdateFont: false)
        let fullLength = Float(chapterModel.typesetContent?.length ?? 0)

        guard fullLength > 0 else { return 0 }

        let progress = Float(mark.location.intValue) / fullLength
        return min(max(progress, 0), 1)
    }
}
