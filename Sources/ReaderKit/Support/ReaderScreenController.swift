//
//  ReaderScreenController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/02.
//

import UIKit

open class ReaderScreenController: UIViewController {

    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        initialize()
        
        addSubviews()
        
        appendDone()
    }
    
    open func initialize() {
        
        view.backgroundColor = UIColor.white
        
        extendedLayoutIncludesOpaqueBars = true
        
        if #available(iOS 11.0, *) {
            // iOS 11及以上版本使用安全区域
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
    }
    
    open func addSubviews() { }
    
    open func appendDone() { }
}
