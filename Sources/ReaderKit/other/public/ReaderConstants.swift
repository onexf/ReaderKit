//
//  ReaderConstants.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/02.
//

import UIKit

// MARK: -- 屏幕属性
//
// 屏幕尺寸 / 安全区 / 导航栏高度收敛到引擎自包含的 ReaderScreenMetrics，
// 原先散落此处的 ScreenWidth / ScreenHeight / SafeAreaTopHeight / SafeAreaBottomHeight /
// NavgationBarHeight 及机型常量已删除。
// 用法：ReaderScreenMetrics.screenWidth / .safeAreaTop / .navBarHeight 等。


// MARK: -- 屏幕适配

/// 以iPhone6为比例
public func readerScaled(_ size: CGFloat) ->CGFloat {
    size
//    return size * (ScreenWidth / 375)
}


// MARK: 颜色

/// 由 RGB 分量（0–255）构造颜色，不透明
public func readerColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
    
    return readerColor(r, g, b, 1.0)
}

/// 由 RGB 分量（0–255）与 alpha 构造颜色
public func readerColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> UIColor {
    
    return UIColor(red: r/255.0, green: g/255.0, blue: b/255.0, alpha: a)
}


// MARK: 时间

/// 获取指定时间字符串 (dateFormat: "YYYY-MM-dd-HH-mm-ss")
public func readerClockText(_ dateFormat: String, _ time: Date = Date()) ->String {
    
    let dateFormatter = DateFormatter()
    
    dateFormatter.dateFormat = dateFormat
    
    return dateFormatter.string(from: time)
}

/// 获得当前时间戳
public func readerTimestamp(_ isMsec: Bool = false) ->TimeInterval {
    
    if isMsec { return Date().timeIntervalSince1970 * 1000
        
    }else{ return Date().timeIntervalSince1970 }
}


// MARK: 延迟执行

/// 延迟执行
public func readerDelay(_ execute:@escaping ()->Void) { readerDelay(0.01, execute) }

/// 延迟执行
public func readerDelay(_ delay: TimeInterval, _ execute:@escaping ()->Void) {
    
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay, execute: execute)
}


// MARK: Block

/// 动画完成
public typealias ReaderAnimationCompletion = ()->Void


// MARK: 其他属性

/// 没有章节了(可以指定为任意标识,默认是空则为没有更多章节)
public let READER_NO_MORE_CHAPTER: NSNumber! = nil

/// 书籍首页-书名页
public let READER_BOOK_HOME_PAGE: NSInteger = -1

/// 用于指定章节最后一页
public let READER_LAST_PAGE: NSInteger = -1

/// 动画时间
public let READER_AD_TIME: TimeInterval = 0.2

/// 段落头部双圆角空格
public let READER_PH_SPACE: String = "　　"

/// 正文文本相关的判定与格式化规则。
public enum ReaderTextRule {

    /// 判断文本是否以拉丁字母为主（占比超过 50%）
    public static func isLatin(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let sample = String(text.prefix(500))
        let latinCount = sample.unicodeScalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || // A-Z
            (0x0061...0x007A).contains(scalar.value)    // a-z
        }.count
        let totalLetters = sample.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }.count
        guard totalLetters > 0 else { return false }
        return Double(latinCount) / Double(totalLetters) > 0.5
    }

    /// 章节标题在正文中的呈现形式（末尾补换行，供排版分段）
    public static func chapterHeading(_ name: String) -> String { return "\(name)\n" }
}

/// 主文件夹名称
public let READER_FOLDER_NAME: String = "ReaderKit"

/// Key - 配置
public let READER_KEY_CONFIGURE: String = "ReaderKit.configuration"

/// Key - 阅读记录
public let READER_KEY_RECORD: String = "ReaderKit.readRecord"

/// Key - 阅读对象
public let READER_KEY_OBJECT: String = "ReaderKit.readObject"

/// Key - 日夜间模式 NO:日间 YES:夜间
public let READER_KEY_MODE_DAY_NIGHT: String = "ReaderKit.nightMode"

/// 沙河路径
public let READER_DOCUMENT_DIRECTORY_PATH: String = (NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).last! as String)



// MARK: 范围

/// 阅读范围(阅读顶部状态栏 + 阅读View + 阅读底部状态栏)
public var READER_RECT: CGRect! {
    
    // 适配全面屏顶部安全区域
    let top = ReaderScreenMetrics.safeAreaTop
    
    // 适配全面屏底部安全区域
    let bottom = ReaderScreenMetrics.safeAreaBottom
    
    return CGRect(x: READER_SPACE_SA_20, y: top, width: ReaderScreenMetrics.screenWidth - READER_SPACE_SA_40, height: ReaderScreenMetrics.screenHeight - top - bottom)
}

/// 阅读View范围
public var READER_VIEW_RECT: CGRect! {
    
    let rect = READER_RECT!
    
    // 左右翻页模式：底部预留页脚区域（高度同底部信息栏），正文从顶栏下方延伸到页脚区上方；
    // 不做 -10 顶部重叠（翻页模式顶栏固定显示）
    let isPageTurnMode = ReaderConfiguration.shared().effectType == .translation
    if isPageTurnMode {
        return CGRect(x: rect.minX,
                      y: rect.minY + READER_STATUS_TOP_VIEW_HEIGHT,
                      width: rect.width,
                      height: rect.height - READER_STATUS_TOP_VIEW_HEIGHT - READER_STATUS_BOTTOM_VIEW_HEIGHT)
    }
    
    // 滚动模式：内容向上移动10，与顶部状态栏重叠
    let topMargin: CGFloat = -10
    
    return CGRect(x: rect.minX, y: rect.minY + READER_STATUS_TOP_VIEW_HEIGHT + topMargin, width: rect.width, height: rect.height - READER_STATUS_TOP_VIEW_HEIGHT - READER_STATUS_BOTTOM_VIEW_HEIGHT - topMargin)
}

// MARK: 进度相关

/// 全书阅读进度的计算与展示。
public enum ReaderProgress {

/// 进度百分比文案
public static func text(progress: Float) ->String {
    
    return String(format: "%.1f%%", (floor(progress * 1000) / 10))
}

/// 计算全书进度（0.0–1.0）
public static func ratio(bookModel: ReaderBookModel!, recordModel: ReaderReadRecordModel!) ->Float {
    
    // 当前阅读进度
    var progress: Float = 0.0
    
    // 临时检查
    if bookModel == nil || recordModel == nil { return progress }
    
    if bookModel.isAuthoritativeFinalChapter(chapterID: recordModel.chapterModel?.id) && recordModel.isLastPage { // 全书真末章最后一页
        
        // 获得当前阅读进度
        progress = 1.0
        
    }else{
        
        // 当前章节在所有章节列表中的位置
        let chapterIndex: Float = recordModel.chapterModel.priority.floatValue
        
        // 章节总数量
        let chapterCount: Float = Float(bookModel.chapterListModels.count)
        
        // 阅读记录首位置
        let locationFirst: Float = recordModel.locationFirst.floatValue
        
        // 阅读记录内容长度
        let fullContentLength: Float = Float(recordModel.chapterModel.typesetContent.length)
        
        // 获得当前阅读进度
        progress = (chapterIndex / chapterCount + locationFirst / fullContentLength / chapterCount)
    }
    
    // 返回
    return progress
}
}
