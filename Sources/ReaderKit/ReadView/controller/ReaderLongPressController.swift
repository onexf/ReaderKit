//
//  ReaderLongPressController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/18.
//

import UIKit

open class ReaderLongPressController: ReaderPageContentController {

    /// 阅读视图
    private var readView: ReaderLongPressView!
    
    /// 当前承载正文渲染的视图。
    ///
    /// 书名页走 `super.initReadView()`，此时本类的 `readView` 为 nil、
    /// 渲染视图落在父类那个上，故需要回退到 super。
    open override var renderingPageView: ReaderPageView? { readView ?? super.renderingPageView }
    
    // 初始化阅读视图
    open override func initReadView() {
        
        // 是否为书籍首页
        if recordModel.pageModel.isHomePage {
            
            super.initReadView()
            
        }else{
            
            // 阅读视图范围（翻页/滚动差异已在 READER_VIEW_RECT 内处理）
            let rect = READER_VIEW_RECT!
            
            // 长按功能需要内容高度防止拖拽超出界限
            let pageModel = recordModel.pageModel!
            
            // 阅读视图
            readView = ReaderLongPressView()
            readView.pageModel = pageModel
            view.addSubview(readView)
            readView.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: pageModel.contentSize.height)
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
        
        // 是否为书籍首页
        if recordModel.pageModel.isHomePage { return }
        
        if readView?.isOpenDrag ?? false {
            
            let windowPoint = ((touches as NSSet).anyObject() as? UITouch)?.location(in: view)
      
            if windowPoint != nil {
                
                let point = view.convert(windowPoint!, to: readView)
        
                readView?.drag(status: status, point: point, windowPoint: windowPoint!)
            }
        }
    }
}
