//
//  ReaderTableView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

open class ReaderTableView: UITableView {

    public override init(frame: CGRect, style: UITableView.Style) {
        
        super.init(frame: frame, style: style)
        
        backgroundColor = UIColor.clear
        
        separatorStyle = .none
        
        if #available(iOS 11.0, *) {
            
            contentInsetAdjustmentBehavior = .never
            estimatedRowHeight = 0
            estimatedSectionFooterHeight = 0
            estimatedSectionHeaderHeight = 0
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
