//
//  ReaderChapterAccessDelegate.swift
//  Reader Engine — Contracts
//
//  章节访问受阻时的回调协议：引擎发现「章节未解锁」或「目录尚未加载完」时通知宿主，
//  由宿主决定弹解锁面板、补拉目录等业务动作。
//
//  这是引擎自有协议（两个方法的参数都是引擎类型 `ReaderViewController`），
//  定义归属引擎：引擎声明需求，接入方实现。
//
//  类型名保留 `ReaderChapterAccessDelegate` 未改：引擎内 32 处引用与宿主实现
//  都用这个名字，保持一致。
//  与本次抽库解耦，避免把两类改动混在一起。
//

import Foundation

/// 章节解锁状态回调协议
public protocol ReaderChapterAccessDelegate: AnyObject {
    /// 当尝试加载未解锁的章节时触发
    /// - Parameters:
    ///   - chapterId: 章节ID
    ///   - chapterCaption: 章节名称
    ///   - chapterOrdinal: 章节序号（从1开始）
    func readController(_ controller: ReaderViewController, didAttemptToLoadLockedChapter chapterId: Int, chapterCaption: String, chapterOrdinal: Int)

    /// 当翻到「已加载章节边界但目录尚未完整加载」时触发，请求补齐后续目录页
    /// （避免分页目录未加载完时边界卡住或被误判为末章）。
    func readControllerDidReachUnloadedBoundary(_ controller: ReaderViewController)
}

// MARK: - 默认实现
extension ReaderChapterAccessDelegate {
    /// 默认空实现：非分页目录场景无需处理。
    public func readControllerDidReachUnloadedBoundary(_ controller: ReaderViewController) {}
}
