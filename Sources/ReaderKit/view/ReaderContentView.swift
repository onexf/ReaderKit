//
//  ReaderContentView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/17.
//

import UIKit

/// contentView 宽高
public let READER_CONTENT_VIEW_WIDTH: CGFloat = ReaderScreenMetrics.screenWidth
public let READER_CONTENT_VIEW_HEIGHT: CGFloat = ReaderScreenMetrics.screenHeight

@objc public protocol ReaderContentViewDelegate: NSObjectProtocol {
    
    /// 点击遮罩
    @objc optional func contentViewClickCover(contentView: ReaderContentView)
}

open class ReaderContentView: UIView {

    /// 代理
    open weak var delegate: ReaderContentViewDelegate!
    
    /// 遮盖
    public private(set) var cover: UIControl!
    
    /// 是否显示遮盖
    private var isShowCover: Bool = false
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        cover = UIControl()
        cover.alpha = 0
        cover.isUserInteractionEnabled = false
        cover.backgroundColor = .black
        cover.addTarget(self, action: #selector(clickCover), for: .touchUpInside)
        addSubview(cover)
    }
    
    /// 遮盖目标透明度：与呼出菜单遮罩取同一档（设计稿逐主题采样，浅色 60% 黑、夜间 80% 黑）
    private var overlayAlpha: CGFloat {
        
        return ReaderConfiguration.shared().isNightMode ? 0.8 : 0.6
    }
    
    @objc private func clickCover() {
        
        cover.isUserInteractionEnabled = false
        
        delegate?.contentViewClickCover?(contentView: self)
        
        presentOverlay(isShow: false)
    }
    
    /// 遮盖展示
    open func presentOverlay(isShow: Bool, force: Bool = false) {
        
        if !force && isShowCover == isShow { return }
        
        if isShow {
            
            // 强制重置状态，确保能显示
            if force {
                cover.alpha = 0
                isShowCover = false
            }
            
            bringSubviewToFront(cover)
            
            cover.isUserInteractionEnabled = true
        }
        
        isShowCover = isShow
        
        UIView.animate(withDuration: READER_AD_TIME) { [weak self] () in
            
            guard let self else { return }
            
            self.cover.alpha = isShow ? self.overlayAlpha : 0
        }
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        cover.frame = bounds
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
