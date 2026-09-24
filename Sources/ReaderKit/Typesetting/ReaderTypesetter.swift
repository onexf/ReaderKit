//
//  ReaderTypesetter.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/27.
//

import UIKit

/// 解析完成
public typealias ReaderParserCompletion = (_ bookModel: ReaderBookModel?) ->Void

open class ReaderTypesetter: NSObject {
    
    // MARK: -- 内容分页
    
    /// 内容分页
    ///
    /// - Parameters:
    ///   - attrString: 内容
    ///   - rect: 显示范围
    ///   - isFirstChapter: 是否为本文章第一个展示章节,如果是则加入书籍首页。(小技巧:如果不需要书籍首页,可不用传,默认就是不带书籍首页)
    /// - Returns: 内容分页列表
    public class func pageing(attrString: NSAttributedString, rect: CGRect, isFirstChapter: Bool = false) ->[ReaderPageModel] {
        
        var layoutPages: [ReaderPageModel] = []
        
        if isFirstChapter { // 第一页为书籍页面
            
            let layoutPage = ReaderPageModel()
            
            layoutPage.range = NSMakeRange(READER_BOOK_HOME_PAGE, 1)
            
            layoutPage.contentSize = READER_VIEW_RECT.size
            
            layoutPages.append(layoutPage)
        }
        
        let ranges = ReaderCoreText.pageRanges(attrString: attrString, rect: rect)
        
        if !ranges.isEmpty {
            
            let count = ranges.count
            
            for i in 0..<count {
                
                let range = ranges[i]
                
                let layoutPage = ReaderPageModel()
                
                let content = attrString.attributedSubstring(from: range)
                
                layoutPage.range = range
                
                layoutPage.content = content
                
                layoutPage.page = NSNumber(value: i)
                
                // --- (滚动模式 || 长按菜单) 使用 ---
                
                // 注意: 为什么这些数据会放到这里赋值，而不是封装起来， 原因是 contentSize 计算封装在 pageModel内部计算出现宽高为0的情况，所以放出来到这里计算，原因还未找到，但是放到这里计算就没有问题。封装起来则会出现宽高度不计算的情况。
                
                // 内容Size (滚动模式 || 长按菜单)
                let maxW = READER_VIEW_RECT.width
                
                layoutPage.contentSize = CGSize(width: maxW, height: ReaderCoreText.attributedStringHeight(attrString: content, maxW: maxW))
                
                
                // 当前页面开头是什么数据开头 (滚动模式)
                if i == 0 { layoutPage.headerKind = .chapterName
                    
                }else if content.string.hasPrefix(READER_PH_SPACE) || content.string.hasPrefix("\n") { layoutPage.headerKind = .paragraph
                    
                }else{ layoutPage.headerKind = .line }
                
                
                // 根据开头类型返回开头高度 (滚动模式)
                if layoutPage.headerKind == .chapterName { layoutPage.headerInsetHeight = 0
                    
                }else if layoutPage.headerKind == .paragraph { layoutPage.headerInsetHeight = ReaderConfiguration.shared().paragraphSpacing
                    
                }else{ layoutPage.headerInsetHeight = ReaderConfiguration.shared().lineSpacing }
                
                // --- (滚动模式 || 长按菜单) 使用 ---
                
                layoutPages.append(layoutPage)
            }
        }
        
        return layoutPages
    }
    
    
    // MARK: -- 内容整理排版
    
    /// 内容排版整理
    ///
    /// - Parameter content: 内容
    /// - Returns: 整理好的内容
    public class func contentTypesetting(content: String) ->String {
        
        // 替换单换行
        var content = content.replacingOccurrences(of: "\r", with: "")
        
        // 替换换行 以及 多个换行 为 换行加空格
        content = content.replacingCharacters("\\s*\\n+\\s*", "\n" + READER_PH_SPACE)
        
        // 返回
        return content
    }
    
    
    // MARK: -- 解码URL
    
    /// 解码URL
    ///
    /// - Parameter url: 文件路径
    /// - Returns: 内容
    public class func encode(url: URL) ->String {
        
        var content = ""
        
        if url.absoluteString.isEmpty { return content }
        
        // utf8
        content = encode(url: url, encoding: String.Encoding.utf8.rawValue)
        
        // 进制编码
        if content.isEmpty { content = encode(url: url, encoding: 0x80000632) }
        
        if content.isEmpty { content = encode(url: url, encoding: 0x80000631) }
        
        if content.isEmpty { content = "" }
        
        return content
    }
    
    /// 解析URL
    ///
    /// - Parameters:
    ///   - url: 文件路径
    ///   - encoding: 进制编码
    /// - Returns: 内容
    public class func encode(url: URL, encoding: UInt) ->String {
        
        do{
            return try NSString(contentsOf: url, encoding: encoding) as String
            
        }catch{}
        
        return ""
    }
}
