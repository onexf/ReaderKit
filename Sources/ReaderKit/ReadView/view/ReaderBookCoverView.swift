//
//  ReaderBookCoverView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/13.
//

import UIKit

open class ReaderBookCoverView: UIView {
    
    /// 书籍名称
    private var name: UILabel!
    
    /// 当前阅读模型
    open var readModel: ReaderBookModel! {
        
        didSet{
            
            name.text = readModel.bookName
        }
    }

    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        // 书籍名称
        name = UILabel()
        name.textAlignment = .center
        name.font = ReaderFonts.systemBold(50)
        name.textColor = ReaderConfiguration.shared().textColor
        name.numberOfLines = 0
        addSubview(name)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        name.frame = bounds
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
