//
//  UIPageViewController+Extension.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/10.
//

import UIKit

// 关联对象的 key。`objc_setAssociatedObject` 只用这两个变量的**地址**，值是什么无所谓，
// 所以用 `UInt8` 而不是 `String` —— 字符串字面量会白白留在二进制的 __cstring 里。
private nonisolated(unsafe) var panGestureToggleKey: UInt8 = 0
private nonisolated(unsafe) var tapGestureToggleKey: UInt8 = 0

extension UIPageViewController {

    /// 手势启用
    public var gestureRecognizerEnabled: Bool {
        
        get{ return (objc_getAssociatedObject(self, &panGestureToggleKey) as? Bool) ?? true }
        
        set{
            
            for ges in gestureRecognizers { ges.isEnabled = newValue }
            
            objc_setAssociatedObject(self, &panGestureToggleKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
    }
    
    /// tap手势
    public var tapGestureRecognizer: UITapGestureRecognizer? {

        for ges in gestureRecognizers {
            
            if ges.isKind(of: UITapGestureRecognizer.classForCoder()) {
                
                return ges as? UITapGestureRecognizer
            }
        }
        
        return nil
    }
    
    /// tap手势启用
    public var tapGestureRecognizerEnabled: Bool {
        
        get{ return (objc_getAssociatedObject(self, &tapGestureToggleKey) as? Bool) ?? true }
        
        set{
            
            tapGestureRecognizer?.isEnabled = newValue
            
            objc_setAssociatedObject(self, &tapGestureToggleKey, newValue , objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
    }
}
