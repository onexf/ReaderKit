//
//  ReaderChapterListItemModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/22.
//

import UIKit

/// 归档用的固定 ObjC 类名。Swift 类归档时写入「模块名.类名」，
/// 一旦模块名或 Swift 类名变化，旧归档就反序列化不出来（老用户进度与书签丢失）。
/// 用 @objc 固定为无模块前缀的名字后，归档格式与模块名、Swift 名解耦。
/// **该名字一经发布不可再改。**
@objc(ReaderChapterListItemModel)
open class ReaderChapterListItemModel: NSObject,NSCoding {
    
    /// 章节ID
    @objc open var id: NSNumber!

    /// 小说ID
    open var bookID: String!
    
    /// 章节名称
    open var name: String!
    
    /// 优先级 (章节排序，从0开始)
    open var priority: NSNumber!
    
    /// 是否需要解锁 (1=是需要解锁, 2=否不需要解锁)
    open var lock: Int = 1
    
    /// 是否已经解锁 (1=是已解锁, 2=否未解锁)
    open var alreadyLock: Int = 2
    
    /// 解锁价格（金币）
    open var price: Int = 0
    
    /// 所属小说是否为VIP专区内容（0-否 1-是），由小说详情传入
    open var isVipContent: Int = 0
    
    /// 章节是否锁定。
    ///
    /// 本版本不含会员 / 充值模块，付费墙已整体移除，全部章节免费可读，因此恒为 false。
    /// `lock` / `alreadyLock` / `price` / `isVipContent` 字段保留：它们仍由服务端下发并参与
    /// NSCoding 归档，删除会破坏已落盘缓存的兼容性。
    open var isLocked: Bool {
        return false
    }
    
    // MARK: -- NSCoding
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        bookID = aDecoder.decodeObject(forKey: "bookID") as? String
        
        id = aDecoder.decodeObject(forKey: "id") as? NSNumber
        
        name = aDecoder.decodeObject(forKey: "name") as? String
        
        priority = aDecoder.decodeObject(forKey: "priority") as? NSNumber
        
        lock = (aDecoder.decodeObject(forKey: "lock") as? NSNumber)?.intValue ?? 1
        
        alreadyLock = (aDecoder.decodeObject(forKey: "alreadyLock") as? NSNumber)?.intValue ?? 2
        
        price = (aDecoder.decodeObject(forKey: "price") as? NSNumber)?.intValue ?? 0
        
        isVipContent = (aDecoder.decodeObject(forKey: "isVipContent") as? NSNumber)?.intValue ?? 0
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(bookID, forKey: "bookID")
        
        aCoder.encode(id, forKey: "id")
        
        aCoder.encode(name, forKey: "name")
        
        aCoder.encode(priority, forKey: "priority")
        
        aCoder.encode(NSNumber(value: lock), forKey: "lock")
        
        aCoder.encode(NSNumber(value: alreadyLock), forKey: "alreadyLock")
        
        aCoder.encode(NSNumber(value: price), forKey: "price")
        
        aCoder.encode(NSNumber(value: isVipContent), forKey: "isVipContent")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
