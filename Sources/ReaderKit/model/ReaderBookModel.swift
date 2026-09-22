//
//  ReaderBookModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/21.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 同理，属性改名时 `forKey:` 里的键名要保持原样（所以下面会看到名字对不上的成对写法）。
/// 键名跟着改的后果是已落盘的缓存解档拿到 nil，而这些字段是隐式解包可选 —— 访问即崩。
open class ReaderBookModel: NSObject, NSCoding {

    /// 小说ID
    open var storyID: String!
    
    /// 小说名称
    open var storyName: String!
    
    /// 小说封面
    open var coverURL: String?
    
    /// 作者
    open var writer: String?
    
    /// 接入方业务系统里的书籍编码。
    ///
    /// 引擎自身不使用该字段，仅负责随 `ReaderBookModel` 一同归档，供接入方在埋点、
    /// 跳转等场景取用（引擎内部标识书籍一律用 `storyID`）。
    open var externalBookCode: Int = 0
    
    /// 全书章节总数（由接入方从书籍详情写入）
    open var totalChapterCount: Int = 0
    
    /// 小说来源类型
    open var storySourceType: ReaderBookSourceType! = .network
    
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
    ///   3. 已加载章节数达到全书章节总数（二次进入缓存已满、标志尚未置位时的兜底）
    /// 仅当目录完整时，已加载列表的最后一条才允许被判为「全书末章」。
    open var isChapterListComplete: Bool {
        if storySourceType == .local { return true }
        if isDirectoryFullyLoaded { return true }
        let loaded = chapterListModels?.count ?? 0
        return totalChapterCount > 0 && loaded >= totalChapterCount
    }
    
    /// 基于当前 chapterListModels 权威解析指定章节的下一章 ID
    /// （不信任可能过期 / 被污染的 chapterModel.followingChapterID）。
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
    /// 不依赖可能被污染的 chapterModel.followingChapterID / isLastChapter，仅基于目录完整性 + 列表位置。
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
        
        ReaderArchiver.archiver(folderName: storyID, fileName: READER_KEY_OBJECT, object: self)
    }
    
    /// 是否存在阅读对象
    public class func isExist(storyID: String!) ->Bool {
        
        return ReaderArchiver.isExist(folderName: storyID, fileName: READER_KEY_OBJECT)
    }
    
    
    // MARK: 构造
    
    /// 获取阅读对象,如果则创建对象返回
    public class func model(storyID: String!) ->ReaderBookModel {
        
        var bookModel: ReaderBookModel!
        
        if ReaderBookModel.isExist(storyID: storyID) {
            
            bookModel = ReaderArchiver.unarchiver(folderName: storyID, fileName: READER_KEY_OBJECT) as? ReaderBookModel
            
        }else{
            
            bookModel = ReaderBookModel()
            
            bookModel.storyID = storyID
        }
        
        // 获取阅读记录
        bookModel.recordModel = ReaderReadRecordModel.model(storyID: storyID)
        
        return bookModel
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        storyID = aDecoder.decodeObject(forKey: "storyID") as? String
        
        storyName = aDecoder.decodeObject(forKey: "storyName") as? String
        
        coverURL = aDecoder.decodeObject(forKey: "cover") as? String
        
        writer = aDecoder.decodeObject(forKey: "writer") as? String
        
        externalBookCode = (aDecoder.decodeObject(forKey: "externalBookCode") as? NSNumber)?.intValue ?? 0
        
        totalChapterCount = (aDecoder.decodeObject(forKey: "totalChapterCount") as? NSNumber)?.intValue ?? 0
        
        storySourceType = ReaderBookSourceType(rawValue: (aDecoder.decodeObject(forKey: "storySourceType") as! NSNumber).intValue)
        
        chapterListModels = aDecoder.decodeObject(forKey: "chapterListModels") as? [ReaderChapterListItemModel]
        
        markModels = aDecoder.decodeObject(forKey: "markModels") as? [ReaderBookmarkModel]
        
        fullText = aDecoder.decodeObject(forKey: "fullText") as? String
        
        ranges = aDecoder.decodeObject(forKey: "ranges") as? [String: [String: NSRange]]
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "storyID")
        
        aCoder.encode(storyName, forKey: "storyName")
        
        aCoder.encode(coverURL, forKey: "cover")
        
        aCoder.encode(writer, forKey: "writer")
        
        aCoder.encode(NSNumber(value: externalBookCode), forKey: "externalBookCode")
        
        aCoder.encode(NSNumber(value: totalChapterCount), forKey: "totalChapterCount")
        
        aCoder.encode(NSNumber(value: storySourceType.rawValue), forKey: "storySourceType")
        
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
