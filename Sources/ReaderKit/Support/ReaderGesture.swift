//
//  ReaderGesture.swift
//  ReaderKit
//
//  Created by Asuna on 2026/09/24.
//

import UIKit
import ObjectiveC

// 关联对象的 key。只用变量的**地址**，值是什么无所谓，所以用 `UInt8` 而不是 `String`
// —— 字符串字面量会白白留在二进制的 __cstring 里。同 `UIPageViewController+Extension`。
private nonisolated(unsafe) var gestureHandlerKey: UInt8 = 0

/// 手势的闭包入口，替掉 `target:action:` + `@objc` 那一套。
///
/// ```swift
/// addGestureRecognizer(ReaderGesture.tap { [weak self] _ in self?.onTap?() })
/// ```
///
/// ⚠️ **闭包一律写 `[weak self]`。** 视图持手势、手势持闭包（见 `hold`），闭包再强持
/// 视图就成环，而泄漏是静默的：页面不析构，它挂的通知与音频会话跟着一起留下。
/// 原先 `target: self` 那套不会环，是因为 target-action 从不强持 target ——
/// 换成闭包就没有这层天然保护了。
enum ReaderGesture {

    static func tap(_ handler: @escaping (UITapGestureRecognizer) -> Void) -> UITapGestureRecognizer {
        let gesture = UITapGestureRecognizer()
        observe(gesture, with: handler)
        return gesture
    }

    static func longPress(_ handler: @escaping (UILongPressGestureRecognizer) -> Void) -> UILongPressGestureRecognizer {
        let gesture = UILongPressGestureRecognizer()
        observe(gesture, with: handler)
        return gesture
    }

    static func pan(_ handler: @escaping (UIPanGestureRecognizer) -> Void) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        observe(gesture, with: handler)
        return gesture
    }

    /// 往**别人的**手势上追加一个闭包回调，`addTarget(_:action:)` 的闭包版。
    ///
    /// 用于 `UIPageViewController` 内部 scrollView 的 pan 这类不归自己所有的手势：
    /// 同一个手势可以挂多个回调，彼此互不影响。
    static func observe<G: UIGestureRecognizer>(_ gesture: G, with handler: @escaping (G) -> Void) {
        let trampoline = ReaderGestureTrampoline { sender in
            // sender 就是下面那个 gesture，转换不可能失败
            guard let sender = sender as? G else { return }
            handler(sender)
        }
        gesture.addTarget(trampoline, action: ReaderGestureTrampoline.invokeAction)
        hold(trampoline, on: gesture)
    }

    /// 让手势持住蹦床。
    ///
    /// **这一步不能省。** target-action 不强持 target，蹦床要是只被局部变量引用，
    /// 出了作用域当场析构，手势从此一声不响地不再回调 —— 不崩、不报错，就是没反应。
    /// 用数组而不是单槽位，是因为 `observe` 可以往同一个手势上挂第二个回调。
    private static func hold(_ trampoline: ReaderGestureTrampoline, on gesture: UIGestureRecognizer) {
        var holders = objc_getAssociatedObject(gesture, &gestureHandlerKey) as? [ReaderGestureTrampoline] ?? []
        holders.append(trampoline)
        objc_setAssociatedObject(gesture, &gestureHandlerKey, holders, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// selector 的唯一落点：手势相关的 `@objc` 全库只剩这一个，且它与自己的 `#selector`
/// 就在同一屏里，改名立刻编译报错。
private final class ReaderGestureTrampoline: NSObject {

    private let handler: (UIGestureRecognizer) -> Void

    init(_ handler: @escaping (UIGestureRecognizer) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc fileprivate func invoke(_ gesture: UIGestureRecognizer) { handler(gesture) }

    static var invokeAction: Selector { #selector(ReaderGestureTrampoline.invoke(_:)) }
}
