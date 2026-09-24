//
//  ReaderPageModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/06.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 归档键名与属性名保持一致，改属性名就一起改键名。**前提是 `model(...)` 工厂里有
/// 「解档失败回落新实例」的兜底** —— 否则改键名会让 decode 得到 nil，而这些字段是
/// 隐式解包可选，访问即崩。改键名等于丢弃已落盘的缓存：正文能重新下载，
/// 阅读进度与书签不可恢复，所以只在没有正式用户的阶段才这么做。
open class ReaderPageModel: NSObject, NSCoding {

    // MARK: 常用属性
    
    /// 当前页内容
    open var content: NSAttributedString!
    
    /// 当前页范围
    open var range: NSRange!
    
    /// 当前页序号
    open var page: NSNumber!
    
    
    // MARK: 滚动模式使用
    
    /// 根据开头类型返回开头高度 (目前主要是滚动模式使用)
    open var headerInsetHeight: CGFloat! = 0
    
    /// 当前内容Size (目前主要是(滚动模式 || 长按模式)使用)
    open var contentSize: CGSize! = CGSize.zero
    
    /// 当前内容头部类型 (目前主要是滚动模式使用)
    open var headerKindRaw: NSNumber!
    
    /// 当前内容头部类型 (目前主要是滚动模式使用)
    open var headerKind: ReaderSheetHeaderType! {
        
        set{ headerKindRaw = NSNumber(value: newValue.rawValue) }
        
        get{ return ReaderSheetHeaderType(rawValue: headerKindRaw.intValue) }
    }
    
    /// 当前内容总高(cell 高度)
    open var cellHeight: CGFloat! {
        
        // 内容高度 + 头部高度
        return contentSize.height + headerInsetHeight
    }
    
    
    // MARK: 快捷获取
    
    /// 书籍首页
    open var isHomePage: Bool { return range.location == READER_BOOK_HOME_PAGE }
    
    /// 获取显示内容(考虑可能会变换字体颜色的情况)
    open var showContent: NSAttributedString! {
        
        let textColor = ReaderConfiguration.shared().textColor!
        let tempShowContent = NSMutableAttributedString(attributedString: content)
        tempShowContent.addAttributes([.foregroundColor : textColor], range: NSMakeRange(0, content.length))
        return tempShowContent
    }
    
    // MARK: -- NSCoding
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        content = aDecoder.decodeObject(forKey: "body") as? NSAttributedString
        
        range = aDecoder.decodeObject(forKey: "span") as? NSRange
        
        page = aDecoder.decodeObject(forKey: "pageIndex") as? NSNumber
        
        headerInsetHeight = aDecoder.decodeObject(forKey: "headerInsetHeight") as? CGFloat
        
        contentSize = aDecoder.decodeObject(forKey: "renderedSize") as? CGSize
        
        headerKindRaw = aDecoder.decodeObject(forKey: "headerKindRaw") as? NSNumber
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(content, forKey: "body")
        
        aCoder.encode(range, forKey: "span")
        
        aCoder.encode(page, forKey: "pageIndex")
        
        aCoder.encode(headerInsetHeight, forKey: "headerInsetHeight")
        
        aCoder.encode(contentSize, forKey: "renderedSize")
        
        aCoder.encode(headerKindRaw, forKey: "headerKindRaw")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
