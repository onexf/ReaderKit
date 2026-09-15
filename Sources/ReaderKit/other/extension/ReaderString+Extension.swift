//
//  ReaderString+Extension.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/24.
//

import UIKit
import CryptoKit

extension String {
    
    public var length: Int { return (self as NSString).length }
    
    public var bool: Bool { return (self as NSString).boolValue }
    
    public var integer: NSInteger { return (self as NSString).integerValue }
    
    public var float: Float { return (self as NSString).floatValue }
    
    public var cgFloat: CGFloat { return CGFloat(self.float) }
    
    public var double: Double { return (self as NSString).doubleValue }
    
    /// 文件后缀(不带'.')
    public var pathExtension: String { return (self as NSString).pathExtension }
    
    /// 文件名(带后缀)
    public var lastPathComponent: String { return (self as NSString).lastPathComponent }
    
    /// 文件名(不带后缀)
    public var deletingPathExtension: String { return (self as NSString).deletingPathExtension }
    
    /// 去除首尾空格
    public var removeSpaceHeadAndTail: String { return trimmingCharacters(in: NSCharacterSet.whitespaces) }
    
    /// 去除首尾换行
    public var removeEnterHeadAndTail: String { return trimmingCharacters(in: NSCharacterSet.whitespaces) }
    
    /// 去除首尾空格和换行
    public var removeSEHeadAndTail: String { return trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines) }
    
    /// 去掉所有空格
    public var removeSapceAll: String { return replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "") }
    
    /// 去除所有换行
    public var removeEnterAll: String { return replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "") }
    
    /// 换行转单空格(按行拆分→去首尾空白→丢空行→单空格连接),用于书签摘录:
    /// 章节开头书签的标题与正文之间至少保留一个空格,避免粘连
    public var enterToSingleSpace: String {
        return components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    /// 去除所有空格换行
    public var removeSapceEnterAll: String { return removeSapceAll.replacingOccurrences(of: "\n", with: "") }
    
    /// 是否为整数
    public var isInt: Bool {
        
        let scan: Scanner = Scanner(string: self)
        
        var val: Int = 0
        
        return scan.scanInt(&val) && scan.isAtEnd
    }
    
    /// 是否为数字或Float
    public var isFloat: Bool {
        
        let scan: Scanner = Scanner(string: self)
        
        var val: Float = 0
        
        return scan.scanFloat(&val) && scan.isAtEnd
    }
    
    /// 是否为空格
    public var isSpace: Bool {
        
        if (self == " ") || (self == "　") { return true }
        
        return false
    }
    
    /// 是否为空格或者回车
    public var isSpaceOrEnter: Bool {
        
        if isSpace || (self == "\n") { return true }
        
        return false
    }
    
    /// MD5 摘要（十六进制小写）。
    ///
    /// 仅用于把 URL 归一化成本地缓存文件名，**不用于任何安全场景**
    /// （MD5 已不具备抗碰撞性，CryptoKit 也因此把它放在 `Insecure` 命名空间下）。
    ///
    /// 名字不叫 `md5`：接入方很可能已在 String 上定义同名属性，加前缀避免冲突。
    /// 用 CryptoKit 自实现，不引入三方依赖。
    public var readerMD5: String {
        let digest = Insecure.MD5.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// MD5加密
//    var md5: String {
//        
//        let string = cString(using: String.Encoding.utf8)
//        
//        let stringLength = CUnsignedInt(lengthOfBytes(using: String.Encoding.utf8))
//        
//        let digestLength = Int(CC_MD5_DIGEST_LENGTH)
//        
//        let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLength)
//        
//        CC_MD5(string!, stringLength, result)
//        
//        let hash = NSMutableString()
//        
//        for i in 0 ..< digestLength { hash.appendFormat("%02x", result[i]) }
//        
//        result.deinitialize()
//        
//        return String(format: hash as String)
//    }
    
    /// 转JSON
    public var json: Any? {
        
        let data = self.data(using: String.Encoding.utf8, allowLossyConversion: false)
        
        let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments)
        
        return json
    }
    
    /// 是否包含指定字符串
    public func range(_ string: String) ->NSRange {
        
        return (self as NSString).range(of: string)
    }
    
    /// 截取字符串
    public func substring(_ range: NSRange) ->String {
        
        return (self as NSString).substring(with: range)
    }
    
    /// 处理带中文的字符串
    public func addingPercentEncoding(_ characters: CharacterSet = .urlQueryAllowed) ->String {
        
        return (self as NSString).addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
    }
    
    /// 正则替换字符
    public func replacingCharacters(_ pattern: String, _ template: String) ->String {
        
        do {
            let regularExpression = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
            
            return regularExpression.stringByReplacingMatches(in: self, options: NSRegularExpression.MatchingOptions.reportProgress, range: NSMakeRange(0, length), withTemplate: template)
            
        } catch {return self}
    }
    
    /// 正则搜索相关字符位置
    public func matches(_ pattern: String) ->[NSTextCheckingResult] {
        
        if isEmpty {return []}
        
        do {
            let regularExpression = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
            
            return regularExpression.matches(in: self, options: NSRegularExpression.MatchingOptions.reportProgress, range: NSMakeRange(0, length))
            
        } catch {return []}
    }
    
    /// 计算大小
    public func size(_ font: UIFont, _ size: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) ->CGSize {
        
        let string: NSString = self as NSString
        
        return string.boundingRect(with: size, options: [.usesLineFragmentOrigin,.usesFontLeading], attributes: [.font:font], context: nil).size
    }
}

extension NSAttributedString {
    
    /// 计算size
    public func size(_ size: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) ->CGSize{
        
        return self.boundingRect(with: size, options: [NSStringDrawingOptions.usesLineFragmentOrigin,NSStringDrawingOptions.usesFontLeading], context: nil).size
    }
    
    /// 扩展拼接
    public func add<T: NSAttributedString>(_ string: T) ->NSAttributedString {
        
        let attributedText = NSMutableAttributedString(attributedString: self)
        
        attributedText.append(string)
        
        return attributedText
    }
}


extension String {

    // 视频 cache key
    public var videoIdFromUrl: String? {

        let videoIdFromUrl = getMediaCacheKey()
        return videoIdFromUrl
    }

    // 获取资源有效期【结构：xxxx?xxx=过期时间戳-x-x******】【秒级】
    public var expiredTime: Int {
        let components = self.components(separatedBy: "?")
        guard let expiredTimeString = components.last?.components(separatedBy: "=").last?.components(separatedBy: "-").first else {
            return -1
        }

        return Int(expiredTimeString) ?? -1
    }


    // 图片 cache key
    public var imageCacheKey: String {
        let imageCacheKey = getMediaCacheKey()
        return imageCacheKey
    }

    private func getMediaCacheKey() -> String {
        guard let urlComponents = URLComponents(string: self) else {
            return self
        }

        guard let host = urlComponents.host else {
            return self
        }

        let auth_keyItems = urlComponents.queryItems?.filter { $0.name == "auth_key" }
        let auth_key = auth_keyItems?.first?.value
        let notHost = self.replacingOccurrences(of: host, with: "")
        var notHost_auth = notHost
        if let auth_key = auth_key {
            notHost_auth = notHost.replacingOccurrences(of: auth_key, with: "")
        }
        #if DEBUG
//        Log.d("notHost_auth:\(notHost_auth)")
        #endif
        return notHost_auth.readerMD5
    }
    
    /// 封面等图片的压缩 URL。CDN 域名切换与压缩参数拼接由宿主实现，
    /// 引擎只提供原始 URL 与目标像素尺寸（见 ReaderHostConfiguring）。
    public func getImageCompressURL(width: Int, heigth: Int) -> String {
        return ReaderEnvironment.hostConfiguration.compressedImageURL(self, width: width, height: heigth)
    }
}
