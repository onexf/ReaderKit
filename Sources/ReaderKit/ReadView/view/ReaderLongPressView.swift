//
//  ReaderLongPressView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/03.
//

/// Pan手势状态
public enum ReaderDragStatus: NSInteger {
    // 开始手势
    case begin
    // 变换中
    case changed
    // 结束手势
    case end
}

/// 长按选中视图的通知收发。
public enum ReaderLongPressNotification {

    /// 注册监听
    public static func observe(target: Any, action: Selector) {
        
        NotificationCenter.default.addObserver(target, selector: action, name: NSNotification.Name(READER_NOTIFICATION_LONG_PRESS_VIEW), object: nil)
    }

    /// 发送通知
    public static func post(userInfo: [AnyHashable : Any]?) {
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: READER_NOTIFICATION_LONG_PRESS_VIEW), object: nil, userInfo: userInfo)
    }

    /// 移除监听
    public static func remove(target: Any) {
        
        NotificationCenter.default.removeObserver(target, name: NSNotification.Name(rawValue: READER_NOTIFICATION_LONG_PRESS_VIEW), object: nil)
    }
}

/// 长按阅读视图通知 info 数据 key
public let READER_KEY_LONG_PRESS_VIEW: String = "ReaderKit.longPressView"

/// 长按阅读视图通知
public let READER_NOTIFICATION_LONG_PRESS_VIEW: String = "ReaderKit.longPressViewNotification"

/// 光标拖拽触发范围
public let READER_LONG_PRESS_CURSOR_VIEW_OFFSET: CGFloat = -READER_SPACE_20

import UIKit

open class ReaderLongPressView: ReaderPageView {
    
    /// 开启拖拽
    public private(set) var isOpenDrag: Bool = false
    
    /// 选中区域
    private var selectRange: NSRange!
    
    /// 选中区域CGRect数组
    private var rects: [CGRect] = []
    
    /// 长按
    private var longGes: UILongPressGestureRecognizer?
    
    /// 单击
    private var tapGes: UITapGestureRecognizer?
    
    /// 左光标
    private var LCursorView: ReaderLongPressCursorView!
    
    /// 右光标
    private var RCursorView: ReaderLongPressCursorView!
    
    /// 触摸的光标是左还是右
    private var isCursorLorR: Bool = true
    
    /// 是否触摸到左右光标
    private var isTouchCursor: Bool = false
    
    /// 动画时间
    private var duration: TimeInterval = READER_AD_TIME
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        // ⚠️ 长按选中文字功能临时禁用（2026-06）
        //
        // 背景：
        //   早期实现里的放大镜视图（UIWindow 子类）
        //   在 iOS 13+ SceneDelegate 多场景模型下进入内部循环 / 野指针，
        //   线上触发 EXC_BAD_ACCESS（Thread 1, code=2）。
        //   崩溃栈最深点是 setTargetWindow → makeKeyAndVisible / animateWithDuration。
        //   尝试改成 UIView 挂到 targetWindow 上、用 hidden 规避自我镜像 等若干轻量修复
        //   均未能彻底止崩，最终选择直接关闭长按手势止血。
        //
        // 影响：
        //   - 阅读页 Left&Right 翻页模式下长按文字不会再选中、不再弹出复制菜单
        //   - 现阶段需求不依赖文字选中复制，因此关闭对体验无损
        //
        // ⚠️ 书签 / 划线 / 笔记 等功能开发时需要恢复：
        //   1. 取消下面 4 行手势注册的注释，恢复 longGes / tapGes 注册
        //   2. 同时重写放大镜实现，不要再用 。建议方案：
        //      - 普通 UIView，addSubview 到 keyWindow
        //      - 内容用 UIView.drawHierarchy(in:afterScreenUpdates:) 截屏 + UIImageView 显示
        //      - 截屏前 self.isHidden = true 避免把放大镜自己截进去
        //   3. 验证场景：iOS 15.1 / 17 / 18，iPhone + iPad 多窗口，反复长按 + 翻页
        //   4. 同步把 .kiro/learnings/bugs/ 里这次的 learning 链接到书签 spec
        //
        // longGes = UILongPressGestureRecognizer(target: self, action: #selector(longAction(long:)))
        // addGestureRecognizer(longGes!)
        //
        // tapGes = UITapGestureRecognizer(target: self, action: #selector(handleTapAction(tap:)))
        // tapGes!.isEnabled = false
        // addGestureRecognizer(tapGes!)
    }
    
    /// 创建放大镜
    ///
    /// ⚠️ 已配合长按手势一起禁用，详见 init(frame:) 顶部说明。
    /// 恢复书签功能时，本方法需要重新实现：建议用 UIView + drawHierarchy(in:afterScreenUpdates:)
    /// 替代老的 避免再次踩 UIWindow / SceneDelegate 的坑。
    private func creatMagnifierView(windowPoint: CGPoint) {
        // no-op: 放大镜功能临时禁用，等书签功能开发时一并重写
    }
    
    // MARK: 手势事件
    
    /// 单击事件
    @objc private func handleTapAction(tap: UITapGestureRecognizer) {

        // 重置页面数据
        reset()
    }
    
    /// 长按事件
    @objc private func longAction(long: UILongPressGestureRecognizer) {

        // 触摸位置
        let point = long.location(in: self)

        // 触摸位置
        let windowPoint = long.location(in: window)

        // 触摸开始 触摸中
        if long.state == .began {

            // 发送通知
            ReaderLongPressNotification.post(userInfo: [READER_KEY_LONG_PRESS_VIEW : NSNumber(value: true)])

            // 放大镜
            creatMagnifierView(windowPoint: windowPoint)

        }else if long.state == .changed {

            // 放大镜跟随手指：恢复长按功能时在此更新放大镜位置

        }else{ // 触摸结束

            // 获得选中区域
            selectRange = ReaderCoreText.touchedParagraphRange(point: point, frameRef: frameRef, content: pageModel.content?.string)

            // 获得选中选中范围
            rects = ReaderCoreText.rangeRects(range: selectRange!, frameRef: frameRef, content: pageModel.content?.string)

            // 显示光标
            cursor(isShow: true)

            // 显示复制菜单
            // 注：原实现挂在放大镜移除动画的回调里（放大镜消失后再弹菜单）。
            // 放大镜已随  一并移除，恢复长按功能重写放大镜时，
            // 需把这行改回移除动画的完成回调，避免菜单与放大镜同时出现。
            presentDropdown(isShow: true)

            // 重绘
            setNeedsDisplay()

            // 开启手势
            if !rects.isEmpty {

                // 手势状态
                longGes?.isEnabled = false
                tapGes?.isEnabled = true
                isOpenDrag = true

                // 发送通知
                ReaderLongPressNotification.post(userInfo: [READER_KEY_LONG_PRESS_VIEW : NSNumber(value: false)])
            }
        }
    }
    
    // MARK: 页面触摸拖拽处理
    
    /// 触摸开始
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        drag(touches: touches, status: .begin)
    }
    
    /// 触摸移动
    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        drag(touches: touches, status: .changed)
    }
    
    /// 触摸结束
    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        drag(touches: touches, status: .end)
    }
    
    /// 触摸取消
    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        drag(touches: touches, status: .end)
    }
    
    /// 解析触摸事件
    private func drag(touches: Set<UITouch>, status: ReaderDragStatus) {
        
        if isOpenDrag {
            
            let touch: UITouch? = ((touches as NSSet).anyObject() as? UITouch)
            
            let point = touch?.location(in: self)
            
            let windowPoint = touch?.location(in: self.window)
            
            drag(status: status, point: point!, windowPoint: windowPoint!)
        }
    }
    
    /// 拖拽事件解析
    open func drag(status: ReaderDragStatus, point: CGPoint, windowPoint: CGPoint) {

        // 检查是否超出范围
        let point = CGPoint(x: min(max(point.x, 0), pageModel.contentSize.width), y: min(max(point.y, 0), pageModel.contentSize.height))

        // 触摸开始
        if status == .begin {
            
            if LCursorView.frame.insetBy(dx: READER_LONG_PRESS_CURSOR_VIEW_OFFSET, dy: READER_LONG_PRESS_CURSOR_VIEW_OFFSET).contains(point) { // 触摸到左边光标
                
                // 隐藏菜单
                presentDropdown(isShow: false)
                
                isCursorLorR = true
                
                isTouchCursor = true
                
            }else if RCursorView.frame.insetBy(dx: READER_LONG_PRESS_CURSOR_VIEW_OFFSET, dy: READER_LONG_PRESS_CURSOR_VIEW_OFFSET).contains(point) { // 触摸到右边光标
                
                // 隐藏菜单
                presentDropdown(isShow: false)
                
                isCursorLorR = false
                
                isTouchCursor = true
                
            }else{ // 没有触摸到光标
                
                isTouchCursor = false
            }
            
            // 触摸到了光标
            if isTouchCursor {
                
                // 放大镜
                creatMagnifierView(windowPoint: windowPoint)
            }
            
        }else if status == .changed { // 触摸中
            
            // 拖动光标时放大镜跟随：恢复长按功能时在此更新放大镜位置
            
            // 判断触摸
            if isTouchCursor && selectRange != nil {
                
                // 触摸到的位置
                let location = ReaderCoreText.touchedCharacterIndex(point: point, frameRef: frameRef)
                
                // 无结果
                if location == -1 { return }
             
                // 刷新选中区域
                reviseChooseRange(location: location)
                
                // 获得选中选中范围
                rects = ReaderCoreText.rangeRects(range: selectRange, frameRef: frameRef, content: pageModel.content?.string)
                
                // 更新光标位置
                reviseCursorFrame()
            }
            
        }else{ // 触摸结束
   
            // 触摸到光标
            if isTouchCursor {
                
                // 显示复制菜单
                // 注：原实现挂在放大镜移除动画的回调里，恢复长按功能时同 longAction 一并调整
                presentDropdown(isShow: true)
            }
            
            // 结束触摸
            isTouchCursor = false
        }
        
        // 重绘
        setNeedsDisplay()
    }
    
    /// 刷新选中区域
    private func reviseChooseRange(location: Int) {
        
        // 左右 Location 位置
        let LLocation = selectRange!.location
        let RLocation = selectRange!.location + selectRange!.length
        
        // 判断触摸
        if isCursorLorR { // 左边
            
            if location < RLocation {
                
                if location > LLocation {
                    
                    selectRange!.length -= location - LLocation
                    
                    selectRange!.location = location
                    
                }else if location < LLocation {
                    
                    selectRange!.length += LLocation - location
                    
                    selectRange!.location = location
                }
                
            }else{
                
                isCursorLorR = false
                
                var length = location - RLocation
                
                let tempLength = (length == 0 ? 1 : 0)
                
                length = (length == 0 ? 1 : length)
                
                selectRange?.length = length
                
                selectRange?.location = RLocation - tempLength
                
                reviseChooseRange(location: location)
            }
            
        }else{ // 右边
            
            if location > LLocation {
                
                if location > RLocation {
                    
                    selectRange!.length += location - RLocation
                    
                }else if location < RLocation {
                    
                    selectRange!.length -= RLocation - location
                }
                
            }else{
                
                isCursorLorR = true
                
                let tempLength = LLocation - location
                
                let length = (tempLength == 0 ? 1 : tempLength)
                
                selectRange?.length = length
                
                selectRange?.location = LLocation - tempLength
                
                reviseChooseRange(location: location)
            }
        }
    }
    
    // MARK: 光标处理
    
    /// 隐藏或显示光标
    private func cursor(isShow: Bool) {
        
        if isShow {
            
            if !rects.isEmpty && LCursorView == nil {
                
                LCursorView = ReaderLongPressCursorView()
                LCursorView.isTorB = true
                addSubview(LCursorView)
                
                RCursorView = ReaderLongPressCursorView()
                RCursorView.isTorB = false
                addSubview(RCursorView)
                
                reviseCursorFrame()
            }
            
        }else{
            
            if LCursorView != nil {
                
                LCursorView.removeFromSuperview()
                LCursorView = nil
                
                RCursorView.removeFromSuperview()
                RCursorView = nil
            }
        }
    }
    
    /// 更新光标位置
    private func reviseCursorFrame() {
        
        if !rects.isEmpty && LCursorView != nil {
            
            let cursorViewW: CGFloat = 10
            let cursorViewSpaceW: CGFloat = cursorViewW / 4
            let cursorViewSpaceH: CGFloat = cursorViewW / 1.1
            let first = rects.first!
            let last = rects.last!
            
            LCursorView.frame = CGRect(x: first.minX - cursorViewW + cursorViewSpaceW, y: bounds.height - first.minY - first.height - cursorViewSpaceH, width: cursorViewW, height: first.height + cursorViewSpaceH)
            
            RCursorView.frame = CGRect(x: last.maxX - cursorViewSpaceW, y: bounds.height - last.minY - last.height, width: cursorViewW, height: last.height + cursorViewSpaceH)
        }
    }
    
    // MARK: 重置页面
    
    /// 重置页面数据
    private func reset() {
        
        // 发送通知
        ReaderLongPressNotification.post(userInfo: [READER_KEY_LONG_PRESS_VIEW : NSNumber(value: true)])
        
        // 手势状态
        tapGes?.isEnabled = false
        isOpenDrag = false
        longGes?.isEnabled = true
        
        // 移除菜单
        presentDropdown(isShow: false)
        
        // 清空选中
        selectRange = nil
        rects.removeAll()
        
        // 移除光标
        cursor(isShow: false)
        
        // 重绘
        setNeedsDisplay()
    }
    
    // MARK: 菜单相关
    
    /// 隐藏或显示菜单
    private func presentDropdown(isShow: Bool) {
        
        if isShow { // 显示
            
            if !rects.isEmpty {
            
                let rect = ReaderCoreText.menuRect(rects: rects, viewFrame: bounds)
                
                becomeFirstResponder()
                
                let menuController = UIMenuController.shared
                
                let copy = UIMenuItem(title: "复制", action: #selector(clickCopy))
                
                menuController.menuItems = [copy]
                
                menuController.setTargetRect(rect, in: self)
                
                readerDelay {
                    
                    menuController.setMenuVisible(true, animated: true)
                }
            }
            
        }else{ // 隐藏
            
            readerDelay {
                
                UIMenuController.shared.setMenuVisible(false, animated: true)
            }
        }
    }
    
    /// 允许菜单事件
    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        
        if action == #selector(clickCopy) { return true }
        
        return false
    }
    
    /// 允许成为响应者
    open override var canBecomeFirstResponder: Bool {
        
        return true
    }
    
    /// 复制事件
    @objc private func clickCopy() {
        
        if selectRange != nil {
            
            let temSelectRange = selectRange!
            
            let tempContent = pageModel.content
            
            DispatchQueue.global().async {
                
                UIPasteboard.general.string = tempContent?.string.substring(temSelectRange)
            }
            
            // 重置页面数据
            reset()
        }
    }
    
    // MARK: 绘制
    
    /// 绘制
    open override func draw(_ rect: CGRect) {
        
        if (frameRef == nil) {return}
        
        let ctx = UIGraphicsGetCurrentContext()
        
        ctx?.textMatrix = CGAffineTransform.identity
        
        ctx?.translateBy(x: 0, y: bounds.size.height)
        
        ctx?.scaleBy(x: 1.0, y: -1.0)
        
        if selectRange != nil && !rects.isEmpty {
            
            let path = CGMutablePath()
            
            READER_COLOR_MAIN.withAlphaComponent(0.5).setFill()
            
            path.addRects(rects)
            
            ctx?.addPath(path)
            
            ctx?.fillPath()
        }
        
        CTFrameDraw(frameRef!, ctx!)
    }
    
    /// 释放
    deinit {
        
        tapGes?.removeTarget(self, action: #selector(handleTapAction(tap:)))
        tapGes = nil
        
        longGes?.removeTarget(self, action: #selector(longAction(long:)))
        longGes = nil
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
