//
//  ReaderChapterModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/20.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
open class ReaderChapterModel: NSObject, NSCoding {
    
    /// 小说ID
    open var storyID: String!
    
    /// 章节ID
    open var id: NSNumber!
    
    /// 上一章ID
    open var previousChapterID: NSNumber!
    
    /// 下一章ID
    open var nextChapterID: NSNumber!
    
    /// 章节名称
    open var name: String!
    
    /// 内容
    /// 此处 content 是经过排版好且双空格开头的内容。
    /// 如果是网络数据需要确认是否处理好了,也就是在网络章节数据拿到之后, 使用排版接口进行排版并在开头加上双空格。(例如: READER_PH_SPACE + 排版好的content )
    /// 排版内容搜索 contentTypesetting 方法
    open var content: String!
    
    /// 优先级 (一般章节段落都带有排序的优先级 从0开始)
    open var priority: NSNumber!
    
    /// 本章有多少页
    open var pageCount: NSNumber! = NSNumber(value: 0)
    
    /// 分页数据
    open var pageModels: [ReaderPageModel]! = []
    
    
    // MARK: 快捷获取
    
    /// 当前章节是否为第一个章节
    open var isFirstChapter: Bool! { return (previousChapterID == READER_NO_MORE_CHAPTER) }
    
    /// 当前章节是否为最后一个章节
    open var isLastChapter: Bool! { return (nextChapterID == READER_NO_MORE_CHAPTER) }
    
    /// 完整章节名称
    open var fullName: String! { return ReaderTextRule.chapterHeading(name) }
    
    /// 完整富文本内容
    open var fullContent: NSAttributedString!
    
    /// 分页总高 (上下滚动模式使用)
    open var pageTotalHeight: CGFloat {
        
        var pageTotalHeight: CGFloat = 0
        
        for pageModel in pageModels {
            
            pageTotalHeight += (pageModel.contentSize.height + pageModel.headTypeHeight)
        }
        
        return pageTotalHeight
    }
    
    
    // MARK: -- 更新字体
    
    /// 分页参数签名（用于判断是否需要重新分页）
    private var pagingSignature: String = ""
    
    /// 生成当前分页参数的签名字符串
    private func activePagingSignature() -> String {
        let configure = ReaderConfiguration.shared()
        let isEnglish = ReaderTextRule.isLatin(content ?? "")
        let font = configure.font(isTitle: false)
        let titleFont = configure.font(isTitle: true)
        let rect = READER_VIEW_RECT!
        // 将影响分页的所有参数拼成一个字符串
        // titleGap / paraGap 必须在签名里：它们参与 CoreText 排版，改了却不进签名的话，
        // 已归档章节反序列化后签名不变、不会重排，线上表现就是「改了间距没生效」
        return "\(font.fontName)_\(font.pointSize)_\(titleFont.fontName)_\(titleFont.pointSize)_\(configure.lineHeightPercent)_\(configure.spacingType.rawValue)_\(isEnglish)_\(rect.width)_\(rect.height)_leftAlign_indent\(Int(READER_FIRST_LINE_HEAD_INDENT))_titleGap\(Int(READER_TITLE_BOTTOM_SPACING))_paraGap\(Int(READER_PARAGRAPH_SPACING))"
    }
    
    /// 更新字体
    open func reviseFont() {
        
        let newSignature = activePagingSignature()
        
        if pagingSignature != newSignature {
            
            pagingSignature = newSignature
            
            fullContent = entireContentAttrString()
            
            // 不再显示书名页，直接从章节内容开始
            pageModels = ReaderTypesetter.pageing(attrString: fullContent, rect: CGRect(origin: CGPoint.zero, size: READER_VIEW_RECT.size), isFirstChapter: false)
            
            pageCount = NSNumber(value: pageModels.count)
            
            save()
        }
    }
    
    /// 完整内容排版
    private func entireContentAttrString() ->NSMutableAttributedString {
        
        let isEnglish = ReaderTextRule.isLatin(content ?? "")
        
        let titleString = NSMutableAttributedString(string: fullName, attributes: ReaderConfiguration.shared().attributes(isTitle: true, isEnglish: isEnglish))
        
        // 去掉段首全角空格缩进，首行缩进统一由 firstLineHeadIndent 控制
        var displayContent = content ?? ""
        displayContent = displayContent.replacingOccurrences(of: "\n　　", with: "\n")
        if displayContent.hasPrefix("　　") {
            displayContent = String(displayContent.dropFirst(2))
        }
        
        let contentString = NSMutableAttributedString(string: displayContent, attributes: ReaderConfiguration.shared().attributes(isTitle: false, isEnglish: isEnglish))
        
        titleString.append(contentString)
        
        return titleString
    }
    
    // MARK: 辅助功能
    
    /// 获取指定页码字符串
    open func contentString(page: NSInteger) ->String {
        guard page >= 0 && page < pageModels.count else {
            return ""
        }
        return pageModels[page].content.string
    }

    /// 获取指定页码富文本
    open func contentAttributedString(page: NSInteger) ->NSAttributedString {
        guard page >= 0 && page < pageModels.count else {
            return NSAttributedString(string: "")
        }
        return pageModels[page].showContent
    }
    
    /// 获取指定页开始坐标
    open func locationInitial(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < pageModels.count else {
            return NSNumber(value: 0)
        }
        return NSNumber(value: pageModels[page].range.location)
    }
    
    /// 获取指定页码末尾坐标
    open func locationFinal(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < pageModels.count else {
            return NSNumber(value: 0)
        }
        let range = pageModels[page].range!
        
        return NSNumber(value: range.location + range.length)
    }
    
    /// 获取指定页中间
    open func locationMiddle(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < pageModels.count else {
            return NSNumber(value: 0)
        }
        let range = pageModels[page].range!
        
        return NSNumber(value: (range.location + (range.location + range.length) / 2))
    }
    
    /// 获取存在指定坐标的页码
    open func page(location: NSInteger) ->NSNumber {
        
        let count = pageModels.count
        
        for i in 0..<count {
            
            let range = pageModels[i].range!
            
            if location < (range.location + range.length) {
                
                return NSNumber(value: i)
            }
        }
        
        return NSNumber(value: 0)
    }
    
    /// 保存
    open func save() { ReaderArchiver.archiver(folderName: storyID, fileName: id.stringValue, object: self) }
    
    /// 是否存在章节内容
    public class func isExist(storyID: String!, chapterID: NSNumber!) ->Bool {
        return ReaderArchiver.isExist(folderName: storyID, fileName: chapterID.stringValue)
    }
    
    // MARK: 构造
    
    /// 获取章节对象,如果则创建对象返回
    public class func model(storyID: String!, chapterID: NSNumber!, isUpdateFont: Bool = true) ->ReaderChapterModel {
        
        var chapterModel: ReaderChapterModel!
        
        if ReaderChapterModel.isExist(storyID: storyID, chapterID: chapterID) {
            
            chapterModel = ReaderArchiver.unarchiver(folderName: storyID, fileName: chapterID.stringValue) as? ReaderChapterModel
            
            if isUpdateFont { chapterModel?.reviseFont() }
            
        }else{
            
            chapterModel = ReaderChapterModel()
            
            chapterModel.storyID = storyID
            
            chapterModel.id = chapterID
        }
        
        return chapterModel
    }
        
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        storyID = aDecoder.decodeObject(forKey: "storyID") as? String
        
        id = aDecoder.decodeObject(forKey: "id") as? NSNumber
        
        previousChapterID = aDecoder.decodeObject(forKey: "previousChapterID") as? NSNumber
        
        nextChapterID = aDecoder.decodeObject(forKey: "nextChapterID") as? NSNumber
        
        name = aDecoder.decodeObject(forKey: "name") as? String
        
        priority = aDecoder.decodeObject(forKey: "priority") as? NSNumber
        
        content = aDecoder.decodeObject(forKey: "content") as? String
        
        fullContent = aDecoder.decodeObject(forKey: "fullContent") as? NSAttributedString
        
        pageCount = aDecoder.decodeObject(forKey: "pageCount") as? NSNumber
        
        pageModels = aDecoder.decodeObject(forKey: "pageModels") as? [ReaderPageModel]
        
        pagingSignature = aDecoder.decodeObject(forKey: "pagingSignature") as? String ?? ""
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "storyID")
        
        aCoder.encode(id, forKey: "id")
        
        aCoder.encode(previousChapterID, forKey: "previousChapterID")
        
        aCoder.encode(nextChapterID, forKey: "nextChapterID");
        
        aCoder.encode(name, forKey: "name")
        
        aCoder.encode(priority, forKey: "priority")
        
        aCoder.encode(content, forKey: "content")
        
        aCoder.encode(fullContent, forKey: "fullContent")
        
        aCoder.encode(pageCount, forKey: "pageCount")
        
        aCoder.encode(pageModels, forKey: "pageModels")
        
        aCoder.encode(pagingSignature, forKey: "pagingSignature")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
