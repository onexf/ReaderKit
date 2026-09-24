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

public protocol ReaderContentViewDelegate: AnyObject {

    /// 点了正文上的遮罩。抽屉 / 浮层开着时用它收起。
    func contentViewDidTapCover(_ contentView: ReaderContentView)
}

open class ReaderContentView: UIView {

    /// 代理
    open weak var delegate: (any ReaderContentViewDelegate)?
    
    /// 遮盖
    public private(set) var dimOverlay: UIControl!
    
    /// 是否显示遮盖
    private var isDimOverlayVisible: Bool = false
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        dimOverlay = UIControl()
        dimOverlay.alpha = 0
        dimOverlay.isUserInteractionEnabled = false
        dimOverlay.backgroundColor = .black
        dimOverlay.addAction(UIAction { [weak self] _ in self?.handleCoverTap() }, for: .touchUpInside)
        addSubview(dimOverlay)
    }
    
    /// 遮盖目标透明度：与呼出菜单遮罩取同一档（设计稿逐主题采样，浅色 60% 黑、夜间 80% 黑）
    private var overlayAlpha: CGFloat {
        
        return ReaderConfiguration.shared().isDarkTheme ? 0.8 : 0.6
    }
    
    private func handleCoverTap() {
        
        dimOverlay.isUserInteractionEnabled = false
        
        delegate?.contentViewDidTapCover(self)
        
        presentOverlay(isShow: false)
    }
    
    /// 遮盖展示
    open func presentOverlay(isShow: Bool, force: Bool = false) {
        
        if !force && isDimOverlayVisible == isShow { return }
        
        if isShow {
            
            // 强制重置状态，确保能显示
            if force {
                dimOverlay.alpha = 0
                isDimOverlayVisible = false
            }
            
            bringSubviewToFront(dimOverlay)
            
            dimOverlay.isUserInteractionEnabled = true
        }
        
        isDimOverlayVisible = isShow
        
        UIView.animate(withDuration: READER_AD_TIME) { [weak self] () in
            
            guard let self else { return }
            
            self.dimOverlay.alpha = isShow ? self.overlayAlpha : 0
        }
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        dimOverlay.frame = bounds
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
