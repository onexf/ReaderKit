//
//  ReaderEnumList.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/22.
//

import UIKit

/// 书籍来源类型
public enum ReaderBookSourceType: NSInteger {
    /// 网络小说
    case network
    /// 本地小说
    case local
}

/// 阅读翻页类型
///
/// rawValue 必须保持稳定，不可改动、不可复用：
/// 0（仿真）、1（覆盖）、4（无效果）是历史上支持过的模式，已随死代码清理移除。
/// 老用户归档里仍可能存着这三个值，由 `ReaderConfiguration.initData` 统一归一为 `.scroll`。
/// 若把 translation/scroll 改成隐式 rawValue（0/1），老用户的翻页偏好会被静默改写。
public enum ReaderEffectType: NSInteger {
    /// 平移（左右翻页）
    case translation = 2
    /// 滚动（上下滚动）
    case scroll = 3
}

/// 阅读字体类型
public enum ReaderFontType: NSInteger {
    /// 系统
    case system
    /// 黑体
    case one
    /// 楷体
    case two
    /// 宋体
    case three
}

/// 阅读内容间距类型
public enum ReaderSpacingType: NSInteger {
    /// 大间距
    case big
    /// 适中间距
    case middle
    /// 小间距
    case small
}

/// 阅读进度类型
public enum ReaderProgressType: NSInteger {
    /// 总进度
    case total
    /// 分页进度
    case page
}

/// 分页内容是以什么开头
public enum ReaderSheetHeaderType: NSInteger {
    /// 章节名
    case chapterName
    /// 段落
    case paragraph
    /// 行内容
    case line
}
/// 朗读时当前句的高亮样式
///
/// 由接入方经 `ReaderEnvironment.speechHighlightStyle` 选择。
/// 这是接入方的设计取向，不是终端用户设置，故不入 `ReaderConfiguration`、也不持久化，
/// rawValue 无需保持稳定。
public enum ReaderSpeechHighlightStyle: NSInteger {
    /// 背景色块（默认）。在正文绘制前铺一层 `speechHighlightFill`
    case background
    /// 文字变色。把高亮范围的前景色改为 `speechHighlightText`
    case textColor
    /// 下划线。在高亮范围各行底边画 `speechHighlightFill` 色的线
    case underline
}
