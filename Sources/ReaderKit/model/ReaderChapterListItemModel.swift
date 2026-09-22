//
//  ReaderChapterListItemModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/22.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 同理，属性改名时 `forKey:` 里的键名要保持原样（所以下面会看到名字对不上的成对写法）。
/// 键名跟着改的后果是已落盘的缓存解档拿到 nil，而这些字段是隐式解包可选 —— 访问即崩。
open class ReaderChapterListItemModel: NSObject, NSCoding {
    
    /// 章节ID
    open var id: NSNumber!

    /// 小说ID
    open var storyID: String!
    
    /// 章节名称
    open var name: String!
    
    /// 优先级 (章节排序，从0开始)
    open var priority: NSNumber!
    
    /// 是否需要解锁 (1=是需要解锁, 2=否不需要解锁)
    open var lock: Int = 1
    
    /// 是否已经解锁 (1=是已解锁, 2=否未解锁)
    open var unlockState: Int = 2
    
    /// 解锁价格（金币）
    open var price: Int = 0
    
    /// 所属小说是否为VIP专区内容（0-否 1-是），由小说详情传入
    open var premiumZoneFlag: Int = 0
    
    /// 章节是否锁定。
    ///
    /// 本版本不含会员 / 充值模块，付费墙已整体移除，全部章节免费可读，因此恒为 false。
    /// `lock` / `unlockState` / `price` / `premiumZoneFlag` 字段保留：它们仍由服务端下发并参与
    /// NSCoding 归档，删除会破坏已落盘缓存的兼容性。
    open var isLocked: Bool {
        return false
    }
    
    // MARK: -- NSCoding
    //
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        storyID = aDecoder.decodeObject(forKey: "storyID") as? String
        
        id = aDecoder.decodeObject(forKey: "id") as? NSNumber
        
        name = aDecoder.decodeObject(forKey: "name") as? String
        
        priority = aDecoder.decodeObject(forKey: "priority") as? NSNumber
        
        lock = (aDecoder.decodeObject(forKey: "lock") as? NSNumber)?.intValue ?? 1
        
        unlockState = (aDecoder.decodeObject(forKey: "alreadyLock") as? NSNumber)?.intValue ?? 2
        
        price = (aDecoder.decodeObject(forKey: "price") as? NSNumber)?.intValue ?? 0
        
        premiumZoneFlag = (aDecoder.decodeObject(forKey: "isVipContent") as? NSNumber)?.intValue ?? 0
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "storyID")
        
        aCoder.encode(id, forKey: "id")
        
        aCoder.encode(name, forKey: "name")
        
        aCoder.encode(priority, forKey: "priority")
        
        aCoder.encode(NSNumber(value: lock), forKey: "lock")
        
        aCoder.encode(NSNumber(value: unlockState), forKey: "alreadyLock")
        
        aCoder.encode(NSNumber(value: price), forKey: "price")
        
        aCoder.encode(NSNumber(value: premiumZoneFlag), forKey: "isVipContent")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
