//
//  ReaderNotifications.swift
//  Reader Engine — Contracts
//
//  引擎监听的通知名。
//
//  引擎需要在两类外部事件发生时刷新界面，但事件的**产生方是接入方**
//  （目录分页拉取、书签远端合并都在宿主侧完成），故通知名由引擎声明、接入方发送，
//  作为双方的约定。
//
//  接入方用法：完成对应动作后 `NotificationCenter.default.post(name: .readerChapterListDidUpdate, object: nil)`。
//
//  通知名在本文件统一声明，接入方直接使用这里的符号发送，不要另行声明同值的
//  `Notification.Name`——那样两侧靠字符串对齐，一方改动不会有编译错误。
//

import Foundation

public extension Notification.Name {

    /// 章节目录有更新（分页目录又拉到一页、或目录整体刷新）。
    /// 引擎收到后刷新目录列表与书签列表里的章节名。
    static let readerChapterListDidUpdate = Notification.Name("readerChapterListDidUpdate")

    /// 本地书签与远端完成合并。引擎收到后刷新书签列表。
    static let readerBookmarksMerged = Notification.Name("readerBookmarksMerged")
}
