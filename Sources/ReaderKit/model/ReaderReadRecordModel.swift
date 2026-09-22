//
//  ReaderReadRecordModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/15.
//

import UIKit

/// 记录当前章节阅读到的坐标
nonisolated(unsafe) public var READER_RECORD_CURRENT_CHAPTER_LOCATION: NSNumber!

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 同理，属性改名时 `forKey:` 里的键名要保持原样（所以下面会看到名字对不上的成对写法）。
/// 键名跟着改的后果是已落盘的缓存解档拿到 nil，而这些字段是隐式解包可选 —— 访问即崩。
open class ReaderReadRecordModel: NSObject, NSCoding {

    /// 小说ID
    open var storyID: String!
    
    /// 当前记录的阅读章节
    open var chapterModel: ReaderChapterModel!
    
    /// 阅读到的页码(上传阅读记录到服务器时传当前页面的 location 上去,从服务器拿回来 location 在转成页码。精准回到上次阅读位置)
    open var page: NSNumber! = NSNumber(value: 0)
    
    /// 滚动模式下，contentOffset.y 相对于当前 page cell 顶部的偏移（用于精确还原滚动位置）
    open var pageScrollAnchor: CGFloat = 0
    
    
    // MARK: 快捷获取
    
    /// 当前记录分页模型
    open var pageModel: ReaderPageModel! { 
        guard let chapterModel = chapterModel,
              page.intValue >= 0,
              page.intValue < chapterModel.layoutPages.count else {
            return nil
        }
        return chapterModel.layoutPages[page.intValue]
    }
    
    /// 当前记录起始坐标
    open var locationFirst: NSNumber! { 
        guard let chapterModel = chapterModel else { return NSNumber(value: 0) }
        return chapterModel.locationInitial(page: page.intValue)
    }
    
    /// 当前记录末尾坐标
    open var locationLast: NSNumber! { 
        guard let chapterModel = chapterModel else { return NSNumber(value: 0) }
        return chapterModel.locationFinal(page: page.intValue)
    }
    
    /// 当前记录是否为第一个章节
    open var isFirstChapter: Bool! { 
        guard let chapterModel = chapterModel else { return true }
        return chapterModel.isFirstChapter
    }
    
    /// 当前记录是否为最后一个章节
    open var isLastChapter: Bool! { 
        guard let chapterModel = chapterModel else { return true }
        return chapterModel.isLastChapter
    }
    
    /// 当前记录是否为第一页
    open var isFirstPage: Bool! { return (page.intValue == 0) }
    
    /// 当前记录是否为最后一页
    open var isLastPage: Bool! { 
        guard let chapterModel = chapterModel else { return true }
        return (page.intValue == (chapterModel.pageCount.intValue - 1))
    }
    
    /// 当前记录页码字符串
    open var contentString: String! { 
        guard let chapterModel = chapterModel else { return "" }
        return chapterModel.contentString(page: page.intValue)
    }
    
    /// 当前记录页码富文本
    open var contentAttributedString: NSAttributedString! { 
        guard let chapterModel = chapterModel else { return NSAttributedString(string: "") }
        return chapterModel.contentAttributedString(page: page.intValue)
    }
    
    /// 当前记录切到上一页
    open func priorPage() { page = NSNumber(value: max(page.intValue - 1, 0)) }
    
    /// 当前记录切到下一页
    open func followingPage() { page = NSNumber(value: min(page.intValue + 1, chapterModel.pageCount.intValue - 1)) }
    
    /// 当前记录切到第一页
    open func initialPage() { page = NSNumber(value: 0) }
    
    /// 当前记录切到最后一页
    open func finalPage() { page = NSNumber(value: chapterModel.pageCount.intValue - 1) }
    
    
    // MARK: 辅助
    
    /// 修改阅读记录为指定章节位置
    open func modify(chapterModel: ReaderChapterModel!, page: NSInteger, isSave: Bool = true) {
        
        self.chapterModel = chapterModel
        
        self.page = NSNumber(value: page)
        
        // Reset scroll offset when explicitly setting page position
        self.pageScrollAnchor = 0
        
        if isSave { save() }
    }
    
    /// 修改阅读记录为指定章节位置
    ///
    /// - Parameter anchorsParagraphToPageTop: 是否为本次定位重排分页，使目标位置所在段落成为页首。
    ///
    ///   **书签跳转要（默认 `true`），按位置对齐正文不要（传 `false`）。**
    ///
    ///   `adoptBookmarkPaging(at:)` 会把整章在目标段落的段首处切成两段、分别分页再拼接，
    ///   于是前半段的最后一页是个残页（文字到哪断到哪、下方大片空白），其后所有页边界整体错位。
    ///   书签需要这个效果（书签段落必须落在页首），代价可以接受。
    ///
    ///   但朗读对齐只需要「落到含该句的那一页」，句子位置由高亮标示，重排分页纯属副作用：
    ///   - 目标位置在正文第一段时，切点落在标题后的换行处，前半段只剩标题一行 ——
    ///     单独分页出来就是一页**只有标题、正文空白**
    ///   - 每次对齐的位置不同，于是每次都按新切点重排一次，表现为「排版随朗读继续不断变化」
    ///   - 重排是内存态（`isSave: false` 时不落盘），翻走再翻回来会从归档重读出常规分页，
    ///     所以现象看起来还会自行恢复，很容易被误判成渲染时机问题
    ///
    ///   该缺陷只在左右翻页模式暴露（滚动模式走下面的分支，从不重排），
    ///   且只在「朗读位置不在章首」时暴露 —— 前台跨章对齐传的是 `location: 0`，
    ///   `adoptBookmarkPaging` 内部 `guard splitAt > 0` 直接早退，看不出差别。
    ///   锁屏期间跨章不导航、回前台才按当前朗读句补齐，传的位置在章节深处，于是才发作。
    open func modify(chapterID: NSNumber!, location: NSInteger, isSave: Bool = true,
                     anchorsParagraphToPageTop: Bool = true) {
        
        if ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID) {
            
            chapterModel = ReaderChapterModel.model(storyID: storyID, chapterID: chapterID)
            
            // 书签精确定位:翻页模式下对该章临时分页,使书签所在段成为页首
            // 滚动模式保持常规分页,用页内偏移复用滚动控制器的定位恢复机制
            if ReaderConfiguration.shared().effectType != .scroll {
                
                if anchorsParagraphToPageTop {
                    
                    chapterModel.adoptBookmarkPaging(at: location)
                    
                } else {
                    
                    // 不重排，但仍要确保常规分页已按当前排版构建。
                    // `reviseFont()` 受分页签名短路，签名一致时是空操作；
                    // 不调的话，若字号/行距在此之前变过，`page(location:)`
                    // 会落在旧分页上（`adoptBookmarkPaging` 内部本来也先调了它）。
                    chapterModel.reviseFont()
                }
                
                page = chapterModel.page(location: location)
                pageScrollAnchor = 0
            } else {
                page = chapterModel.page(location: location)
                pageScrollAnchor = chapterModel.inPageOffsetY(forLocation: location)
            }
            
            if isSave { save() }
        }
    }
    
    /// 修改阅读记录为指定章节页码 (toPage == READER_LAST_PAGE 为当前章节最后一页)
    open func modify(chapterID: NSNumber!, toPage: NSInteger, isSave: Bool = true) {
        
        if ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID) {
            
            chapterModel = ReaderChapterModel.model(storyID: storyID, chapterID: chapterID)
            
            if (toPage == READER_LAST_PAGE) { finalPage()
                
            }else{ page = NSNumber(value: toPage) }
            
            // Reset scroll offset when jumping to a specific page
            pageScrollAnchor = 0
            
            if isSave { save() }
        }
    }
    
    /// 更新字体
    open func reviseFont(isSave: Bool = true) {
        
        if chapterModel != nil {
            
            chapterModel.reviseFont()
            
            page = chapterModel.page(location: READER_RECORD_CURRENT_CHAPTER_LOCATION.intValue)
            
            if isSave { save() }
        }
    }
    
    /// 拷贝阅读记录
    open func duplicateModel() ->ReaderReadRecordModel {
        
        let recordModel = ReaderReadRecordModel()
        
        recordModel.storyID = storyID
        
        recordModel.chapterModel = chapterModel
        
        recordModel.page = page
        
        recordModel.pageScrollAnchor = pageScrollAnchor
        
        return recordModel
    }
    
    /// 保存记录
    open func save() {
        
        ReaderArchiver.archiver(folderName: storyID, fileName: READER_KEY_RECORD, object: self)
    }
    
    /// 是否存在阅读记录
    public class func isExist(_ storyID: String!) ->Bool {
        
        return ReaderArchiver.isExist(folderName: storyID, fileName: READER_KEY_RECORD)
    }
    
    
    // MARK: 构造
    
    /// 获取阅读记录对象,如果则创建对象返回
    public class func model(storyID: String!) ->ReaderReadRecordModel {
        
        var recordModel: ReaderReadRecordModel!
        
        if ReaderReadRecordModel.isExist(storyID) {
            
            recordModel = ReaderArchiver.unarchiver(folderName: storyID, fileName: READER_KEY_RECORD) as? ReaderReadRecordModel
            
            // 不在此处调用 reviseFont()，避免不必要的重新分页导致 page 偏移
            // reviseFont() 会在 GetChapterModel / ReaderChapterModel.model() 中按需调用
            
        }else{
            
            recordModel = ReaderReadRecordModel()
            
            recordModel.storyID = storyID
        }
        
        return recordModel
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        storyID = aDecoder.decodeObject(forKey: "storyID") as? String
        
        chapterModel = aDecoder.decodeObject(forKey: "chapterModel") as? ReaderChapterModel
        
        page = aDecoder.decodeObject(forKey: "page") as? NSNumber
        
        pageScrollAnchor = CGFloat(aDecoder.decodeDouble(forKey: "scrollOffsetInPage"))
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "storyID")
        
        aCoder.encode(chapterModel, forKey: "chapterModel")
        
        aCoder.encode(page, forKey: "page")
        
        aCoder.encode(Double(pageScrollAnchor), forKey: "scrollOffsetInPage")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
