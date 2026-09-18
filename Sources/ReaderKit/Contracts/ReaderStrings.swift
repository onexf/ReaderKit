//
//  ReaderStrings.swift
//  Reader Engine — Contracts
//
//  阅读器引擎所需的全部用户可见文案。
//
//  设计取舍：用**配置结构体**而非运行时 delegate 查表。
//  - 编译期即可发现缺失（新增字段不填就编译不过），delegate 方案要跑到那行才知道
//  - 可测试：构造一个实例即可，无需 mock 协议
//  - 无运行时间接开销
//
//  宿主初始化阅读器时传入填好的实例；不传则用英文默认值，保证库能独立跑起来。
//

import Foundation

/// 阅读器引擎的文案表。
///
/// 所有字段都有英文默认值，宿主只需覆盖需要本地化的项。
public struct ReaderStrings {

    // MARK: - 目录 / 章节

    /// 「章」的称谓，用于目录 cell 前缀、当前章节标签等。例：`Chapter`
    public var chapter: String = "Chapter"
    /// 目录按钮标题
    public var directory: String = "Directory"
    /// 正文读完后，页眉显示的章节名
    public var readEndChapterName: String = "The End"
    /// 上一章按钮标题（进度面板）
    public var previousChapter: String = "Previous"
    /// 下一章按钮标题（进度面板）
    public var nextChapter: String = "Next"
    /// 章节名缺失时的占位（书签命名等场景）
    public var unnamedChapter: String = "Untitled chapter"
    /// 本地 txt 解析出的卷首/前言分节名
    public var localBookPreface: String = "Preface"

    // MARK: - 阅读菜单

    /// 设置按钮标题
    public var setting: String = "Setting"
    /// 字号调节区标题
    public var settingSize: String = "Size"
    /// 切换到夜间模式的按钮标题
    public var night: String = "Night"
    /// 切换到日间模式的按钮标题
    public var day: String = "Day"
    /// 长篇阅读模式（左右翻页）名称
    public var readingModeLong: String = "Left & Right"
    /// 短篇阅读模式（上下滚动）名称
    public var readingModeShort: String = "Up & Down"

    // MARK: - 书签

    /// 书签列表空态提示
    public var bookmarkEmpty: String = "No bookmarks yet"
    /// 锁定章节书签的标题
    public var bookmarkLocked: String = "Locked"
    /// 锁定章节书签的副标题
    public var bookmarkLockedSub: String = "Unlock this chapter to view"
    /// 添加书签成功
    public var bookmarkAdded: String = "Bookmark added"
    /// 删除书签成功
    public var bookmarkDeleted: String = "Bookmark removed"
    /// 书签操作失败
    public var bookmarkFailed: String = "Operation failed, please try again"
    /// 书签数量达到上限
    public var bookmarkLimited: String = "Bookmark limit reached"

    // MARK: - 书签删除确认

    /// 单条删除选项
    public var bookmarkDeleteOne: String = "Remove"
    /// 全部删除选项
    public var bookmarkDeleteAll: String = "Clear All"
    /// 取消
    public var cancel: String = "Cancel"
    /// 长按选中文字后的「复制」菜单项
    public var copy: String = "Copy"
    /// 删除确认弹窗标题
    public var bookmarkDeleteAlertTitle: String = "Remove this bookmark?"
    /// 删除确认弹窗的确认按钮
    public var bookmarkDeleteAlertConfirm: String = "Confirm"

    // MARK: - 其它提示

    /// 已加入书架
    public var addedToBookshelf: String = "Added to bookshelf"

    /// 章节加载失败提示，`%@` 为章节名。
    ///
    /// 用闭包而非带占位符的字符串：宿主可自行决定拼接方式，
    /// 也避免 `String(format:)` 的占位符数量与类型在编译期不受检查。
    public var chapterLoadFailed: (_ chapterName: String) -> String = { name in
        "Failed to load \(name), please try again"
    }

    // MARK: - 朗读

    /// 朗读入口按钮标题
    public var speechPlay: String = "Read Aloud"
    /// 朗读控制条的暂停按钮标题
    public var speechPause: String = "Pause"
    /// 朗读控制条的继续按钮标题
    public var speechResume: String = "Resume"
    /// 长按正文后弹出的「从这里开始读」动作标题
    public var speechStartHere: String = "Start reading here"
    /// 设备上没有可用于当前内容语言的音色
    public var speechVoiceUnavailable: String = "No voice available for this language"
    /// 朗读失败的通用提示
    public var speechFailed: String = "Read aloud failed, please try again"

    /// 全默认值实例（英文）。库在宿主未注入时使用，保证可独立运行。
    public static let `default` = ReaderStrings()

    public init() {}
}
