//
//  ReaderBookmarkModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/15.
//

import UIKit

/// ⚠️ 本类参与归档，磁盘上的类名登记在 `ReaderArchiver.archivedClassNames`。
/// 改 Swift 类名不影响归档，但**不要改那张表里的字符串**。
///
/// 归档键名与属性名保持一致，改属性名就一起改键名。**前提是 `model(...)` 工厂里有
/// 「解档失败回落新实例」的兜底** —— 否则改键名会让 decode 得到 nil，而这些字段是
/// 隐式解包可选，访问即崩。改键名等于丢弃已落盘的缓存：正文能重新下载，
/// 阅读进度与书签不可恢复，所以只在没有正式用户的阶段才这么做。
open class ReaderBookmarkModel: NSObject, NSCoding {

    // 以下字段原为隐式解包可选（`String!`），是从 Objective-C 移植时留下的写法：
    // 解档缺 key 时字段为 nil，之后任何访问都会崩溃，且编译器不提醒。
    // 改为非可选 + 默认值后，缺数据退化成空值而非崩溃，且使用点无需改动
    // （IUO 在使用时本就当非可选用）。

    /// 小说ID
    open var storyID: String = ""

    /// 章节ID
    open var chapterKey: NSNumber = NSNumber(value: 0)

    /// 章节名称
    open var name: String = ""

    /// 内容
    open var content: String = ""

    /// 时间戳
    open var time: NSNumber = NSNumber(value: 0)

    /// 位置
    open var location: NSNumber = NSNumber(value: 0)
    
    /// 服务端书签ID(上报 /app/bookmark/add 成功后回填,nil 表示尚未同步到服务端;有值即代表已在服务端,是唯一的"已同步"判据)
    open var remoteMarkID: NSNumber?
    
    // MARK: -- 构造
    
    public override init() {
        
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        // 解档缺字段时退化为默认值，不再留下 nil 触发后续崩溃
        storyID = aDecoder.decodeObject(forKey: "bookKey") as? String ?? ""

        chapterKey = aDecoder.decodeObject(forKey: "chapterKey") as? NSNumber ?? NSNumber(value: 0)

        name = aDecoder.decodeObject(forKey: "label") as? String ?? ""

        content = aDecoder.decodeObject(forKey: "body") as? String ?? ""

        time = aDecoder.decodeObject(forKey: "stampedAt") as? NSNumber ?? NSNumber(value: 0)

        location = aDecoder.decodeObject(forKey: "anchorOffset") as? NSNumber ?? NSNumber(value: 0)
        
        remoteMarkID = aDecoder.decodeObject(forKey: "remoteMarkID") as? NSNumber
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "bookKey")
        
        aCoder.encode(chapterKey, forKey: "chapterKey")
        
        aCoder.encode(name, forKey: "label")
        
        aCoder.encode(content, forKey: "body")
        
        aCoder.encode(time, forKey: "stampedAt")
        
        aCoder.encode(location, forKey: "anchorOffset")
        
        aCoder.encode(remoteMarkID, forKey: "remoteMarkID")
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
    
    // MARK: -- 上报摘要
    
    /// 上报服务端的书签文字摘要最大长度(服务端 contentSnippet 字段上限 200)。
    /// 需覆盖书签列表 cell 的 2 行展示(snippetLabel.numberOfLines = 2):
    /// 重装/跨设备后若本地无该章正文缓存,只能用服务端 contentSnippet 还原展示,
    /// 摘要够长才能让 cell 截取的 2 行与添加时一致(50 字仅够 1 行多,会比本地短)。
    public static let snippetMaxLength = 200
    
    /// 生成上报用的书签文字摘要:去首尾空白后截取前 snippetMaxLength 字。
    /// add(单条) 与 batchAdd(批量) 统一调用此方法,避免两处截取长度不一致。
    public static func snippet(from content: String?) -> String? {
        guard let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.count <= snippetMaxLength ? trimmed : String(trimmed.prefix(snippetMaxLength))
    }
}
