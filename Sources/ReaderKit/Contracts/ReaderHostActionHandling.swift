//
//  ReaderHostActionHandling.swift
//  Reader Engine — Contracts
//
//  宿主动作注入点：引擎菜单上存在若干「点了要跳到宿主页面」的入口。
//
//  设计原则：引擎只报「用户点了什么 + 当前读到哪」，**不组装业务模型、不做跳转**。
//  例如反馈入口，若由引擎组装业务参数（封面 URL、书名、业务编码等），就不得不持有
//  业务 ViewModel；改为引擎只传章节定位，接入方自己取书籍元信息并跳转。
//

import UIKit

/// 当前阅读位置的中立描述，供宿主组装自己的业务参数。
public struct ReaderPositionContext {
    /// 章节 ID
    public let chapterId: Int
    /// 章节序号（**从 1 开始**的展示用序号，非 priority 原值）
    public let chapterNumber: Int

    public init(chapterId: Int, chapterNumber: Int) {
        self.chapterId = chapterId
        self.chapterNumber = chapterNumber
    }
}

/// 宿主动作能力。各方法均为可选实现，未实现即该入口无响应（宿主应同时隐藏对应按钮）。
public protocol ReaderHostActionHandling: AnyObject {

    /// 用户在阅读菜单点击「反馈」。
    ///
    /// - Parameters:
    ///   - reader: 发起的阅读器控制器，供宿主做 push / present
    ///   - position: 当前阅读位置
    func readerDidRequestFeedback(_ reader: UIViewController, at position: ReaderPositionContext)

    /// 用户在目录抽屉点击书籍信息，请求跳转书籍详情页。
    ///
    /// 宿主完成选章后通过 `onChapterPicked` 回传章节 ID，引擎据此跳转。
    /// 本项目当前该入口已禁用，故默认空实现即可。
    func readerDidRequestBookInfo(_ reader: UIViewController,
                                 onChapterPicked: @escaping (Int) -> Void)

    /// 询问导航栈中的某个控制器是否应在阅读器打开后被移除。
    ///
    /// 场景：从书籍详情页进入阅读器后，详情页通常要从栈里摘掉，避免返回时又回到详情页。
    /// 「哪种页面算详情页」是业务判断，故交给宿主。
    ///
    /// - Returns: `true` 表示引擎将其从导航栈移除
    func reader(_ reader: UIViewController, shouldRemoveFromStack viewController: UIViewController) -> Bool
}

extension ReaderHostActionHandling {

    public func readerDidRequestFeedback(_ reader: UIViewController, at position: ReaderPositionContext) {}

    public func readerDidRequestBookInfo(_ reader: UIViewController,
                                 onChapterPicked: @escaping (Int) -> Void) {}

    public func reader(_ reader: UIViewController, shouldRemoveFromStack viewController: UIViewController) -> Bool {
        false
    }
}
