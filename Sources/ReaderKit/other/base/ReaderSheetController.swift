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

/// 翻页的方向。
public enum ReaderPageDragDirection {
    /// 往后翻（下一页 / 下一章）。手指往左推。
    case forward
    /// 往前翻（上一页 / 上一章）。手指往右推。
    case backward
}

/// 点击左右两侧区域翻页的回调。
///
/// **不是 `UIPageViewControllerDataSource` 的替代品。** 这里只报「用户点了哪一侧」，
/// 翻不翻、翻到哪由接入方决定并自己调 `setViewControllers`。点击不走数据源，是因为
/// 数据源返回 nil 时容器只会静静不动，而点击必须有反馈（邻章没缓存要下载）。
public protocol ReaderSheetControllerDelegate: AnyObject {

    /// 用户点了左侧三分之一 —— 想往前翻一页。
    func sheetControllerDidRequestPreviousPage(_ sheetController: ReaderSheetController)

    /// 用户点了右侧三分之一 —— 想往后翻一页。
    func sheetControllerDidRequestNextPage(_ sheetController: ReaderSheetController)
}

open class ReaderSheetController: UIPageViewController, UIGestureRecognizerDelegate {

    /// 点击翻页的代理。`delegate` / `dataSource` 归 UIPageViewController，所以另起一个名。
    open weak var pageTapDelegate: (any ReaderSheetControllerDelegate)?
    
    // 自定义Tap手势
    public private(set) var pageTapRecognizer: UITapGestureRecognizer!
    
    // Whether a tap-triggered page transition is in progress (prevents rapid-tap overlap)
    private var tapTurnInFlight: Bool = false
    
    // Whether setViewControllers was called during the current tap handling (animation will manage reset)
    private var transitionInFlight: Bool = false
    
    // Internal scrollView reference (UIPageViewController .scroll style uses a UIScrollView internally)
    private weak var hostedScrollView: UIScrollView?
    
    // Safety timer to reset tapTurnInFlight if completion block is never called
    private var transitionWatchdog: Timer?
    
    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        tapGestureRecognizerEnabled = false
        
        pageTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handlePageTap(tap:)))

        pageTapRecognizer.delegate = self

        view.addGestureRecognizer(pageTapRecognizer)
        
        // Find the internal UIScrollView for later use
        ensurePrivateScrollView()
        observePageDrag()
    }
    
    open override func viewDidLayoutSubviews() {
        
        super.viewDidLayoutSubviews()
        
        // ⚠️ **内部 scrollView 的发现必须放在这里，不能只靠 `viewDidLoad`。**
        //
        // UIPageViewController 是**懒建**那个 scrollView 的：`viewDidLoad` 和
        // `didMove(toParent:)` 都早于第一次 `setViewControllers`，那两个时机它通常还不存在。
        // 只在早期找一次的后果是 `hostedScrollView` 恒为 nil —— 于是拖动监听挂不上、
        // `onPageDragEnded` 一次都不回调，而这**不会报错**，只表现为「滑动没反应」。
        //
        // 布局之后它一定有了。两个方法都幂等，重复调只有第一次有成本。
        ensurePrivateScrollView()
        observePageDrag()
    }
    
    /// 查找并缓存 UIPageViewController 内部的 UIScrollView（.scroll 样式下存在）。
    /// 幂等：已找到则跳过。
    private func ensurePrivateScrollView() {
        guard hostedScrollView == nil else { return }
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView {
                hostedScrollView = scrollView
                break
            }
        }
    }
    
    /// 让内部横向翻页手势在给定手势成功识别前保持等待（require to fail）。
    /// 用于左右翻页模式下把屏幕左边缘让给"退出/返回"边缘手势，其余区域仍正常翻页。
    /// - Note: pageCurl（仿真）样式无内部 scrollView，此调用不产生任何效果。
    open func requirePageScrollToFail(_ gesture: UIGestureRecognizer) {
        ensurePrivateScrollView()
        hostedScrollView?.panGestureRecognizer.require(toFail: gesture)
    }
    
    /// 用户拖动结束时回调，带上「想往哪翻」。
    ///
    /// ## 为什么需要它
    ///
    /// `UIPageViewControllerDataSource` 返回 nil 时，UIPageViewController **只是不让翻，
    /// 不会告诉任何人用户试过**。于是「邻章还没下载」这种情况下滑动就是死路：橡皮筋弹回来，
    /// 没有任何反馈。而点击翻页有 `pageTapDelegate` 那条路可以兜底。
    /// 接入方拿这个回调把滑动也接到同一个兜底实现上。
    ///
    /// ## 只报方向，「容器接手了没有」由接入方自己判
    ///
    /// **接入方必须用 `pageViewControllerDelegate` 的
    /// `pageViewController(_:willTransitionTo:)` 来判断**：容器一旦开始转场就会调它，
    /// 从没调过就说明那个方向真的没有页。收到本回调时若本次手势期间有过 `willTransitionTo`，
    /// 什么都别做 —— 容器自己在翻，插手会打架。
    ///
    /// ⚠️ **不要试图用内部 scrollView 的几何量判断。** 试过两版都不成立：
    ///
    /// - 「offset 偏离一页宽」—— 静止 offset 只在前后都有页时才等于一页宽，缺一侧时是 0。
    /// - 「offset 越出 contentSize 范围（橡皮筋）」—— 真机数据显示往前拖时它恒为真，
    ///   即使前面明明有页、容器也确实翻过去了（3 页窗口、静止 offset 居中的情况下）。
    ///
    /// 容器内部怎么摆放那三页、什么时候重新居中都是未文档化的，靠它反推状态不可靠。
    open var onPageDragEnded: ((ReaderPageDragDirection) -> Void)?
    
    /// 方向判定的位移阈值。小于它的当抖动忽略。
    private static let dragDirectionThreshold: CGFloat = 20
    
    /// 是否已经挂上拖动监听。
    private var isObservingPageDrag = false
    
    /// 监听内部横向 pan 的结束。
    ///
    /// **往【已有】手势上挂一个 target，不要去换 `scrollView.delegate`** ——
    /// UIPageViewController 自己就是那个 delegate，换掉它等于把容器的翻页记账拆了
    /// （它靠那些回调驱动自己的转场与 `didFinishAnimating`）。
    /// 同一个手势可以有多个 target，彼此互不影响，这条是文档化的行为。
    private func observePageDrag() {
        
        guard !isObservingPageDrag else { return }
        
        ensurePrivateScrollView()
        guard let pan = hostedScrollView?.panGestureRecognizer else { return }
        
        pan.addTarget(self, action: #selector(handlePageDrag(_:)))
        isObservingPageDrag = true
    }
    
    @objc private func handlePageDrag(_ pan: UIPanGestureRecognizer) {
        
        guard pan.state == .ended, let onPageDragEnded else { return }
        
        // 只判方向，不判「翻过去了没有」—— 那件事交给接入方看 `willTransitionTo`，
        // 理由写在 `onPageDragEnded` 的文档上（几何量判据试过两版都不成立）。
        //
        // 手指往左推 = 想往后翻（forward）。
        let translationX = pan.translation(in: view).x
        guard abs(translationX) > Self.dragDirectionThreshold else { return }
        
        onPageDragEnded(translationX < 0 ? .forward : .backward)
    }
    
    /// 暂停 / 恢复【滑动】翻页。菜单呼出期间由 `ReaderMenu.presentDropdown` 调用。
    ///
    /// 只关内部 pan 手势，**不动 `isScrollEnabled`、也不动 `isUserInteractionEnabled`**：
    /// 菜单开着时上一章 / 下一章 / 拖进度条都会走 `setViewControllers(animated:)`，
    /// 那条路径依赖内部 scrollView 的偏移动画，把 scrollView 整体关掉会一起废掉它。
    /// 关 pan 只拦用户拖动，程序驱动的翻页不受影响。
    ///
    /// 点击翻页不在这里管 —— 它是本类自己的 `pageTapRecognizer`，
    /// 在 `gestureRecognizer(_:shouldReceive:)` 里按菜单状态拒掉。
    open func suspendPageTurn(_ isSuspended: Bool) {
        ensurePrivateScrollView()
        hostedScrollView?.panGestureRecognizer.isEnabled = !isSuspended
    }
    
    /// 菜单是否正呼出。
    ///
    /// 向上问宿主而不是自己存一个标志位：`isMenuVisible` 是唯一事实来源，
    /// 存副本就要考虑两边什么时候同步，菜单被别的路径收起时副本就脏了。
    private var isReaderMenuShowing: Bool {
        (parent as? ReaderViewController)?.hostMenu?.isMenuVisible == true
    }
    
    open override func didMove(toParent parent: UIViewController?) {
        
        super.didMove(toParent: parent)
        
        // 这个容器会【在菜单呼出期间被重建】—— 改字号、改行距、换主题、换阅读模式都会重建。
        // 新建出来的内部 pan 默认是开的，不在这里补一次的话：改完字号菜单还开着，
        // 却又能滑动翻页了。`viewDidLoad` 里做不了，那时 parent 还没挂上。
        suspendPageTurn(isReaderMenuShowing)
        // 内部 scrollView 在 `viewDidLoad` 时可能还没建出来，补挂一次（幂等）。
        observePageDrag()
    }
    
    /// Override to track animation completion for tap-triggered transitions
    open override func setViewControllers(_ viewControllers: [UIViewController]?, direction: UIPageViewController.NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        
        if tapTurnInFlight && animated {
            transitionInFlight = true
            // Disable user interaction on internal scrollView during animation to prevent
            // touch events from interrupting the ongoing scroll animation (causes "bounce back" glitch)
            hostedScrollView?.isUserInteractionEnabled = false
            
            // Safety timer: if completion is never called (e.g., animation interrupted by another
            // setViewControllers call), force-reset state after a reasonable timeout
            transitionWatchdog?.invalidate()
            transitionWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.tapTurnInFlight {
                    self.hostedScrollView?.isUserInteractionEnabled = true
                    self.tapTurnInFlight = false
                }
            }
            
            super.setViewControllers(viewControllers, direction: direction, animated: true) { [weak self] finished in
                guard let self = self else { return }
                self.transitionWatchdog?.invalidate()
                self.transitionWatchdog = nil
                self.hostedScrollView?.isUserInteractionEnabled = true
                self.tapTurnInFlight = false
                completion?(finished)
            }
        } else {
            super.setViewControllers(viewControllers, direction: direction, animated: animated, completion: completion)
        }
    }
    
    // tap事件
    @objc open func handlePageTap(tap: UIGestureRecognizer) {
        
        // Prevent rapid taps from triggering multiple simultaneous page transitions
        guard !tapTurnInFlight else { return }
        
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
                tapTurnInFlight = true
                transitionInFlight = false
                pageTapDelegate?.sheetControllerDidRequestPreviousPage(self)
                if !transitionInFlight {
                    tapTurnInFlight = false
                }
            }
            // Middle 1/3 is handled by ReaderMenu's singleTap (menu toggle)
            // Right 1/3 does nothing on END page (no next page)
            return
        }
        
        let touchPoint = tap.location(in: view)
        
        if (touchPoint.x < LeftWidth) { // 左边
            
            tapTurnInFlight = true
            transitionInFlight = false
            pageTapDelegate?.sheetControllerDidRequestPreviousPage(self)
            // If delegate didn't call setViewControllers (no previous page / locked chapter), reset immediately
            if !transitionInFlight {
                tapTurnInFlight = false
            }
            
        }else if (touchPoint.x > (ReaderScreenMetrics.screenWidth - RightWidth)) { // 右边
            
            tapTurnInFlight = true
            transitionInFlight = false
            pageTapDelegate?.sheetControllerDidRequestNextPage(self)
            // If delegate didn't call setViewControllers (no next page / locked chapter), reset immediately
            if !transitionInFlight {
                tapTurnInFlight = false
            }
        }
    }
    
    // MARK: UIGestureRecognizerDelegate
    
    /// Prevent tap gesture from recognizing on END page recommend content area so touches pass through
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer.isEqual(pageTapRecognizer) {
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

        if (gestureRecognizer.isKind(of: UITapGestureRecognizer.classForCoder()) && gestureRecognizer.isEqual(pageTapRecognizer)) {

            // On END page top blank area, allow middle 1/3 to trigger menu simultaneously
            if let endVC = viewControllers?.first as? ReaderTerminalPageController {
                let touchPoint = pageTapRecognizer.location(in: endVC.view)
                if !endVC.isPressInSuggestContentZone(touchPoint) {
                    let tapX = pageTapRecognizer.location(in: view).x
                    if tapX > LeftWidth && tapX < (ReaderScreenMetrics.screenWidth - RightWidth) {
                        return true
                    }
                }
                return false
            }

            let touchPoint = pageTapRecognizer.location(in: view)

            if (touchPoint.x > LeftWidth && touchPoint.x < (ReaderScreenMetrics.screenWidth - RightWidth)) {

                return true
            }
        }

        return false
    }
}
