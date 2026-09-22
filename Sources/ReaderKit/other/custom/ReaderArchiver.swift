//
//  ReaderArchiver.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/09.
//

import UIKit

open class ReaderArchiver: NSObject {
    
    /// 归档里写的类名 ↔ Swift 类。
    ///
    /// ## 为什么要有这张表
    ///
    /// Swift 类归档时写入的类名默认是「模块名.Swift 类名」，于是**改模块名或改类名都会让
    /// 已有归档读不出来** —— 而且是静默的：解档返回 nil，上层当成「本地没有缓存」，
    /// 用户的阅读进度、书签、已下载章节凭空消失，没有任何错误。
    ///
    /// 把磁盘上的名字显式钉在这里，Swift 侧就可以自由改名、库也可以被折进别的模块。
    ///
    /// ## 为什么不用 `@objc(类名)`
    ///
    /// 那样同样能固定名字，但代价是把这 6 个类暴露进 ObjC 运行时 —— 本库没有任何
    /// Objective-C 代码，那份暴露纯属白付；而且归档格式会散在 6 个文件的类声明上，
    /// 而它本该是**存储层的事**。收在这一张表里，改名字只需要看这一处。
    ///
    /// ## 维护规则
    ///
    /// **表里的字符串一经发布不可再改。** 新增归档类型要在这里登记 —— 漏登记不报错，
    /// 写盘时会退回「模块名.类名」，于是下次改模块名它就悄悄失联。
    private static let archivedClassNames: [(AnyClass, String)] = [
        (ReaderBookModel.self, "ReaderBookModel"),
        (ReaderChapterModel.self, "ReaderChapterModel"),
        (ReaderChapterListItemModel.self, "ReaderChapterListItemModel"),
        (ReaderReadRecordModel.self, "ReaderReadRecordModel"),
        (ReaderBookmarkModel.self, "ReaderBookmarkModel"),
        (ReaderPageModel.self, "ReaderPageModel"),
    ]

    /// 归档文件
    public class func archiver(folderName: String!, fileName: String!, object: AnyObject!) {
        
        var path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)"
        
        guard creat_file(path: path) else { return } // 文件夹创建失败且不存在
        
        path += "/\(fileName!)"
        
        // 不用 `NSKeyedArchiver.archiveRootObject(_:toFile:)`：那条便捷方法不给机会调
        // `setClassName(_:for:)`，写下去的就是「模块名.类名」。
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        for (cls, name) in archivedClassNames { archiver.setClassName(name, for: cls) }
        archiver.encode(object, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        
        try? archiver.encodedData.write(to: URL(fileURLWithPath: path))
    }
    
    /// 解档文件
    public class func unarchiver(folderName: String!, fileName: String!) ->AnyObject? {
        
        let path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)/\(fileName!)"
        
        // 检查文件是否存在
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            for (cls, name) in archivedClassNames { unarchiver.setClass(cls, forClassName: name) }

            let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            
            return result as AnyObject?
        } catch {
            // log("❌ 解档失败: \(error)")
            return nil
        }
    }

    /// 删除归档文件
    public class func remove(folderName: String!, fileName: String? = nil) ->Bool {
        
        var path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)"
        
        if fileName != nil && !fileName!.isEmpty { path += "/\(fileName!)" }
        
        do{
            try FileManager.default.removeItem(atPath: path)
            
            return true
            
        }catch{ }
        
        return false
    }
    
    /// 清空归档文件
    public class func clear() ->Bool {
        
        let path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)"
        
        do{
            
            try FileManager.default.removeItem(atPath: path)
            
            return true
            
        }catch{ }
        
        return false
    }
    
    /// 是否存在归档文件
    public class func isExist(folderName: String!, fileName: String? = nil) ->Bool {
        
        var path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)"
        
        if fileName != nil && !fileName!.isEmpty { path += "/\(fileName!)" }
        
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// 创建文件夹,如果存在则不创建
    private class func creat_file(path: String) ->Bool {
        
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: path) { return true }
        
        do{
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            
            return true
            
        }catch{ }
        
        return false
    }
}
