//
//  ReaderBookModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/21.
//

import UIKit

/// 归档用的固定 ObjC 类名。Swift 类归档时写入「模块名.类名」，
/// 一旦模块名或 Swift 类名变化，旧归档就反序列化不出来（老用户进度与书签丢失）。
/// 用 @objc 固定为无模块前缀的名字后，归档格式与模块名、Swift 名解耦。
/// **该名字一经发布不可再改。**
@objc(ReaderBookModel)
open class ReaderBookModel: NSObject, NSCoding {

    /// 小说ID
    open var bookID: String!
    
    /// 小说名称
    open var bookName: String!
    
    /// 小说封面
    open var bookCover: String?
    
    /// 作者
    open var author: String?
    
    /// 短剧代码（用于埋点）
    open var shortPlayCode: Int = 0
    
    /// 章节总数
    open var totalEpisodes: Int = 0
    
    /// 小说来源类型
    open var bookSourceType: ReaderBookSourceType! = .network
    
    /// 当前阅读记录
    open var recordModel: ReaderReadRecordModel!
    
    /// 书签列表
    open var markModels: [ReaderBookmarkModel]! = []
    
    /// 章节列表(如果是网络小说可以不需要放在这里记录,直接在目录视图里面加载接口或者读取本地数据库就好了。)
    open var chapterListModels: [ReaderChapterListItemModel]! = []
    
    
    // MARK: 快速进入
    
    /// 本地小说全文
    open var fullText: String!
    
    /// 章节内容范围数组 [章节ID:[章节优先级:章节内容Range]]
    open var ranges: [String: [String: NSRange]]!
    
    
    // MARK: - 目录完整性与权威章节链接（分页目录加载防误判末章）
    
    /// 目录是否已完整加载（分页补全完成）。
    /// 由接入方的目录加载器维护：加载到末页 / 后台补全成功时置 true。
    /// 非持久化（不参与 NSCoding）：每次阅读会话重新判定，默认保守为 false，避免旧会话状态误导。
    open var isDirectoryFullyLoaded: Bool = false
    
    /// 章节目录是否已包含全书所有章节。满足任一即视为完整：
    ///   1. 本地书（一次性全量解析，无分页）
    ///   2. loader 明确置位 isDirectoryFullyLoaded（加载到末页 / 后台补全成功）
    ///   3. 已加载章节数达到全书总集数（二次进入缓存已满、标志尚未置位时的兜底）
    /// 仅当目录完整时，已加载列表的最后一条才允许被判为「全书末章」。
    open var isChapterListComplete: Bool {
        if bookSourceType == .local { return true }
        if isDirectoryFullyLoaded { return true }
        let loaded = chapterListModels?.count ?? 0
        return totalEpisodes > 0 && loaded >= totalEpisodes
    }
    
    /// 基于当前 chapterListModels 权威解析指定章节的下一章 ID
    /// （不信任可能过期 / 被污染的 chapterModel.nextChapterID）。
    /// - Returns:
    ///   - 非 nil：存在下一章（返回其 id）
    ///   - nil：已是已加载列表最后一条。需结合 `isChapterListComplete` 甄别：
    ///     complete==true 为全书真末章；complete==false 为下一章尚未加载（应补目录，切勿当末章）。
    /// - Note: `READER_NO_MORE_CHAPTER` 本身即 nil，故本方法返回 nil 的两种语义必须由调用方区分。
    open func resolvedFollowingChapterID(forChapterID chapterID: NSNumber?) -> NSNumber? {
        guard let chapterID = chapterID,
              let list = chapterListModels,
              let idx = list.firstIndex(where: { $0.id == chapterID }) else { return nil }
        if idx < list.count - 1 {
            return list[idx + 1].id
        }
        return nil
    }
    
    /// 权威判定：指定章节是否为「全书真正的最后一章」。
    /// 不依赖可能被污染的 chapterModel.nextChapterID / isLastChapter，仅基于目录完整性 + 列表位置。
    /// 目录未完整时一律返回 false（无法确定末章），从根本上杜绝分页未加载完时误判末章而触发 END。
    open func isAuthoritativeFinalChapter(chapterID: NSNumber?) -> Bool {
        guard isChapterListComplete else { return false }
        guard let chapterID = chapterID,
              let list = chapterListModels, !list.isEmpty,
              let idx = list.firstIndex(where: { $0.id == chapterID }) else { return false }
        return idx == list.count - 1
    }
    
    
    // MARK: 辅助
    
    /// 保存
    open func save() {
        
        recordModel.save()
        
        ReaderArchiver.archiver(folderName: bookID, fileName: READER_KEY_OBJECT, object: self)
    }
    
    /// 是否存在阅读对象
    public class func isExist(bookID: String!) ->Bool {
        
        return ReaderArchiver.isExist(folderName: bookID, fileName: READER_KEY_OBJECT)
    }
    
    
    // MARK: 构造
    
    /// 获取阅读对象,如果则创建对象返回
    @objc public class func model(bookID: String!) ->ReaderBookModel {
        
        var readModel: ReaderBookModel!
        
        if ReaderBookModel.isExist(bookID: bookID) {
            
            readModel = ReaderArchiver.unarchiver(folderName: bookID, fileName: READER_KEY_OBJECT) as? ReaderBookModel
            
        }else{
            
            readModel = ReaderBookModel()
            
            readModel.bookID = bookID
        }
        
        // 获取阅读记录
        readModel.recordModel = ReaderReadRecordModel.model(bookID: bookID)
        
        return readModel
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        bookID = aDecoder.decodeObject(forKey: "bookID") as? String
        
        bookName = aDecoder.decodeObject(forKey: "bookName") as? String
        
        bookCover = aDecoder.decodeObject(forKey: "bookCover") as? String
        
        author = aDecoder.decodeObject(forKey: "author") as? String
        
        shortPlayCode = (aDecoder.decodeObject(forKey: "shortPlayCode") as? NSNumber)?.intValue ?? 0
        
        totalEpisodes = (aDecoder.decodeObject(forKey: "totalEpisodes") as? NSNumber)?.intValue ?? 0
        
        bookSourceType = ReaderBookSourceType(rawValue: (aDecoder.decodeObject(forKey: "bookSourceType") as! NSNumber).intValue)
        
        chapterListModels = aDecoder.decodeObject(forKey: "chapterListModels") as? [ReaderChapterListItemModel]
        
        markModels = aDecoder.decodeObject(forKey: "markModels") as? [ReaderBookmarkModel]
        
        fullText = aDecoder.decodeObject(forKey: "fullText") as? String
        
        ranges = aDecoder.decodeObject(forKey: "ranges") as? [String: [String: NSRange]]
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(bookID, forKey: "bookID")
        
        aCoder.encode(bookName, forKey: "bookName")
        
        aCoder.encode(bookCover, forKey: "bookCover")
        
        aCoder.encode(author, forKey: "author")
        
        aCoder.encode(NSNumber(value: shortPlayCode), forKey: "shortPlayCode")
        
        aCoder.encode(NSNumber(value: totalEpisodes), forKey: "totalEpisodes")
        
        aCoder.encode(NSNumber(value: bookSourceType.rawValue), forKey: "bookSourceType")
        
        aCoder.encode(chapterListModels, forKey: "chapterListModels")
        
        aCoder.encode(markModels, forKey: "markModels")
        
        aCoder.encode(fullText, forKey: "fullText")
        
        aCoder.encode(ranges, forKey: "ranges")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
