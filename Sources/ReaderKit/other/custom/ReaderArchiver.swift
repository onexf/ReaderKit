//
//  ReaderArchiver.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/09.
//

import UIKit

open class ReaderArchiver: NSObject {
    
    /// 归档文件
    public class func archiver(folderName: String!, fileName: String!, object: AnyObject!) {
        
        var path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)"
        
        if creat_file(path: path) { // 创建文件夹成功或者文件夹存在
            
            path += "/\(fileName!)"
            
            NSKeyedArchiver.archiveRootObject(object, toFile: path)
        }
    }
    
    /// 解档文件
    public class func unarchiver(folderName: String!, fileName: String!) ->AnyObject? {
        
        let path = READER_DOCUMENT_DIRECTORY_PATH + "/\(READER_FOLDER_NAME)/\(folderName!)/\(fileName!)"
        
        // 检查文件是否存在
        guard let data = NSData(contentsOfFile: path) else {
            return nil
        }
        
        do {
            let unarchiver = NSKeyedUnarchiver(forReadingWith: data as Data)
            registerLegacyClassNames(on: unarchiver)

            let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            
            return result as AnyObject?
        } catch {
            // log("❌ 解档失败: \(error)")
            return nil
        }
    }
    
    /// 归档类名不再需要历史映射。
    ///
    /// Swift 类归档写入的类名默认是「模块名.Swift 类名」，模块名或类名一变旧归档就读不出来。
    /// 库内 6 个归档 model 已改用 `@objc(Reader*Model)` 固定 ObjC 类名，写入的是无模块前缀
    /// 的固定名，此后改模块名或 Swift 类名都不影响归档格式，因此不必再维护映射表。
    ///
    /// 之所以能直接去掉兼容层：本库随首个版本一同发布，线上不存在历史格式的归档数据。
    /// **若将来 `@objc` 固定名有变动，必须在此重新引入 `setClass(_:forClassName:)` 映射**，
    /// 否则升级用户的阅读进度、书签与章节缓存会全部失联。
    private class func registerLegacyClassNames(on unarchiver: NSKeyedUnarchiver) {
        // 当前无需映射：@objc 固定名已与模块名解耦
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
