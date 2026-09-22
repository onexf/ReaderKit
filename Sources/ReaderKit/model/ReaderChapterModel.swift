//
//  ReaderChapterModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/20.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 归档键名与属性名保持一致，改属性名就一起改键名。**前提是 `model(...)` 工厂里有
/// 「解档失败回落新实例」的兜底** —— 否则改键名会让 decode 得到 nil，而这些字段是
/// 隐式解包可选，访问即崩。改键名等于丢弃已落盘的缓存：正文能重新下载，
/// 阅读进度与书签不可恢复，所以只在没有正式用户的阶段才这么做。
open class ReaderChapterModel: NSObject, NSCoding {
    
    /// 小说ID
    open var storyID: String!
    
    /// 章节ID
    open var id: NSNumber!
    
    /// 上一章ID
    open var priorChapterID: NSNumber!
    
    /// 下一章ID
    open var followingChapterID: NSNumber!
    
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
    open var layoutPages: [ReaderPageModel]! = []
    
    
    // MARK: 快捷获取
    
    /// 当前章节是否为第一个章节
    open var isFirstChapter: Bool! { return (priorChapterID == READER_NO_MORE_CHAPTER) }
    
    /// 当前章节是否为最后一个章节
    open var isLastChapter: Bool! { return (followingChapterID == READER_NO_MORE_CHAPTER) }
    
    /// 完整章节名称
    open var fullName: String! { return ReaderTextRule.chapterHeading(name) }
    
    /// 完整富文本内容
    open var typesetContent: NSAttributedString!
    
    /// 分页总高 (上下滚动模式使用)
    open var pageTotalHeight: CGFloat {
        
        var pageTotalHeight: CGFloat = 0
        
        for pageModel in layoutPages {
            
            pageTotalHeight += (pageModel.contentSize.height + pageModel.headerInsetHeight)
        }
        
        return pageTotalHeight
    }
    
    
    // MARK: -- 更新字体
    
    /// 分页参数签名（用于判断是否需要重新分页）
    private var layoutFingerprint: String = ""
    
    /// 生成当前分页参数的签名字符串
    private func activePagingSignature() -> String {
        let configure = ReaderConfiguration.shared()
        let isEnglish = ReaderTextRule.isLatin(content ?? "")
        let font = configure.font(isTitle: false)
        let titleFont = configure.font(isTitle: true)
        let rect = READER_VIEW_RECT!
        // 把影响分页的所有参数拼成一个字符串。**格式本身没有语义**，只要「参数变了串就变」，
        // 所以随时可以改写 —— 改了等于让所有已归档章节重排一次。
        // 标题间距 / 段间距必须在串里：它们参与 CoreText 排版，漏了的话已归档章节
        // 反序列化后签名不变、不会重排，线上表现就是「改了间距没生效」。
        return [
            font.fontName, "\(font.pointSize)",
            titleFont.fontName, "\(titleFont.pointSize)",
            "lh\(configure.lineHeightPercent)",
            "sp\(configure.spacingType.rawValue)",
            "latin\(isEnglish)",
            "\(rect.width)x\(rect.height)",
            "ind\(Int(READER_FIRST_LINE_HEAD_INDENT))",
            "tg\(Int(READER_TITLE_BOTTOM_SPACING))",
            "pg\(Int(READER_PARAGRAPH_SPACING))",
        ].joined(separator: "|")
    }
    
    /// 更新字体
    open func reviseFont() {
        
        let newSignature = activePagingSignature()
        
        if layoutFingerprint != newSignature {
            
            layoutFingerprint = newSignature
            
            typesetContent = entireContentAttrString()
            
            // 不再显示书名页，直接从章节内容开始
            layoutPages = ReaderTypesetter.pageing(attrString: typesetContent, rect: CGRect(origin: CGPoint.zero, size: READER_VIEW_RECT.size), isFirstChapter: false)
            
            pageCount = NSNumber(value: layoutPages.count)
            
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
        guard page >= 0 && page < layoutPages.count else {
            return ""
        }
        return layoutPages[page].content.string
    }

    /// 获取指定页码富文本
    open func contentAttributedString(page: NSInteger) ->NSAttributedString {
        guard page >= 0 && page < layoutPages.count else {
            return NSAttributedString(string: "")
        }
        return layoutPages[page].showContent
    }
    
    /// 获取指定页开始坐标
    open func locationInitial(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < layoutPages.count else {
            return NSNumber(value: 0)
        }
        return NSNumber(value: layoutPages[page].range.location)
    }
    
    /// 获取指定页码末尾坐标
    open func locationFinal(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < layoutPages.count else {
            return NSNumber(value: 0)
        }
        let range = layoutPages[page].range!
        
        return NSNumber(value: range.location + range.length)
    }
    
    /// 获取指定页中间
    open func locationMiddle(page: NSInteger) ->NSNumber {
        guard page >= 0 && page < layoutPages.count else {
            return NSNumber(value: 0)
        }
        let range = layoutPages[page].range!
        
        return NSNumber(value: (range.location + (range.location + range.length) / 2))
    }
    
    /// 获取存在指定坐标的页码
    open func page(location: NSInteger) ->NSNumber {
        
        let count = layoutPages.count
        
        for i in 0..<count {
            
            let range = layoutPages[i].range!
            
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
        }
        
        // ⚠️ 解档失败必须回落成新实例。返回类型非可选，而本类字段是隐式解包可选 ——
        // 让 nil 流出去的后果是调用方访问 `name` / `content` 时崩。归档文件损坏、
        // 或归档键名随版本变过，都会走到这条路上。
        if chapterModel == nil {
            
            chapterModel = ReaderChapterModel()
            
            chapterModel.storyID = storyID
            
            chapterModel.id = chapterID
        }
        
        return chapterModel
    }
        
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        storyID = aDecoder.decodeObject(forKey: "bookKey") as? String
        
        id = aDecoder.decodeObject(forKey: "key") as? NSNumber
        
        priorChapterID = aDecoder.decodeObject(forKey: "priorChapterID") as? NSNumber
        
        followingChapterID = aDecoder.decodeObject(forKey: "followingChapterID") as? NSNumber
        
        name = aDecoder.decodeObject(forKey: "label") as? String
        
        priority = aDecoder.decodeObject(forKey: "sortWeight") as? NSNumber
        
        content = aDecoder.decodeObject(forKey: "body") as? String
        
        typesetContent = aDecoder.decodeObject(forKey: "typesetContent") as? NSAttributedString
        
        pageCount = aDecoder.decodeObject(forKey: "pageTally") as? NSNumber
        
        layoutPages = aDecoder.decodeObject(forKey: "layoutPages") as? [ReaderPageModel]
        
        layoutFingerprint = aDecoder.decodeObject(forKey: "layoutFingerprint") as? String ?? ""
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "bookKey")
        
        aCoder.encode(id, forKey: "key")
        
        aCoder.encode(priorChapterID, forKey: "priorChapterID")
        
        aCoder.encode(followingChapterID, forKey: "followingChapterID");
        
        aCoder.encode(name, forKey: "label")
        
        aCoder.encode(priority, forKey: "sortWeight")
        
        aCoder.encode(content, forKey: "body")
        
        aCoder.encode(typesetContent, forKey: "typesetContent")
        
        aCoder.encode(pageCount, forKey: "pageTally")
        
        aCoder.encode(layoutPages, forKey: "layoutPages")
        
        aCoder.encode(layoutFingerprint, forKey: "layoutFingerprint")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
