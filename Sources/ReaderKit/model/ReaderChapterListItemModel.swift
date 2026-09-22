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
/// 归档键名与属性名保持一致，改属性名就一起改键名。**前提是 `model(...)` 工厂里有
/// 「解档失败回落新实例」的兜底** —— 否则改键名会让 decode 得到 nil，而这些字段是
/// 隐式解包可选，访问即崩。改键名等于丢弃已落盘的缓存：正文能重新下载，
/// 阅读进度与书签不可恢复，所以只在没有正式用户的阶段才这么做。
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
        
        storyID = aDecoder.decodeObject(forKey: "bookKey") as? String
        
        id = aDecoder.decodeObject(forKey: "key") as? NSNumber
        
        name = aDecoder.decodeObject(forKey: "label") as? String
        
        priority = aDecoder.decodeObject(forKey: "sortWeight") as? NSNumber
        
        lock = (aDecoder.decodeObject(forKey: "gateFlag") as? NSNumber)?.intValue ?? 1
        
        unlockState = (aDecoder.decodeObject(forKey: "unlockState") as? NSNumber)?.intValue ?? 2
        
        price = (aDecoder.decodeObject(forKey: "unlockCost") as? NSNumber)?.intValue ?? 0
        
        premiumZoneFlag = (aDecoder.decodeObject(forKey: "premiumZoneFlag") as? NSNumber)?.intValue ?? 0
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "bookKey")
        
        aCoder.encode(id, forKey: "key")
        
        aCoder.encode(name, forKey: "label")
        
        aCoder.encode(priority, forKey: "sortWeight")
        
        aCoder.encode(NSNumber(value: lock), forKey: "gateFlag")
        
        aCoder.encode(NSNumber(value: unlockState), forKey: "unlockState")
        
        aCoder.encode(NSNumber(value: price), forKey: "unlockCost")
        
        aCoder.encode(NSNumber(value: premiumZoneFlag), forKey: "premiumZoneFlag")
    }
    
    public init(_ dict: Any? = nil) {
        
        super.init()
        
        if dict != nil { setValuesForKeys(dict as! [String : Any]) }
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
}
