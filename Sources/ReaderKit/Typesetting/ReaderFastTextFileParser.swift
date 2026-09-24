//
//  ReaderFastTextFileParser.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/20.
//

import UIKit

open class ReaderFastTextFileParser: NSObject {
    
    /// 异步解析本地链接
    ///
    /// - Parameters:
    ///   - url: 本地文件地址
    ///   - completion: 解析完成
    public class func parser(url: URL!, completion: ReaderParserCompletion!) {
        
        DispatchQueue.global().async {
            
            let bookModel = parser(url: url)
            
            DispatchQueue.main.async {
                
                completion?(bookModel)
            }
        }
    }
    
    /// 解析本地链接
    ///
    /// - Parameter url: 本地文件地址
    /// - Returns: 阅读对象
    private class func parser(url: URL!) ->ReaderBookModel? {
        
        // log("🔍 ReaderFastTextFileParser.parser 开始解析:")
        // log("   - URL: \(url?.absoluteString ?? "nil")")
        
        // 链接不为空且是本地文件路径
        if url == nil || url.absoluteString.isEmpty || !url.isFileURL { 
            // log("   - ❌ URL 无效")
            return nil 
        }
        
        // 获取文件后缀名作为 storyName
        let storyName = url.absoluteString.removingPercentEncoding?.lastPathComponent.deletingPathExtension ?? ""
        // log("   - 书名: \(storyName)")
        
        // storyName 作为 storyID
        let storyID = storyName
        
        // storyID 为空
        if storyID.isEmpty { 
            // log("   - ❌ storyID 为空")
            return nil 
        }
        
        // log("   - storyID: \(storyID)")
        // log("   - 检查是否已存在: \(ReaderBookModel.isExist(storyID: storyID))")
        
        if !ReaderBookModel.isExist(storyID: storyID) { // 不存在
            
            // log("   - 开始解析新文件...")
            
            // 解析数据
            let content = ReaderTypesetter.encode(url: url)
            // log("   - 文件内容长度: \(content.count)")
            // log("   - 内容预览: \(String(content.prefix(100)))")
            
            // 解析失败
            if content.isEmpty { 
                // log("   - ❌ 文件内容为空")
                return nil 
            }
            
            // 阅读模型
            let bookModel = ReaderBookModel.model(storyID: storyID)
            
            // 书籍类型
            bookModel.storySourceType = .local
            
            // 小说名称
            bookModel.storyName = storyName
            
            // 解析内容并获得章节列表
            parser(bookModel: bookModel, content: content)
            
            // log("   - 解析后章节数量: \(bookModel.catalogueEntries?.count ?? 0)")
            
            // 解析内容失败
            if bookModel.catalogueEntries.isEmpty { 
                // log("   - ❌ 章节列表为空")
                return nil 
            }
            
            // 首章
            let chapterListModel = bookModel.catalogueEntries.first!
            // log("   - 第一章: \(chapterListModel.name ?? "未知")")
            
            // 加载首章
            let chapterModel = parser(bookModel: bookModel, chapterID: chapterListModel.id)
            // log("   - 首章加载结果: \(chapterModel != nil ? "成功" : "失败")")
            
            // 设置第一个章节为阅读记录
            bookModel.readingRecord.modify(chapterID:  chapterListModel.id, toPage: 0)
            
            // 保存
            bookModel.save()
            
            // log("   - ✅ 解析完成，返回 readModel")
            
            // 返回
            return bookModel
            
        }else{ // 存在
            
            // log("   - 从缓存加载 readModel")
            
            // 返回
            return ReaderBookModel.model(storyID: storyID)
        }
    }
    
    /// 解析整本小说
    ///
    /// - Parameters:
    ///   - bookModel: bookModel
    ///   - content: 小说内容
    private class func parser(bookModel: ReaderBookModel, content: String!) {
        
        // log("📚 开始解析章节内容:")
        // log("   - 内容长度: \(content?.count ?? 0)")
        
        // 章节列表
        var catalogueEntries: [ReaderChapterListItemModel] = []
        
        // 章节范围列表 [章节ID:[章节优先级:章节内容Range]]
        var ranges: [String: [String: NSRange]] = [:]
        
        // 正则
        let parten = ReaderEnvironment.hostConfiguration.localChapterTitlePattern
        
        // 排版
        let content = ReaderTypesetter.contentTypesetting(content: content)
        // log("   - 排版后内容长度: \(content.count)")
        // log("   - 排版后内容预览: \(String(content.prefix(200)))")
        
        // 正则匹配结果
        var results: [NSTextCheckingResult] = []
        
        // 开始匹配
        do{
            let regularExpression: NSRegularExpression = try NSRegularExpression(pattern: parten, options: .caseInsensitive)
            
            results = regularExpression.matches(in: content, options: .reportCompletion, range: NSRange(location: 0, length: content.length))
            
            // log("   - 正则匹配到 \(results.count) 个章节")
            
        }catch{ 
            // log("   - ❌ 正则匹配失败")
            return  
        }
        
        // 解析匹配结果
        if !results.isEmpty {
            
            // log("   - 处理匹配到的章节...")
            
            // 章节数量
            let count = results.count
            
            // 记录最后一个Range
            var lastRange: NSRange!
            
            // 有前言
            var isHavePreface: Bool = true
            
            // 便利
            for i in 0...count {
                
                // 章节数量分析:
                // count + 1  = 匹配到的章节数量 + 最后一个章节
                // 1 + count + 1  = 第一章前面的前言内容 + 匹配到的章节数量 + 最后一个章节
                // log("章节总数: \(count + 1)  当前正在解析: \(i + 1)")
                
                var range = NSMakeRange(0, 0)
                
                var location = 0
                
                if i < count {
                    
                    range = results[i].range
                    
                    location = range.location
                }
                
                // 章节列表
                let chapterListModel = ReaderChapterListItemModel()
                
                // 书ID
                chapterListModel.storyID = bookModel.storyID
                
                // 章节ID
                chapterListModel.id = NSNumber(value: (i + NSNumber(value: isHavePreface).intValue))
                
                // 优先级
                let priority = NSNumber(value: (i - NSNumber(value: !isHavePreface).intValue))
                
                if i == 0 { // 前言
                    
                    // 章节名
                    chapterListModel.name = ReaderEnvironment.strings.localBookPreface
                    
                    // 内容Range
                    ranges[chapterListModel.id.stringValue] = [priority.stringValue: NSMakeRange(0, location)]
                    
                    // 内容
                    let content = content.substring(NSMakeRange(0, location))
                    
                    // 记录
                    lastRange = range
                    
                    // 没有内容则不需要添加列表
                    if content.isEmpty {
                        
                        isHavePreface = false
                        
                        continue
                    }
                    
                }else if i == count { // 结尾
                    
                    // 章节名
                    chapterListModel.name = content.substring(lastRange)
                    
                    // 内容Range
                    ranges[chapterListModel.id.stringValue] =  [priority.stringValue: NSMakeRange(lastRange.location + lastRange.length, content.length - lastRange.location - lastRange.length)]
                    
                }else { // 中间章节
                    
                    // 章节名
                    chapterListModel.name =  content.substring(lastRange)
                    
                    // 内容Range
                    ranges[chapterListModel.id.stringValue] = [priority.stringValue: NSMakeRange(lastRange.location + lastRange.length, location - lastRange.location - lastRange.length)]
                }
                
                // 记录
                lastRange = range
                
                // 通过章节内容生成章节列表
                catalogueEntries.append(chapterListModel)
                
                // log("     - 添加章节 \(i): \(chapterListModel.name ?? "未知")")
            }
            
        }else{
            
            // log("   - 没有匹配到章节，创建默认章节")
            
            // 章节列表
            let chapterListModel = ReaderChapterListItemModel()
            
            // 章节名
            chapterListModel.name = ReaderEnvironment.strings.localBookPreface
            
            // 书ID
            chapterListModel.storyID = bookModel.storyID
            
            // 章节ID
            chapterListModel.id = NSNumber(value: 1)
            
            // 优先级
            let priority = NSNumber(value: 0)
            
            // 内容Range
            ranges[chapterListModel.id.stringValue] = [priority.stringValue: NSMakeRange(0, content.length)]
            
            // 添加章节列表模型
            catalogueEntries.append(chapterListModel)
            
            // log("     - 创建默认章节: \(chapterListModel.name ?? "未知")")
        }
        
        // log("   - 最终章节数量: \(catalogueEntries.count)")
        
        // 小说全文
        bookModel.rawText = content
        
        // 章节列表
        bookModel.catalogueEntries = catalogueEntries
        
        // 章节内容范围
        bookModel.ranges = ranges
    }
    
    /// 获取单个指定章节
    public class func parser(bookModel: ReaderBookModel!, chapterID: NSNumber!, isUpdateFont: Bool = true) ->ReaderChapterModel? {
        
        // 获得[章节优先级:章节内容Range]
        let range = bookModel.ranges[chapterID.stringValue]
      
        // 没有了
        if range != nil {
            
            // 当前优先级
            let priority = range!.keys.first!.integer
            
            // 章节内容范围
            let range = range!.values.first
            
            // 当前章节
            let chapterListModel = bookModel.catalogueEntries[priority]
            
            /// 第一个章节
            let isFirstChapter: Bool = (priority == 0)
            
            /// 最后一个章节
            let isLastChapter: Bool = (priority == (bookModel.catalogueEntries.count - 1))
            
            // 上一个章节ID
            let priorChapterID: NSNumber! = isFirstChapter ? READER_NO_MORE_CHAPTER : bookModel.catalogueEntries[priority - 1].id
            
            // 下一个章节ID
            let followingChapterID: NSNumber! = isLastChapter ? READER_NO_MORE_CHAPTER : bookModel.catalogueEntries[priority + 1].id
            
            // 章节内容
            let chapterModel = ReaderChapterModel()
            
            // 书ID
            chapterModel.storyID = chapterListModel.storyID
            
            // 章节ID
            chapterModel.id = chapterListModel.id
            
            // 章节名
            chapterModel.name = chapterListModel.name
            
            // 优先级
            chapterModel.priority = NSNumber(value: priority)
            
            // 上一个章节ID
            chapterModel.priorChapterID = priorChapterID
            
            // 下一个章节ID
            chapterModel.followingChapterID = followingChapterID
            
            // 章节内容
            chapterModel.content = READER_PH_SPACE + bookModel.rawText.substring(range!).removeSEHeadAndTail

            // 保存
            if isUpdateFont { chapterModel.reviseFont()
                
            }else{ chapterModel.save() }
            
            // 返回
            return chapterModel
        }
        
        return nil
    }
}
