//
//  ReaderMenu.swift
//  ReaderKit
//
//  Created by Asuna on 2025/08/28.
//

import UIKit

/// 阅读菜单的宿主回调。
///
/// 菜单的界面全在库内，宿主只回答「点了之后做什么」。
///
/// 所有方法都在协议扩展里给了空默认实现，按需覆盖即可 —— 代价和过去的
/// `@objc optional` 一样：**签名写错不会报错，只会静默走默认实现**。接入时对照本协议
/// 逐项确认，不要靠「点了没反应」来发现漏接。
public protocol ReaderMenuDelegate: AnyObject {

    // MARK: 菜单显隐

    func readerMenuWillPresent(_ menu: ReaderMenu)
    func readerMenuDidPresent(_ menu: ReaderMenu)
    func readerMenuWillDismiss(_ menu: ReaderMenu)
    func readerMenuDidDismiss(_ menu: ReaderMenu)

    // MARK: 顶栏

    func readerMenuDidTapBack(_ menu: ReaderMenu)
    func readerMenuDidTapAddToBookshelf(_ menu: ReaderMenu)
    func readerMenuDidTapFeedback(_ menu: ReaderMenu)

    // MARK: 章节导航

    func readerMenuDidTapCatalogue(_ menu: ReaderMenu)
    func readerMenuDidTapPreviousChapter(_ menu: ReaderMenu)
    func readerMenuDidTapNextChapter(_ menu: ReaderMenu)

    /// 进度条拖到本章某一页。
    func readerMenu(_ menu: ReaderMenu, didSeekToPage page: Int)

    /// 进度条跨章拖动（全书进度模式）。
    func readerMenu(_ menu: ReaderMenu, didSeekToChapter chapterID: Int, page: Int)

    // MARK: 排版与主题

    /// 阅读主题变更。**日夜切换最终也走这里** —— 库内自己改主题索引，改完回调本方法，
    /// 所以宿主只需要在这一处做主题重刷。
    func readerMenuDidChangeTheme(_ menu: ReaderMenu)

    func readerMenuDidChangeFontSize(_ menu: ReaderMenu)
    func readerMenuDidChangeLineHeight(_ menu: ReaderMenu)

    /// 阅读模式变更（左右翻页 ↔ 上下滚动）。
    func readerMenuDidChangeReadingMode(_ menu: ReaderMenu)
}

public extension ReaderMenuDelegate {

    func readerMenuWillPresent(_ menu: ReaderMenu) {}
    func readerMenuDidPresent(_ menu: ReaderMenu) {}
    func readerMenuWillDismiss(_ menu: ReaderMenu) {}
    func readerMenuDidDismiss(_ menu: ReaderMenu) {}

    func readerMenuDidTapBack(_ menu: ReaderMenu) {}
    func readerMenuDidTapAddToBookshelf(_ menu: ReaderMenu) {}
    func readerMenuDidTapFeedback(_ menu: ReaderMenu) {}

    func readerMenuDidTapCatalogue(_ menu: ReaderMenu) {}
    func readerMenuDidTapPreviousChapter(_ menu: ReaderMenu) {}
    func readerMenuDidTapNextChapter(_ menu: ReaderMenu) {}

    func readerMenu(_ menu: ReaderMenu, didSeekToPage page: Int) {}
    func readerMenu(_ menu: ReaderMenu, didSeekToChapter chapterID: Int, page: Int) {}

    func readerMenuDidChangeTheme(_ menu: ReaderMenu) {}
    func readerMenuDidChangeFontSize(_ menu: ReaderMenu) {}
    func readerMenuDidChangeLineHeight(_ menu: ReaderMenu) {}
    func readerMenuDidChangeReadingMode(_ menu: ReaderMenu) {}
}

open class ReaderMenu: NSObject, UIGestureRecognizerDelegate {

    /// 控制器
    /// 阅读器控制器。
    ///
    /// 类型为引擎基类而非具体子类：菜单只用到 `contentView` / `bookModel` / `view` /
    /// `pageViewController` 这几个引擎成员，不需要感知宿主子类的业务字段。
    public private(set) weak var vc: ReaderViewController!
    
    /// 阅读主视图
    public private(set) weak var contentView: ReaderContentView!
    
    /// 代理
    public private(set) weak var delegate: ReaderMenuDelegate?
    
    /// 菜单显示状态
    open var isMenuShow: Bool = false
    
    /// 单击手势
    public private(set) var singleTap: UITapGestureRecognizer!
    
    /// 收起菜单的滑动手势。
    ///
    /// 菜单呼出期间在半透明区域**拖动**也要能收起菜单，不只是点一下。
    /// 只在 `isMenuShow` 为真时才允许开始（见 `gestureRecognizerShouldBegin`），
    /// 菜单没呼出时它立刻失败，不参与正常的翻页 / 滚动。
    public private(set) var dismissPan: UIPanGestureRecognizer!
    
    /// TopView
    public private(set) var topView: ReaderMenuTopBar!
    
    /// BottomView
    public private(set) var bottomBar: ReaderMenuBottomBar!
    
    /// 目录背景遮罩
    public private(set) var catalogueBackdrop: UIView!
    
    /// 呼出菜单遮罩(设计稿:压在正文之上、顶部栏/底部栏之下,浅色主题 60% 黑、夜间 80% 黑)
    public private(set) var menuBackdrop: UIView!
    
    /// 底部目录视图
    private var catalogueDrawer: ReaderCatalogueView!
    
    /// 日夜间遮盖
    public private(set) var nightTint: UIView!
    
    /// 禁用系统初始化
    private override init() { super.init() }
    
    /// 初始化
    public convenience init(vc: ReaderViewController!, delegate: ReaderMenuDelegate?) {
        
        self.init()
        
        // 记录
        self.vc = vc
        self.contentView = vc.contentView
        self.delegate = delegate
        
        // 允许获取电量信息
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // 添加单机手势
        initPressSwipeRecognizer()
        
        // 初始化日夜间遮盖
        initOverlay()
        
        // 初始化目录背景遮罩
        initCatalogBackdrop()
        
        // 初始化底部目录视图
        initBaseCatalogView()
        
        // 初始化呼出菜单遮罩(必须在 TopView / BottomView 之前,保证层级在菜单栏之下)
        initMenuBackdrop()
        
        // 初始化TopView
        initPeakView()
        
        // 初始化BottomView
        initBaseView()
    }
    
    // MARK: -- 添加单机手势
    
    /// 添加单机手势
    private func initPressSwipeRecognizer() {
        
        // 单击手势
        singleTap = UITapGestureRecognizer(target: self, action: #selector(handleMenuTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.delegate = self
        vc.contentView.addGestureRecognizer(singleTap)
        
        // 收起菜单的滑动手势
        dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleMenuDismissDrag))
        dismissPan.delegate = self
        // 只负责"发现有人在这块区域拖动",不吞触摸 —— 侧滑返回、滚动模式的正文滚动
        // 都还要照常收到这一串触摸。
        dismissPan.cancelsTouchesInView = false
        vc.contentView.addGestureRecognizer(dismissPan)
    }
    
    // 触发单击手势
    @objc private func handleMenuTap() {
        
        // 如果内容还未加载完成，不显示菜单
        guard vc.bookModel != nil else {
            // log("⚠️ touchSingleTap: readModel 为 nil，内容尚未加载，不显示菜单")
            return
        }
        
        // 滚动模式下，只有屏幕中间1/3区域点击才唤起菜单
        //
        // 这条限制只管【唤起】。菜单已经呼出时任意位置点一下都要能收起 ——
        // 此时正文被遮罩盖着，用户点的是遮罩，语义就是「关掉菜单」，
        // 再按左右 1/3 判一次的话点两侧会毫无反应。
        if !isMenuShow, ReaderConfiguration.shared().effectType == .scroll {
            let tapLocation = singleTap.location(in: vc.contentView)
            let viewWidth = vc.contentView.bounds.width
            let leftBoundary = viewWidth / 3.0
            let rightBoundary = viewWidth * 2.0 / 3.0
            
            // 点击在左侧1/3或右侧1/3区域，不响应菜单
            if tapLocation.x < leftBoundary || tapLocation.x > rightBoundary {
                return
            }
        }
        
        presentDropdown(isShow: !isMenuShow)
    }
    
    /// 触发收起菜单的滑动手势
    ///
    /// 只在**开始**拖动的那一下收菜单，不跟手 —— 这是「先收起菜单」而不是「跟着手指拉」。
    /// 收完菜单本次拖动就不再有别的效果：左右翻页的 pan 在菜单呼出时已经被
    /// `suspendPageTurn(true)` 关掉，中途重新打开也不会接管已经开始的这串触摸。
    @objc private func handleMenuDismissDrag() {
        
        guard dismissPan.state == .began, isMenuShow else { return }
        
        presentDropdown(isShow: false)
    }
    
    // MARK: -- UIGestureRecognizerDelegate
    
    /// 收菜单的滑动手势只在菜单呼出时才允许开始。
    ///
    /// 菜单没呼出时返回 false，它立刻进入 failed，不会延迟或干扰翻页 / 滚动手势。
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer === dismissPan { return isMenuShow }
        
        return true
    }
    
    /// 收菜单的滑动手势和谁都能并存。
    ///
    /// 它只是个观察者：不吞触摸、不抢识别权。要是不放开并存，它一旦识别就会把侧滑返回、
    /// 滚动模式的正文滚动一起挤掉 —— 那又变成「整块区域没手势」了。
    open func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        
        return gestureRecognizer === dismissPan || otherGestureRecognizer === dismissPan
    }
    
    /// 手势拦截
    ///
    /// 原先靠类名白名单判断，设置面板的容器是裸 UIView、不在名单里，导致点面板空白处
    /// 会把菜单整个关掉。改成按视图层级判断：落在顶栏/底栏（含它们的任意子视图）里的
    /// 触摸都不触发呼出手势，新增控件不需要再维护名单。
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        guard let touchedView = touch.view else { return true }
        
        if let topView, touchedView.isDescendant(of: topView) { return false }
        
        if let bottomBar, touchedView.isDescendant(of: bottomBar) { return false }
        
        if let catalogueDrawer, touchedView.isDescendant(of: catalogueDrawer) { return false }
        
        // 朗读 dock：整块吞掉点击，不唤起也不收起菜单。
        //
        // 三种情况都靠这一条覆盖：书封（点了本该什么都不做）、进度环与关闭按钮
        // （它们是带 tap 手势的普通 UIView，不是 UIControl，下面那条 UIControl 判断兜不住，
        // 否则点暂停会顺带把菜单收起）。
        if let dock = vc?.installedSpeechDock, touchedView.isDescendant(of: dock) { return false }
        
        if touchedView is UIControl { return false }
        
        // 菜单已经呼出 —— 放行，此时一次点击的语义固定是「收起菜单」。
        //
        // 必须排在下面那些按位置/按页型的判断之前：那些规则是为【唤起】菜单定的
        // （书末页只让顶部空白区的中间 1/3 唤起），拿来管收起会留下死区 ——
        // 点了既不收菜单、又因为翻页已被掐掉而什么都不发生。
        if isMenuShow { return true }
        
        // On END page, only allow menu tap in the top blank area (above recommend content)
        if let endVC = vc.pageViewController?.viewControllers?.first as? ReaderTerminalPageController {
            let touchPoint = touch.location(in: endVC.view)
            if endVC.isPressInSuggestContentZone(touchPoint) {
                return false
            }
            // Top blank area: allow middle 1/3 to trigger menu
            let touchX = touch.location(in: vc.contentView).x
            let viewWidth = vc.contentView.bounds.width
            let leftBoundary = viewWidth / 3.0
            let rightBoundary = viewWidth * 2.0 / 3.0
            if touchX < leftBoundary || touchX > rightBoundary {
                return false
            }
            return true
        }
        
        return true
    }
    
    // MARK: 日夜间遮盖
    
    /// 初始化日夜间遮盖
    private func initOverlay() {
        
        nightTint = UIView()
        nightTint.alpha = CGFloat(NSNumber(value: ReaderDefaults.bool(READER_KEY_MODE_DAY_NIGHT)).floatValue)
        nightTint.isUserInteractionEnabled = false
        nightTint.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        vc.view.addSubview(nightTint)
        nightTint.frame = vc.view.bounds
    }
    
    // MARK: 目录背景遮罩
    
    /// 初始化目录背景遮罩
    private func initCatalogBackdrop() {
        catalogueBackdrop = UIView()
        // 目录背景蒙版：黑色 60% 透明（原 .cover1，改用引擎自有色值以脱离宿主 UIColor 扩展）
        catalogueBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        catalogueBackdrop.isHidden = true
        contentView.addSubview(catalogueBackdrop)
        // 遮罩撑满整个contentView
        catalogueBackdrop.frame = CGRect(x: 0, y: 0, width: READER_CONTENT_VIEW_WIDTH, height: READER_CONTENT_VIEW_HEIGHT)
        
        // 添加点击手势关闭目录
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissCatalogueFromBackdrop))
        catalogueBackdrop.addGestureRecognizer(tapGesture)
    }
    
    @objc private func dismissCatalogueFromBackdrop() {
        // log("🔥 handleCatalogBackgroundTap called")
        // 关闭底部目录
        concealBaseCatalog()
    }
    
    /// 显示/隐藏目录背景遮罩
    open func presentCatalogBackdrop(isShow: Bool, animated: Bool = true) {
        if isShow {
            catalogueBackdrop.isHidden = false
            if animated {
                catalogueBackdrop.alpha = 0
                UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS) {
                    self.catalogueBackdrop.alpha = 1
                }
            } else {
                catalogueBackdrop.alpha = 1
            }
        } else {
            if animated {
                UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: {
                    self.catalogueBackdrop.alpha = 0
                }) { _ in
                    self.catalogueBackdrop.isHidden = true
                }
            } else {
                catalogueBackdrop.alpha = 0
                catalogueBackdrop.isHidden = true
            }
        }
    }
    
    // MARK: 底部目录视图
    
    /// 初始化底部目录视图
    private func initBaseCatalogView() {
        catalogueDrawer = ReaderCatalogueView()
        // 代理设为 vc 才能触发章节点击。
        // 目录面板代理目前实现在子类，故按协议做条件转换，避免菜单反向依赖具体子类类型。
        catalogueDrawer.delegate = vc as? any ReaderCatalogueDelegate
        catalogueDrawer.bookModel = vc.bookModel
        catalogueDrawer.backgroundColor = ReaderConfiguration.shared().bgColor
        catalogueDrawer.layer.cornerRadius = 12
        catalogueDrawer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        catalogueDrawer.layer.masksToBounds = true
        catalogueDrawer.isHidden = true
        contentView.addSubview(catalogueDrawer)
        
        let height = READER_CONTENT_VIEW_HEIGHT * 0.7
        catalogueDrawer.frame = CGRect(x: 0, y: READER_CONTENT_VIEW_HEIGHT, width: READER_CONTENT_VIEW_WIDTH, height: height)
    }
    
    /// 显示底部目录
    open func presentBaseCatalog() {
        // 隐藏菜单
        presentDropdown(isShow: false)
        
        // 显示背景遮罩
        presentCatalogBackdrop(isShow: true, animated: true)
        
        // 刷新目录数据并滚动到当前章节
        catalogueDrawer.bookModel = vc.bookModel
        catalogueDrawer.scrollEntry()
        
        // 显示底部目录
        catalogueDrawer.isHidden = false
        let height = READER_CONTENT_VIEW_HEIGHT * 0.7
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            self?.catalogueDrawer.frame.origin.y = READER_CONTENT_VIEW_HEIGHT - height
        })
    }
    
    /// 隐藏底部目录
    open func concealBaseCatalog() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            self?.catalogueDrawer.frame.origin.y = READER_CONTENT_VIEW_HEIGHT
        }) { [weak self] _ in
            self?.catalogueDrawer.isHidden = true
            self?.presentCatalogBackdrop(isShow: false, animated: true)
        }
    }
    
    // MARK: 呼出菜单遮罩
    
    /// 遮罩目标透明度:夜间比浅色主题更深(对照设计稿逐主题采样得到 0.6 / 0.8)
    open var menuBackdropAlpha: CGFloat {
        return ReaderConfiguration.shared().isDarkTheme ? 0.8 : 0.6
    }
    
    /// 初始化呼出菜单遮罩
    private func initMenuBackdrop() {
        
        menuBackdrop = UIView()
        menuBackdrop.backgroundColor = .black
        menuBackdrop.alpha = isMenuShow ? menuBackdropAlpha : 0
        menuBackdrop.isHidden = !isMenuShow
        
        // 不拦截手势,点击仍由 contentView 的单击手势统一处理
        //
        // **不要为了「菜单呼出时别翻页」把这里改成 true。** 遮罩铺满整个 contentView,
        // 一旦参与命中测试就会把落在这块区域的触摸全部吃掉 —— 不只是翻页,滚动模式的
        // 正文滚动、以后加在这一层的任何手势都会一起没掉,而且没法只放过其中一个。
        // 翻页要单独掐,见 `suspendPageTurn(_:)`。
        menuBackdrop.isUserInteractionEnabled = false
        contentView.addSubview(menuBackdrop)
        
        menuBackdrop.frame = CGRect(x: 0, y: 0, width: READER_CONTENT_VIEW_WIDTH, height: READER_CONTENT_VIEW_HEIGHT)
    }
    
    /// 遮罩展示
    private func presentMenuBackdrop(isShow: Bool) {
        
        if isShow {
            menuBackdrop.isHidden = false
            menuBackdrop.alpha = 0
        }
        
        UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: { [weak self] () in
            
            guard let self else { return }
            self.menuBackdrop.alpha = isShow ? self.menuBackdropAlpha : 0
            
        }) { [weak self] (isOK) in
            
            if !isShow { self?.menuBackdrop.isHidden = true }
        }
    }
    
    /// 切换主题后同步遮罩深度(浅色 ←→ 夜间深度不同)
    open func reviseMenuBackdropAlpha() {
        
        guard isMenuShow else { return }
        menuBackdrop.alpha = menuBackdropAlpha
    }
    
    // MARK: -- TopView
    
    /// 初始化TopView
    private func initPeakView() {
        
        topView = ReaderMenuTopBar(hostMenu: self)
        
        topView.isHidden = !isMenuShow
        
        contentView.addSubview(topView)
        
        let y = isMenuShow ? 0 : -READER_MENU_TOP_VIEW_HEIGHT
        
        topView.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: READER_MENU_TOP_VIEW_HEIGHT)
    }
    
    // MARK: -- BottomView
    
    /// 初始化BottomView
    private func initBaseView() {
        
        bottomBar = ReaderMenuBottomBar(hostMenu: self)
    
        bottomBar.isHidden = !isMenuShow
        
        contentView.addSubview(bottomBar)
        
        let currentHeight = bottomBar.getCurrentHeight()
        let y = isMenuShow ? (READER_CONTENT_VIEW_HEIGHT - currentHeight) : READER_CONTENT_VIEW_HEIGHT
        
        bottomBar.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: currentHeight)
        
        
        // 绘制中间虚线(如果不需要虚线可以去掉自己加个分割线)
//        let shapeLayer: CAShapeLayer = CAShapeLayer()
//        
//        shapeLayer.bounds = bottomBar.bounds
//        
//        shapeLayer.position = CGPoint(x: bottomBar.frame.width / 2, y: bottomBar.frame.height / 2)
//        
//        shapeLayer.fillColor = UIColor.clear.cgColor
//        
//        shapeLayer.strokeColor = READER_COLOR_MENU_COLOR.cgColor
//        
//        shapeLayer.lineJoin = CAShapeLayerLineJoin.round
//        
//        shapeLayer.lineDashPhase = 0
//        
//        shapeLayer.lineDashPattern = [NSNumber(value: 1), NSNumber(value: 2)]
//        
//        let path: CGMutablePath = CGMutablePath()
//        
//        path.move(to: CGPoint(x: 0, y: READER_MENU_PROGRESS_VIEW_HEIGHT))
//        
//        path.addLine(to: CGPoint(x: bottomBar.frame.width, y: READER_MENU_PROGRESS_VIEW_HEIGHT))
//        
//        shapeLayer.path = path
//        
//        bottomBar.layer.addSublayer(shapeLayer)
    }
    
    // MARK: 菜单层级
    
    /// 把菜单视图按既定顺序重新提到最前
    ///
    /// contentView 上的 `nightTint`（目录/辅视图用的 0.7 黑遮盖）在 presentOverlay(isShow:true)
    /// 里会被 bringSubviewToFront 提到最前且不再还原，之后呼出菜单时 topView / bottomBar
    /// 就被压在它下面。每次呼出前复位一次层级，保证「遮罩在正文之上、菜单栏之下」这个不变量。
    private func liftMenuHierarchy() {
        
        contentView.bringSubviewToFront(catalogueBackdrop)
        contentView.bringSubviewToFront(catalogueDrawer)
        contentView.bringSubviewToFront(menuBackdrop)
        contentView.bringSubviewToFront(topView)
        contentView.bringSubviewToFront(bottomBar)
        
        // 朗读 dock 排在最后：它只在菜单呼出期间出现，且必须浮在遮罩之上才看得见。
        // 与页脚胶囊的层级要求正好相反（那个要被遮罩压住），所以不能放进上面那组。
        vc?.liftSpeechDockIfInstalled()
    }
    

    
    // MARK: 菜单展示
    
    /// 动画是否完成
    private var isAnimateComplete: Bool = true
    
    open func presentDropdown(isShow: Bool) {
        
        if isMenuShow == isShow || !isAnimateComplete {return}
        
        isAnimateComplete = false
        
        if isShow {
            delegate?.readerMenuWillPresent(self)
            
        }else{ 
            delegate?.readerMenuWillDismiss(self)
            // 隐藏目录遮罩
            presentCatalogBackdrop(isShow: false)
        }
        
        isMenuShow = isShow
        
        // 菜单呼出期间不许滑动翻页。
        //
        // 点击翻页由 `ReaderSheetController` 自己按 `isMenuShow` 拒掉，不需要在这里管；
        // 滑动那条是 UIPageViewController 内部的 pan,只能从外面显式开关。
        // 滚动模式没有这个容器（`pageViewController` 为 nil）,可选链直接跳过。
        vc?.pageViewController?.suspendPageTurn(isShow)
        
        // 更新状态栏
        UIApplication.shared.setStatusBarHidden(!isMenuShow, with: .fade)
        
        presentMenuBackdrop(isShow: isShow)
        
        // 朗读 dock 只在菜单呼出期间可见（菜单收起后由页脚胶囊接手）。
        // 呼出时设置面板恒为收起态（presentBaseView 里会 restoreForMenuDismissed），
        // 所以这里无条件放出来即可，不必判面板状态。
        vc?.presentSpeechDock(isShow: isShow)
        
        presentBaseView(isShow: isShow)
        
        presentPeakView(isShow: isShow) { [weak self] () in
            
            guard let self else { return }
            
            self.isAnimateComplete = true
            
            if isShow {
                self.delegate?.readerMenuDidPresent(self)
            } else {
                self.delegate?.readerMenuDidDismiss(self)
            }
        }
    }
    
    /// TopView展示
    open func presentPeakView(isShow: Bool, completion: ReaderAnimationCompletion? = nil) {
        
        // 顶栏可以被单独唤出(不走 presentDropdown),所以状态栏在这里也同步一次。
        // 统一用 .fade,原先这里是 .slide 而 presentDropdown 是 .fade,两种方式互相打断
        UIApplication.shared.setStatusBarHidden(!isShow, with: .fade)
        
        if isShow {
            liftMenuHierarchy()
            topView.isHidden = false
        }
        
        UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: { [weak self] () in
            
            let y = isShow ? 0 : -READER_MENU_TOP_VIEW_HEIGHT
            
            self?.topView.frame.origin = CGPoint(x: 0, y: y)
            
        }) { [weak self] (isOK) in
            
            if !isShow { self?.topView.isHidden = true }
            
            completion?()
        }
    }
    
    /// BottomView展示
    open func presentBaseView(isShow: Bool, completion: ReaderAnimationCompletion? = nil) {
  
        if isShow { 
            liftMenuHierarchy()
            bottomBar.isHidden = false
            // 每次显示时重置按钮状态
            bottomBar.settingsPanel.restoreForMenuDismissed()
        }

        UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: { [weak self] () in
            
            guard let self else { return }
            let currentHeight = self.bottomBar.getCurrentHeight()
            let y = isShow ? (READER_CONTENT_VIEW_HEIGHT - currentHeight) : READER_CONTENT_VIEW_HEIGHT
            
            self.bottomBar.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: currentHeight)
            self.bottomBar.layoutIfNeeded()
            
        }) { [weak self] (isOK) in
            
            if !isShow, let self {
                self.bottomBar.isHidden = true
                // 滑出动画结束后收起设置面板，并把 bottomBar 复位成「基础高度 + 屏幕外」，
                // 下一次呼出就是干净的整体上滑，不会夹带一次面板塌陷
                self.bottomBar.settingsPanel.restoreForMenuDismissed()
                self.bottomBar.frame = CGRect(x: 0,
                                               y: READER_CONTENT_VIEW_HEIGHT,
                                               width: READER_CONTENT_VIEW_WIDTH,
                                               height: self.bottomBar.getCurrentHeight())
                self.bottomBar.layoutIfNeeded()
            }
            
            completion?()
        }
    }
}
