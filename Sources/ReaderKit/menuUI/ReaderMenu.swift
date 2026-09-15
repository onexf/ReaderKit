//
//  ReaderMenu.swift
//  ReaderKit
//
//  Created by Asuna on 2025/08/28.
//

import UIKit

@objc public protocol ReaderMenuDelegate: NSObjectProtocol {
    
    /// 菜单将要显示
    @objc optional func readMenuWillDisplay(readMenu: ReaderMenu!)
    
    /// 菜单完成显示
    @objc optional func readMenuDidDisplay(readMenu: ReaderMenu!)
    
    /// 菜单将要隐藏
    @objc optional func readMenuWillEndDisplay(readMenu: ReaderMenu!)
    
    /// 菜单完成隐藏
    @objc optional func readMenuDidEndDisplay(readMenu: ReaderMenu!)
    
    /// 点击返回
    @objc optional func readMenuClickBack(readMenu: ReaderMenu!)
    
    /// 点击加入书架
    @objc optional func readMenuClickAddToBookshelf(readMenu: ReaderMenu!)
    
    /// 点击反馈
    @objc optional func readMenuClickFeedback(readMenu: ReaderMenu!)
    
    /// 点击书签
    @objc optional func readMenuClickMark(readMenu: ReaderMenu!, topView: ReaderMenuTopBar!, markButton: UIButton!)
    
    /// 点击目录
    @objc optional func readMenuClickCatalogue(readMenu: ReaderMenu!)
    
    /// 点击切换日夜间
    @objc optional func readMenuClickDayAndNight(readMenu: ReaderMenu!)
    
    /// 点击上一章
    @objc optional func readMenuClickPreviousChapter(readMenu: ReaderMenu!)
    
    /// 点击下一章
    @objc optional func readMenuClickNextChapter(readMenu: ReaderMenu!)
    
    /// 拖拽章节进度(分页进度)
    @objc optional func readMenuDraggingProgress(readMenu: ReaderMenu!, toPage: NSInteger)
    
    /// 拖拽章节进度(总文章进度,网络文章也可以使用)
    @objc optional func readMenuDraggingProgress(readMenu: ReaderMenu!, toChapterID: NSNumber, toPage: NSInteger)
    
    /// 点击切换背景颜色
    @objc optional func readMenuClickBGColor(readMenu: ReaderMenu)
    
    /// 点击切换字体
    @objc optional func readMenuClickFont(readMenu: ReaderMenu)
    
    /// 点击切换字体大小
    @objc optional func readMenuClickFontSize(readMenu: ReaderMenu)
    
    /// 点击切换行高
    @objc optional func readMenuClickLineHeight(readMenu: ReaderMenu)
    
    /// 切换进度显示(分页 || 总进度)
    @objc optional func readMenuClickDisplayProgress(readMenu: ReaderMenu)
    
    /// 点击切换间距
    @objc optional func readMenuClickSpacing(readMenu: ReaderMenu)
    
    /// 点击切换翻页效果
    @objc optional func readMenuClickEffect(readMenu: ReaderMenu)
  
}

open class ReaderMenu: NSObject, UIGestureRecognizerDelegate {

    /// 控制器
    /// 阅读器控制器。
    ///
    /// 类型为引擎基类而非具体子类：菜单只用到 `contentView` / `readModel` / `view` /
    /// `pageViewController` 这几个引擎成员，不需要感知宿主子类的业务字段。
    public private(set) weak var vc: ReaderViewController!
    
    /// 阅读主视图
    public private(set) weak var contentView: ReaderContentView!
    
    /// 代理
    public private(set) weak var delegate: ReaderMenuDelegate!
    
    /// 菜单显示状态
    open var isMenuShow: Bool = false
    
    /// 单击手势
    public private(set) var singleTap: UITapGestureRecognizer!
    
    /// TopView
    public private(set) var topView: ReaderMenuTopBar!
    
    /// BottomView
    public private(set) var bottomView: ReaderMenuBottomBar!
    
    /// 目录背景遮罩
    public private(set) var catalogBackgroundView: UIView!
    
    /// 呼出菜单遮罩(设计稿:压在正文之上、顶部栏/底部栏之下,浅色主题 60% 黑、夜间 80% 黑)
    public private(set) var menuBackdrop: UIView!
    
    /// 底部目录视图
    private var bottomCatalogView: ReaderCatalogueView!
    
    /// 日夜间遮盖
    public private(set) var cover: UIView!
    
    /// 禁用系统初始化
    private override init() { super.init() }
    
    /// 初始化
    public convenience init(vc: ReaderViewController!, delegate: ReaderMenuDelegate!) {
        
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
        singleTap = UITapGestureRecognizer(target: self, action: #selector(touchSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.delegate = self
        vc.contentView.addGestureRecognizer(singleTap)
    }
    
    // 触发单击手势
    @objc private func touchSingleTap() {
        
        // 如果内容还未加载完成，不显示菜单
        guard vc.readModel != nil else {
            // log("⚠️ touchSingleTap: readModel 为 nil，内容尚未加载，不显示菜单")
            return
        }
        
        // 滚动模式下，只有屏幕中间1/3区域点击才唤起菜单
        if ReaderConfiguration.shared().effectType == .scroll {
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
    
    // MARK: -- UIGestureRecognizerDelegate
    
    /// 手势拦截
    ///
    /// 原先靠类名白名单判断，设置面板的容器是裸 UIView、不在名单里，导致点面板空白处
    /// 会把菜单整个关掉。改成按视图层级判断：落在顶栏/底栏（含它们的任意子视图）里的
    /// 触摸都不触发呼出手势，新增控件不需要再维护名单。
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        guard let touchedView = touch.view else { return true }
        
        if let topView, touchedView.isDescendant(of: topView) { return false }
        
        if let bottomView, touchedView.isDescendant(of: bottomView) { return false }
        
        if let bottomCatalogView, touchedView.isDescendant(of: bottomCatalogView) { return false }
        
        if touchedView is UIControl { return false }
        
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
        
        cover = UIView()
        cover.alpha = CGFloat(NSNumber(value: ReaderDefaults.bool(READER_KEY_MODE_DAY_NIGHT)).floatValue)
        cover.isUserInteractionEnabled = false
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        vc.view.addSubview(cover)
        cover.frame = vc.view.bounds
    }
    
    // MARK: 目录背景遮罩
    
    /// 初始化目录背景遮罩
    private func initCatalogBackdrop() {
        catalogBackgroundView = UIView()
        // 目录背景蒙版：黑色 60% 透明（原 .cover1，改用引擎自有色值以脱离宿主 UIColor 扩展）
        catalogBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        catalogBackgroundView.isHidden = true
        contentView.addSubview(catalogBackgroundView)
        // 遮罩撑满整个contentView
        catalogBackgroundView.frame = CGRect(x: 0, y: 0, width: READER_CONTENT_VIEW_WIDTH, height: READER_CONTENT_VIEW_HEIGHT)
        
        // 添加点击手势关闭目录
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCatalogBackgroundTap))
        catalogBackgroundView.addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleCatalogBackgroundTap() {
        // log("🔥 handleCatalogBackgroundTap called")
        // 关闭底部目录
        concealBaseCatalog()
    }
    
    /// 显示/隐藏目录背景遮罩
    open func presentCatalogBackdrop(isShow: Bool, animated: Bool = true) {
        if isShow {
            catalogBackgroundView.isHidden = false
            if animated {
                catalogBackgroundView.alpha = 0
                UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS) {
                    self.catalogBackgroundView.alpha = 1
                }
            } else {
                catalogBackgroundView.alpha = 1
            }
        } else {
            if animated {
                UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: {
                    self.catalogBackgroundView.alpha = 0
                }) { _ in
                    self.catalogBackgroundView.isHidden = true
                }
            } else {
                catalogBackgroundView.alpha = 0
                catalogBackgroundView.isHidden = true
            }
        }
    }
    
    // MARK: 底部目录视图
    
    /// 初始化底部目录视图
    private func initBaseCatalogView() {
        bottomCatalogView = ReaderCatalogueView()
        // 代理设为 vc 才能触发 catalogViewClickChapter。
        // 目录面板代理目前实现在子类，故按协议做条件转换，避免菜单反向依赖具体子类类型。
        bottomCatalogView.delegate = vc as? ReaderCatalogueDelegate
        bottomCatalogView.readModel = vc.readModel
        bottomCatalogView.backgroundColor = ReaderConfiguration.shared().bgColor
        bottomCatalogView.layer.cornerRadius = 12
        bottomCatalogView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bottomCatalogView.layer.masksToBounds = true
        bottomCatalogView.isHidden = true
        contentView.addSubview(bottomCatalogView)
        
        let height = READER_CONTENT_VIEW_HEIGHT * 0.7
        bottomCatalogView.frame = CGRect(x: 0, y: READER_CONTENT_VIEW_HEIGHT, width: READER_CONTENT_VIEW_WIDTH, height: height)
    }
    
    /// 显示底部目录
    open func presentBaseCatalog() {
        // 隐藏菜单
        presentDropdown(isShow: false)
        
        // 显示背景遮罩
        presentCatalogBackdrop(isShow: true, animated: true)
        
        // 刷新目录数据并滚动到当前章节
        bottomCatalogView.readModel = vc.readModel
        bottomCatalogView.scrollEntry()
        
        // 显示底部目录
        bottomCatalogView.isHidden = false
        let height = READER_CONTENT_VIEW_HEIGHT * 0.7
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            self?.bottomCatalogView.frame.origin.y = READER_CONTENT_VIEW_HEIGHT - height
        })
    }
    
    /// 隐藏底部目录
    open func concealBaseCatalog() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: { [weak self] in
            self?.bottomCatalogView.frame.origin.y = READER_CONTENT_VIEW_HEIGHT
        }) { [weak self] _ in
            self?.bottomCatalogView.isHidden = true
            self?.presentCatalogBackdrop(isShow: false, animated: true)
        }
    }
    
    // MARK: 呼出菜单遮罩
    
    /// 遮罩目标透明度:夜间比浅色主题更深(对照设计稿逐主题采样得到 0.6 / 0.8)
    open var menuBackdropAlpha: CGFloat {
        return ReaderConfiguration.shared().isNightMode ? 0.8 : 0.6
    }
    
    /// 初始化呼出菜单遮罩
    private func initMenuBackdrop() {
        
        menuBackdrop = UIView()
        menuBackdrop.backgroundColor = .black
        menuBackdrop.alpha = isMenuShow ? menuBackdropAlpha : 0
        menuBackdrop.isHidden = !isMenuShow
        // 不拦截手势,点击仍由 contentView 的单击手势统一处理
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
        
        topView = ReaderMenuTopBar(readMenu: self)
        
        topView.isHidden = !isMenuShow
        
        contentView.addSubview(topView)
        
        let y = isMenuShow ? 0 : -READER_MENU_TOP_VIEW_HEIGHT
        
        topView.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: READER_MENU_TOP_VIEW_HEIGHT)
    }
    
    // MARK: -- BottomView
    
    /// 初始化BottomView
    private func initBaseView() {
        
        bottomView = ReaderMenuBottomBar(readMenu: self)
    
        bottomView.isHidden = !isMenuShow
        
        contentView.addSubview(bottomView)
        
        let currentHeight = bottomView.getCurrentHeight()
        let y = isMenuShow ? (READER_CONTENT_VIEW_HEIGHT - currentHeight) : READER_CONTENT_VIEW_HEIGHT
        
        bottomView.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: currentHeight)
        
        
        // 绘制中间虚线(如果不需要虚线可以去掉自己加个分割线)
//        let shapeLayer: CAShapeLayer = CAShapeLayer()
//        
//        shapeLayer.bounds = bottomView.bounds
//        
//        shapeLayer.position = CGPoint(x: bottomView.frame.width / 2, y: bottomView.frame.height / 2)
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
//        path.addLine(to: CGPoint(x: bottomView.frame.width, y: READER_MENU_PROGRESS_VIEW_HEIGHT))
//        
//        shapeLayer.path = path
//        
//        bottomView.layer.addSublayer(shapeLayer)
    }
    
    // MARK: 菜单层级
    
    /// 把菜单视图按既定顺序重新提到最前
    ///
    /// contentView 上的 `cover`（目录/辅视图用的 0.7 黑遮盖）在 presentOverlay(isShow:true)
    /// 里会被 bringSubviewToFront 提到最前且不再还原，之后呼出菜单时 topView / bottomView
    /// 就被压在它下面。每次呼出前复位一次层级，保证「遮罩在正文之上、菜单栏之下」这个不变量。
    private func liftMenuHierarchy() {
        
        contentView.bringSubviewToFront(catalogBackgroundView)
        contentView.bringSubviewToFront(bottomCatalogView)
        contentView.bringSubviewToFront(menuBackdrop)
        contentView.bringSubviewToFront(topView)
        contentView.bringSubviewToFront(bottomView)
    }
    
    // MARK: 菜单展示
    
    /// 动画是否完成
    private var isAnimateComplete: Bool = true
    
    open func presentDropdown(isShow: Bool) {
        
        if isMenuShow == isShow || !isAnimateComplete {return}
        
        isAnimateComplete = false
        
        if isShow {
            delegate?.readMenuWillDisplay?(readMenu: self)
            
        }else{ 
            delegate?.readMenuWillEndDisplay?(readMenu: self)
            // 隐藏目录遮罩
            presentCatalogBackdrop(isShow: false)
        }
        
        isMenuShow = isShow
        
        // 更新状态栏
        UIApplication.shared.setStatusBarHidden(!isMenuShow, with: .fade)
        
        presentMenuBackdrop(isShow: isShow)
        
        presentBaseView(isShow: isShow)
        
        presentPeakView(isShow: isShow) { [weak self] () in
            
            self?.isAnimateComplete = true
            
            if isShow { self?.delegate?.readMenuDidDisplay?(readMenu: self!)
                
            }else{ self?.delegate?.readMenuDidEndDisplay?(readMenu: self!) }
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
            bottomView.isHidden = false
            // 每次显示时重置按钮状态
            bottomView.funcView.restoreForMenuDismissed()
        }

        UIView.animate(withDuration: READER_MENU_MOTION_TIME, delay: 0, options: READER_MENU_MOTION_OPTIONS, animations: { [weak self] () in
            
            guard let self else { return }
            let currentHeight = self.bottomView.getCurrentHeight()
            let y = isShow ? (READER_CONTENT_VIEW_HEIGHT - currentHeight) : READER_CONTENT_VIEW_HEIGHT
            
            self.bottomView.frame = CGRect(x: 0, y: y, width: READER_CONTENT_VIEW_WIDTH, height: currentHeight)
            self.bottomView.layoutIfNeeded()
            
        }) { [weak self] (isOK) in
            
            if !isShow, let self {
                self.bottomView.isHidden = true
                // 滑出动画结束后收起设置面板，并把 bottomView 复位成「基础高度 + 屏幕外」，
                // 下一次呼出就是干净的整体上滑，不会夹带一次面板塌陷
                self.bottomView.funcView.restoreForMenuDismissed()
                self.bottomView.frame = CGRect(x: 0,
                                               y: READER_CONTENT_VIEW_HEIGHT,
                                               width: READER_CONTENT_VIEW_WIDTH,
                                               height: self.bottomView.getCurrentHeight())
                self.bottomView.layoutIfNeeded()
            }
            
            completion?()
        }
    }
}
