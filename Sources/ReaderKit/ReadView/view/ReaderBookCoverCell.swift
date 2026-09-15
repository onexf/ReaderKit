//
//  ReaderBookCoverCell.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/11.
//

import UIKit

open class ReaderBookCoverCell: UITableViewCell {

    /// 书籍首页视图
    public private(set) var homeView: ReaderBookCoverView!
    
    public class func cell(_ tableView: UITableView) ->ReaderBookCoverCell {
        
        var cell = tableView.dequeueReusableCell(withIdentifier: "ReaderBookCoverCell")
        
        if cell == nil {
            
            cell = ReaderBookCoverCell(style: UITableViewCell.CellStyle.default, reuseIdentifier: "ReaderBookCoverCell")
        }
        
        return cell as! ReaderBookCoverCell
    }
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        backgroundColor = UIColor.clear
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        // 书籍首页
        homeView = ReaderBookCoverView()
        contentView.addSubview(homeView)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        homeView.frame = bounds
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
