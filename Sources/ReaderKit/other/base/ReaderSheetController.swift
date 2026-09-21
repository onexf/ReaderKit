//
//  ReaderSheetController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/19.
//

import UIKit

// 左边上一页点击区域
private let LeftWidth: CGFloat = ReaderScreenMetrics.screenWidth / 3

// 右边下一页点击区域
private let RightWidth: CGFloat = ReaderScreenMetrics.screenWidth / 3

@objc public protocol ReaderSheetControllerDelegate: NSObjectProtocol {
    
    /// 获取上一页
    @objc optional func pageViewController(_ pageViewController: ReaderSheetController, getViewControllerBefore viewController: UIViewController!)
    
    /// 获取下一页
    @objc optional func pageViewController(_ pageViewController: ReaderSheetController, getViewControllerAfter viewController: UIViewController!)
}

open class ReaderSheetController: UIPageViewController, UIGestureRecognizerDelegate {

    // 自定义tap手势的相关代理
    open weak var aDelegate: ReaderSheetControllerDelegate?
    
    // 自定义Tap手势
    public private(set) var customTapGestureRecognizer: UITapGestureRecognizer!
    
    // Whether a tap-triggered page transition is in progress (prevents rapid-tap overlap)
    private var isTapAnimating: Bool = false
    
    // Whether setViewControllers was called during the current tap handling (animation will manage reset)
    private var didStartTransition: Bool = false
    
    // Internal scrollView reference (UIPageViewController .scroll style uses a UIScrollView internally)
    private weak var internalScrollView: UIScrollView?
    
    // Safety timer to reset isTapAnimating if completion block is never called
    private var animationSafetyTimer: Timer?
    
    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        tapGestureRecognizerEnabled = false
        
        customTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(touchTap(tap:)))

        customTapGestureRecognizer.delegate = self

        view.addGestureRecognizer(customTapGestureRecognizer)
        
        // Find the internal UIScrollView for later use
        ensurePrivateScrollView()
    }
    
    /// 查找并缓存 UIPageViewController 内部的 UIScrollView（.scroll 样式下存在）。
    /// 幂等：已找到则跳过。
    private func ensurePrivateScrollView() {
        guard internalScrollView == nil else { return }
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView {
                internalScrollView = scrollView
                break
            }
        }
    }
    
    /// 让内部横向翻页手势在给定手势成功识别前保持等待（require to fail）。
    /// 用于左右翻页模式下把屏幕左边缘让给"退出/返回"边缘手势，其余区域仍正常翻页。
    /// - Note: pageCurl（仿真）样式无内部 scrollView，此调用不产生任何效果。
    open func requirePageScrollToFail(_ gesture: UIGestureRecognizer) {
        ensurePrivateScrollView()
        internalScrollView?.panGestureRecognizer.require(toFail: gesture)
    }
    
    /// 暂停 / 恢复【滑动】翻页。菜单呼出期间由 `ReaderMenu.presentDropdown` 调用。
    ///
    /// 只关内部 pan 手势，**不动 `isScrollEnabled`、也不动 `isUserInteractionEnabled`**：
    /// 菜单开着时上一章 / 下一章 / 拖进度条都会走 `setViewControllers(animated:)`，
    /// 那条路径依赖内部 scrollView 的偏移动画，把 scrollView 整体关掉会一起废掉它。
    /// 关 pan 只拦用户拖动，程序驱动的翻页不受影响。
    ///
    /// 点击翻页不在这里管 —— 它是本类自己的 `customTapGestureRecognizer`，
    /// 在 `gestureRecognizer(_:shouldReceive:)` 里按菜单状态拒掉。
    open func suspendPageTurn(_ isSuspended: Bool) {
        ensurePrivateScrollView()
        internalScrollView?.panGestureRecognizer.isEnabled = !isSuspended
    }
    
    /// 菜单是否正呼出。
    ///
    /// 向上问宿主而不是自己存一个标志位：`isMenuShow` 是唯一事实来源，
    /// 存副本就要考虑两边什么时候同步，菜单被别的路径收起时副本就脏了。
    private var isReaderMenuShowing: Bool {
        (parent as? ReaderViewController)?.readMenu?.isMenuShow == true
    }
    
    open override func didMove(toParent parent: UIViewController?) {
        
        super.didMove(toParent: parent)
        
        // 这个容器会【在菜单呼出期间被重建】—— 改字号、改行距、换主题、换阅读模式都会重建。
        // 新建出来的内部 pan 默认是开的，不在这里补一次的话：改完字号菜单还开着，
        // 却又能滑动翻页了。`viewDidLoad` 里做不了，那时 parent 还没挂上。
        suspendPageTurn(isReaderMenuShowing)
    }
    
    /// Override to track animation completion for tap-triggered transitions
    open override func setViewControllers(_ viewControllers: [UIViewController]?, direction: UIPageViewController.NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        
        if isTapAnimating && animated {
            didStartTransition = true
            // Disable user interaction on internal scrollView during animation to prevent
            // touch events from interrupting the ongoing scroll animation (causes "bounce back" glitch)
            internalScrollView?.isUserInteractionEnabled = false
            
            // Safety timer: if completion is never called (e.g., animation interrupted by another
            // setViewControllers call), force-reset state after a reasonable timeout
            animationSafetyTimer?.invalidate()
            animationSafetyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.isTapAnimating {
                    self.internalScrollView?.isUserInteractionEnabled = true
                    self.isTapAnimating = false
                }
            }
            
            super.setViewControllers(viewControllers, direction: direction, animated: true) { [weak self] finished in
                guard let self = self else { return }
                self.animationSafetyTimer?.invalidate()
                self.animationSafetyTimer = nil
                self.internalScrollView?.isUserInteractionEnabled = true
                self.isTapAnimating = false
                completion?(finished)
            }
        } else {
            super.setViewControllers(viewControllers, direction: direction, animated: animated, completion: completion)
        }
    }
    
    // tap事件
    @objc open func touchTap(tap: UIGestureRecognizer) {
        
        // Prevent rapid taps from triggering multiple simultaneous page transitions
        guard !isTapAnimating else { return }
        
        // On END page, only respond to taps in the top blank area (above recommend list)
        if let endVC = viewControllers?.first as? ReaderTerminalPageController {
            let touchPoint = tap.location(in: view)
            // Check if tap is in the recommend content area (below the top blank zone)
            let touchInEndVC = tap.location(in: endVC.view)
            if endVC.isPressInSuggestContentZone(touchInEndVC) {
                // Let taps pass through to recommendation view
                return
            }
            // Top blank area: left 1/3 triggers previous page (go back)
            if touchPoint.x < LeftWidth {
                isTapAnimating = true
                didStartTransition = false
                aDelegate?.pageViewController?(self, getViewControllerBefore: viewControllers?.first)
                if !didStartTransition {
                    isTapAnimating = false
                }
            }
            // Middle 1/3 is handled by ReaderMenu's singleTap (menu toggle)
            // Right 1/3 does nothing on END page (no next page)
            return
        }
        
        let touchPoint = tap.location(in: view)
        
        if (touchPoint.x < LeftWidth) { // 左边
            
            isTapAnimating = true
            didStartTransition = false
            aDelegate?.pageViewController?(self, getViewControllerBefore: viewControllers?.first)
            // If delegate didn't call setViewControllers (no previous page / locked chapter), reset immediately
            if !didStartTransition {
                isTapAnimating = false
            }
            
        }else if (touchPoint.x > (ReaderScreenMetrics.screenWidth - RightWidth)) { // 右边
            
            isTapAnimating = true
            didStartTransition = false
            aDelegate?.pageViewController?(self, getViewControllerAfter: viewControllers?.first)
            // If delegate didn't call setViewControllers (no next page / locked chapter), reset immediately
            if !didStartTransition {
                isTapAnimating = false
            }
        }
    }
    
    // MARK: UIGestureRecognizerDelegate
    
    /// Prevent tap gesture from recognizing on END page recommend content area so touches pass through
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer.isEqual(customTapGestureRecognizer) {
            // 菜单呼出期间不点击翻页 —— 这一下点击归菜单，语义是「先收起菜单」。
            //
            // 拦在这里而不是让遮罩吃掉触摸：遮罩铺满整屏，一旦参与命中测试就会连带
            // 掐掉这块区域上的其他手势。这里只拒本类的点击手势，其余照常。
            if isReaderMenuShowing { return false }
            
            if let endVC = viewControllers?.first as? ReaderTerminalPageController {
                // Allow tap in top blank area (above recommend list), block in recommend content area
                let touchPoint = touch.location(in: endVC.view)
                return !endVC.isPressInSuggestContentZone(touchPoint)
            }
        }
        return true
    }
    
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if (gestureRecognizer.isKind(of: UITapGestureRecognizer.classForCoder()) && gestureRecognizer.isEqual(customTapGestureRecognizer)) {

            // On END page top blank area, allow middle 1/3 to trigger menu simultaneously
            if let endVC = viewControllers?.first as? ReaderTerminalPageController {
                let touchPoint = customTapGestureRecognizer.location(in: endVC.view)
                if !endVC.isPressInSuggestContentZone(touchPoint) {
                    let tapX = customTapGestureRecognizer.location(in: view).x
                    if tapX > LeftWidth && tapX < (ReaderScreenMetrics.screenWidth - RightWidth) {
                        return true
                    }
                }
                return false
            }

            let touchPoint = customTapGestureRecognizer.location(in: view)

            if (touchPoint.x > LeftWidth && touchPoint.x < (ReaderScreenMetrics.screenWidth - RightWidth)) {

                return true
            }
        }

        return false
    }
}
