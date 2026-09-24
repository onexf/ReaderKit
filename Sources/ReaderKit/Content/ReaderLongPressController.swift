//
//  ReaderLongPressController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/18.
//

import UIKit

open class ReaderLongPressController: ReaderPageContentController {

    /// 阅读视图
    private var selectionView: ReaderLongPressView!
    
    /// 当前承载正文渲染的视图。
    ///
    /// 书名页走 `super.initReadView()`，此时本类的 `selectionView` 为 nil、
    /// 渲染视图落在父类那个上，故需要回退到 super。
    open override var renderingPageView: ReaderPageView? { selectionView ?? super.renderingPageView }
    
    // 初始化阅读视图
    open override func initReadView() {
        
        // 是否为书籍首页
        if readingRecord.layoutPage.isHomePage {
            
            super.initReadView()
            
        }else{
            
            // 阅读视图范围（翻页/滚动差异已在 READER_VIEW_RECT 内处理）
            let rect = READER_VIEW_RECT!
            
            let layoutPage = readingRecord.layoutPage!
            
            // 阅读视图
            selectionView = ReaderLongPressView()
            selectionView.layoutPage = layoutPage
            view.addSubview(selectionView)
            
            // 高度取**阅读区域**，与 `ReaderPageView` 在翻页模式下的排版尺寸严格一致。
            //
            // `ReaderPageView.draw(_:)` 按 `bounds.height` 做 CoreText 坐标翻转，
            // 所以视图高度与排版高度必须相等，否则文字整体错位。
            //
            // 这里曾经用 `layoutPage.contentSize.height`（注释理由是「长按拖拽需要内容高度」）。
            // 那个值是在无高度约束下量出来的，比阅读区域高出末行行距与段后间距，
            // 于是每一页的末行都落到阅读区域之外、压在页脚上。
            selectionView.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
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
        if readingRecord.layoutPage.isHomePage { return }
        
        if selectionView?.isDragActive ?? false {
            
            let windowPoint = ((touches as NSSet).anyObject() as? UITouch)?.location(in: view)
      
            if windowPoint != nil {
                
                let point = view.convert(windowPoint!, to: selectionView)
        
                selectionView?.drag(status: status, point: point, windowPoint: windowPoint!)
            }
        }
    }
}
