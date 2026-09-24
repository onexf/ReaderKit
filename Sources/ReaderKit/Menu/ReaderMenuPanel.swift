//
//  ReaderMenuPanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/23.
//

import UIKit

open class ReaderMenuPanel: UIView {

    /// 菜单对象
    open weak var hostMenu: ReaderMenu!
    
    /// 系统初始化
    public override init(frame: CGRect) { super.init(frame: frame) }
    
    /// 初始化
    public convenience init(hostMenu: ReaderMenu!) {
        
        self.init(frame: CGRect.zero)
        
        self.hostMenu = hostMenu
        
        addSubviews()
    }
    
    open func addSubviews() {
        
        backgroundColor = .clear
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
