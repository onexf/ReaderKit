//
//  ReaderBookmarkModel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/15.
//

import UIKit

/// 归档用的固定 ObjC 类名。Swift 类归档时写入「模块名.类名」，
/// 一旦模块名或 Swift 类名变化，旧归档就反序列化不出来（老用户进度与书签丢失）。
/// 用 @objc 固定为无模块前缀的名字后，归档格式与模块名、Swift 名解耦。
/// **该名字一经发布不可再改。**
@objc(ReaderBookmarkModel)
open class ReaderBookmarkModel: NSObject, NSCoding {

    // 以下字段原为隐式解包可选（`String!`），是从 Objective-C 移植时留下的写法：
    // 解档缺 key 时字段为 nil，之后任何访问都会崩溃，且编译器不提醒。
    // 改为非可选 + 默认值后，缺数据退化成空值而非崩溃，且使用点无需改动
    // （IUO 在使用时本就当非可选用）。

    /// 小说ID
    open var storyID: String = ""

    /// 章节ID
    open var chapterID: NSNumber = NSNumber(value: 0)

    /// 章节名称
    open var name: String = ""

    /// 内容
    open var content: String = ""

    /// 时间戳
    open var time: NSNumber = NSNumber(value: 0)

    /// 位置
    open var location: NSNumber = NSNumber(value: 0)
    
    /// 服务端书签ID(上报 /app/bookmark/add 成功后回填,nil 表示尚未同步到服务端;有值即代表已在服务端,是唯一的"已同步"判据)
    open var bookmarkId: NSNumber?
    
    // MARK: -- 构造
    
    public override init() {
        
        super.init()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        super.init()
        
        // 解档缺字段时退化为默认值，不再留下 nil 触发后续崩溃
        storyID = aDecoder.decodeObject(forKey: "storyID") as? String ?? ""

        chapterID = aDecoder.decodeObject(forKey: "chapterID") as? NSNumber ?? NSNumber(value: 0)

        name = aDecoder.decodeObject(forKey: "name") as? String ?? ""

        content = aDecoder.decodeObject(forKey: "content") as? String ?? ""

        time = aDecoder.decodeObject(forKey: "time") as? NSNumber ?? NSNumber(value: 0)

        location = aDecoder.decodeObject(forKey: "location") as? NSNumber ?? NSNumber(value: 0)
        
        bookmarkId = aDecoder.decodeObject(forKey: "bookmarkId") as? NSNumber
    }
    
    open func encode(with aCoder: NSCoder) {
        
        aCoder.encode(storyID, forKey: "storyID")
        
        aCoder.encode(chapterID, forKey: "chapterID")
        
        aCoder.encode(name, forKey: "name")
        
        aCoder.encode(content, forKey: "content")
        
        aCoder.encode(time, forKey: "time")
        
        aCoder.encode(location, forKey: "location")
        
        aCoder.encode(bookmarkId, forKey: "bookmarkId")
    }
    
    open override func setValue(_ value: Any?, forUndefinedKey key: String) { }
    
    // MARK: -- 上报摘要
    
    /// 上报服务端的书签文字摘要最大长度(服务端 contentSnippet 字段上限 200)。
    /// 需覆盖书签列表 cell 的 2 行展示(excerptLabel.numberOfLines = 2):
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
