//
//  ReaderPageCell.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/05.
//

import UIKit

open class ReaderPageCell: UITableViewCell {

    /// 阅读视图
    private var readView: ReaderPageView!
    
    /// 当前承载正文渲染的视图，供朗读高亮等跨文件能力取用。
    ///
    /// 与 `ReaderPageContentController.renderingPageView` 同名同语义，
    /// 让编排层不必区分「翻页模式的页控制器」与「滚动模式的 cell」。
    ///
    /// 高亮的清理不在这里做：`ReaderPageView` 换 `pageModel` 时会自行清掉，
    /// 复用路径必然经过那里，放在视图层更不容易漏。
    open var renderingPageView: ReaderPageView? { readView }
    
    open var pageModel: ReaderPageModel! {
        
        didSet{
            
            readView.pageModel = pageModel
            
            setNeedsLayout()
        }
    }
    
    public class func cell(_ tableView: UITableView) ->ReaderPageCell {
        
        var cell = tableView.dequeueReusableCell(withIdentifier: "ReaderPageCell")
        
        if cell == nil {
            
            cell = ReaderPageCell(style: UITableViewCell.CellStyle.default, reuseIdentifier: "ReaderPageCell")
        }
        
        return cell as! ReaderPageCell
    }
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        backgroundColor = UIColor.clear
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        // 阅读视图
        readView = ReaderPageView()
        contentView.addSubview(readView)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
      
        // 分页顶部高度
        let y = pageModel?.headTypeHeight ?? READER_SPACE_MIN_HEIGHT
        
        // 内容高度
        let h = pageModel?.contentSize.height ?? READER_SPACE_MIN_HEIGHT

        readView.frame = CGRect(x: 0, y: y, width: READER_VIEW_RECT.width, height: h)
        
        // 打印第一页的布局信息
        if pageModel?.page?.intValue == 0 {
            // log("=== Cell 布局调试信息 (第一页) ===")
            // log("cell.frame: \(self.frame)")
            // log("cell.contentView.frame: \(self.contentView.frame)")
            // log("readView.frame: \(readView.frame)")
            // log("y (headTypeHeight): \(y)")
            // log("h (contentSize.height): \(h)")
            // log("========================")
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
