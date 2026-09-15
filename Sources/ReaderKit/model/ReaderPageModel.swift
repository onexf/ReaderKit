//
//  ReaderPageModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/06.
//

import UIKit

/// 归档用的固定 ObjC 类名。Swift 类归档时写入「模块名.类名」，
/// 一旦模块名或 Swift 类名变化，旧归档就反序列化不出来（老用户进度与书签丢失）。
/// 用 @objc 固定为无模块前缀的名字后，归档格式与模块名、Swift 名解耦。
/// **该名字一经发布不可再改。**
@objc(ReaderPageModel)
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
    open var headTypeHeight: CGFloat! = 0
    
    /// 当前内容Size (目前主要是(滚动模式 || 长按模式)使用)
    open var contentSize: CGSize! = CGSize.zero
    
    /// 当前内容头部类型 (目前主要是滚动模式使用)
    open var headTypeIndex: NSNumber!
    
    /// 当前内容头部类型 (目前主要是滚动模式使用)
    open var headType: ReaderSheetHeaderType! {
        
        set{ headTypeIndex = NSNumber(value: newValue.rawValue) }
        
        get{ return ReaderSheetHeaderType(rawValue: headTypeIndex.intValue) }
    }
    
    /// 当前内容总高(cell 高度)
    open var cellHeight: CGFloat! {
        
        // 内容高度 + 头部高度
        return contentSize.height + headTypeHeight
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
        
        content = aDecoder.decodeObject(forKey: "content") as? NSAttributedString
        
        range = aDecoder.decodeObject(forKey: "range") as? NSRange
        
        page = aDecoder.decodeObject(forKey: "page") as? NSNumber
        
        headTypeHeight = aDecoder.decodeObject(forKey: "headTypeHeight") as? CGFloat
        
        contentSize = aDecoder.decodeObject(forKey: "contentSize") as? CGSize
        
        headTypeIndex = aDecoder.decodeObject(forKey: "headTypeIndex") as? NSNumber
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(content, forKey: "content")
        
        aCoder.encode(range, forKey: "range")
        
        aCoder.encode(page, forKey: "page")
        
        aCoder.encode(headTypeHeight, forKey: "headTypeHeight")
        
        aCoder.encode(contentSize, forKey: "contentSize")
        
        aCoder.encode(headTypeIndex, forKey: "headTypeIndex")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
