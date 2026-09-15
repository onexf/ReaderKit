//
//  ReaderTerminalPage.swift
//  Reader Engine — Contracts
//
//  书末页注入点：正文读完后展示的终止页。
//  引擎负责把它接入翻页流程与手势判定，具体内容（推荐位、运营位等）由宿主提供。
//

import UIKit

/// 书末页需要向引擎暴露的能力。
///
/// 引擎对书末页的全部诉求只有两项：命中测试与主题刷新。
/// 页面长什么样、加载什么数据，引擎一概不感知。
public protocol ReaderTerminalPage: AnyObject {

    /// 命中测试：`point` 是否落在宿主的自定义内容区内（例如书末推荐列表）。
    ///
    /// - 返回 `true`：引擎放行该次点击，交给宿主视图自己处理，不弹阅读菜单。
    /// - 返回 `false`：视为点在空白区，走引擎默认的菜单唤起逻辑。
    ///
    /// - Parameter point: 已换算到本页 `view` 坐标系下的触点。
    func isPressInSuggestContentZone(_ point: CGPoint) -> Bool

    /// 主题切换后刷新外观。
    ///
    /// 引擎在重建翻页容器（改字号/行距/主题）后调用，宿主据此重新取色。
    func adoptActiveTheme()
}

/// 书末页控制器：既是 `UIViewController`（引擎需要它参与翻页与坐标换算），
/// 又满足 `ReaderTerminalPage`。
public typealias ReaderTerminalPageController = UIViewController & ReaderTerminalPage

/// 书末页工厂。由宿主实现并注入，引擎借此创建书末页而不引用任何业务类型。
public protocol ReaderTerminalPageProviding: AnyObject {

    /// 创建书末页。
    ///
    /// - Parameter reader: 发起创建的阅读器控制器，供宿主建立回引（如取共享 ViewModel）。
    /// - Returns: 书末页控制器。引擎会缓存复用，避免重复拉取数据。
    func makeTerminalPage(reader: UIViewController) -> ReaderTerminalPageController
}
