//
//  ReaderReadRecordModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/15.
//

import UIKit

/// 记录当前章节阅读到的坐标
nonisolated(unsafe) public var READER_RECORD_CURRENT_CHAPTER_LOCATION: NSNumber!

/// 归档用的固定 ObjC 类名。Swift 类归档时写入「模块名.类名」，
/// 一旦模块名或 Swift 类名变化，旧归档就反序列化不出来（老用户进度与书签丢失）。
/// 用 @objc 固定为无模块前缀的名字后，归档格式与模块名、Swift 名解耦。
/// **该名字一经发布不可再改。**
@objc(ReaderReadRecordModel)
open class ReaderReadRecordModel: NSObject, NSCoding {

    /// 小说ID
    open var bookID: String!
    
    /// 当前记录的阅读章节
    open var chapterModel: ReaderChapterModel!
    
    /// 阅读到的页码(上传阅读记录到服务器时传当前页面的 location 上去,从服务器拿回来 location 在转成页码。精准回到上次阅读位置)
    open var page: NSNumber! = NSNumber(value: 0)
    
    /// 滚动模式下，contentOffset.y 相对于当前 page cell 顶部的偏移（用于精确还原滚动位置）
    open var scrollOffsetInPage: CGFloat = 0
    
    
    // MARK: 快捷获取
    
    /// 当前记录分页模型
    open var pageModel: ReaderPageModel! { 
        guard let chapterModel = chapterModel,
              page.intValue >= 0,
              page.intValue < chapterModel.pageModels.count else {
            return nil
        }
        return chapterModel.pageModels[page.intValue]
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
        self.scrollOffsetInPage = 0
        
        if isSave { save() }
    }
    
    /// 修改阅读记录为指定章节位置
    open func modify(chapterID: NSNumber!, location: NSInteger, isSave: Bool = true) {
        
        if ReaderChapterModel.isExist(bookID: bookID, chapterID: chapterID) {
            
            chapterModel = ReaderChapterModel.model(bookID: bookID, chapterID: chapterID)
            
            // 书签精确定位:翻页模式下对该章临时分页,使书签所在段成为页首
            // 滚动模式保持常规分页,用页内偏移复用滚动控制器的定位恢复机制
            if ReaderConfiguration.shared().effectType != .scroll {
                chapterModel.adoptBookmarkPaging(at: location)
                page = chapterModel.page(location: location)
                scrollOffsetInPage = 0
            } else {
                page = chapterModel.page(location: location)
                scrollOffsetInPage = chapterModel.inPageOffsetY(forLocation: location)
            }
            
            if isSave { save() }
        }
    }
    
    /// 修改阅读记录为指定章节页码 (toPage == READER_LAST_PAGE 为当前章节最后一页)
    open func modify(chapterID: NSNumber!, toPage: NSInteger, isSave: Bool = true) {
        
        if ReaderChapterModel.isExist(bookID: bookID, chapterID: chapterID) {
            
            chapterModel = ReaderChapterModel.model(bookID: bookID, chapterID: chapterID)
            
            if (toPage == READER_LAST_PAGE) { finalPage()
                
            }else{ page = NSNumber(value: toPage) }
            
            // Reset scroll offset when jumping to a specific page
            scrollOffsetInPage = 0
            
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
        
        recordModel.bookID = bookID
        
        recordModel.chapterModel = chapterModel
        
        recordModel.page = page
        
        recordModel.scrollOffsetInPage = scrollOffsetInPage
        
        return recordModel
    }
    
    /// 保存记录
    open func save() {
        
        ReaderArchiver.archiver(folderName: bookID, fileName: READER_KEY_RECORD, object: self)
    }
    
    /// 是否存在阅读记录
    public class func isExist(_ bookID: String!) ->Bool {
        
        return ReaderArchiver.isExist(folderName: bookID, fileName: READER_KEY_RECORD)
    }
    
    
    // MARK: 构造
    
    /// 获取阅读记录对象,如果则创建对象返回
    @objc public class func model(bookID: String!) ->ReaderReadRecordModel {
        
        var recordModel: ReaderReadRecordModel!
        
        if ReaderReadRecordModel.isExist(bookID) {
            
            recordModel = ReaderArchiver.unarchiver(folderName: bookID, fileName: READER_KEY_RECORD) as? ReaderReadRecordModel
            
            // 不在此处调用 reviseFont()，避免不必要的重新分页导致 page 偏移
            // reviseFont() 会在 GetChapterModel / ReaderChapterModel.model() 中按需调用
            
        }else{
            
            recordModel = ReaderReadRecordModel()
            
            recordModel.bookID = bookID
        }
        
        return recordModel
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        bookID = aDecoder.decodeObject(forKey: "bookID") as? String
        
        chapterModel = aDecoder.decodeObject(forKey: "chapterModel") as? ReaderChapterModel
        
        page = aDecoder.decodeObject(forKey: "page") as? NSNumber
        
        scrollOffsetInPage = CGFloat(aDecoder.decodeDouble(forKey: "scrollOffsetInPage"))
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(bookID, forKey: "bookID")
        
        aCoder.encode(chapterModel, forKey: "chapterModel")
        
        aCoder.encode(page, forKey: "page")
        
        aCoder.encode(Double(scrollOffsetInPage), forKey: "scrollOffsetInPage")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
