//
//  ReaderPageView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/10/19.
//

import UIKit

open class ReaderPageView: UIView {
    
    /// 当前页模型(使用contentSize绘制)
    open var pageModel: ReaderPageModel! {
        
        didSet{
            
            // 打印内容的段落样式信息
            if pageModel != nil && pageModel.showContent.length > 0 {
                // log("=== 阅读内容调试信息 (pageModel) ===")
                // log("内容长度: \(pageModel.showContent.length)")
                // log("内容前100字符: \(pageModel.showContent.string.prefix(100))")
                // log("headType: \(pageModel.headType.rawValue)")
                // log("headTypeHeight: \(pageModel.headTypeHeight)")
                // log("contentSize: \(pageModel.contentSize)")
                // log("page: \(pageModel.page?.intValue ?? -1)")
                
                // 获取第一个字符的属性
                let attributes = pageModel.showContent.attributes(at: 0, effectiveRange: nil)
                if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                    // log("段落样式:")
                    // log("  - lineSpacing: \(paragraphStyle.lineSpacing)")
                    // log("  - paragraphSpacing: \(paragraphStyle.paragraphSpacing)")
                    // log("  - paragraphSpacingBefore: \(paragraphStyle.paragraphSpacingBefore)")
                    // log("  - firstLineHeadIndent: \(paragraphStyle.firstLineHeadIndent)")
                    // log("  - headIndent: \(paragraphStyle.headIndent)")
                    // log("  - alignment: \(paragraphStyle.alignment.rawValue)")
                }
                
                if let font = attributes[.font] as? UIFont {
                    // log("字体:")
                    // log("  - fontName: \(font.fontName)")
                    // log("  - pointSize: \(font.pointSize)")
                }
                // log("========================")
            }
            
            frameRef = ReaderCoreText.makeFrame(attrString: pageModel.showContent, rect: CGRect(origin: CGPoint.zero, size: pageModel.contentSize))
        }
    }
    
    /// 当前页内容(使用固定范围绘制)
    open var content: NSAttributedString! {
        
        didSet{
            
            // 打印内容的段落样式信息
            if content.length > 0 {
                // log("=== 阅读内容调试信息 ===")
                // log("内容长度: \(content.length)")
                // log("内容前100字符: \(content.string.prefix(100))")
                
                // 获取第一个字符的属性
                let attributes = content.attributes(at: 0, effectiveRange: nil)
                if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                    // log("段落样式:")
                    // log("  - lineSpacing: \(paragraphStyle.lineSpacing)")
                    // log("  - paragraphSpacing: \(paragraphStyle.paragraphSpacing)")
                    // log("  - paragraphSpacingBefore: \(paragraphStyle.paragraphSpacingBefore)")
                    // log("  - firstLineHeadIndent: \(paragraphStyle.firstLineHeadIndent)")
                    // log("  - headIndent: \(paragraphStyle.headIndent)")
                    // log("  - alignment: \(paragraphStyle.alignment.rawValue)")
                }
                
                if let font = attributes[.font] as? UIFont {
                    // log("字体:")
                    // log("  - fontName: \(font.fontName)")
                    // log("  - pointSize: \(font.pointSize)")
                }
                // log("========================")
            }
            
            frameRef = ReaderCoreText.makeFrame(attrString: content, rect: CGRect(origin: CGPoint.zero, size: READER_VIEW_RECT.size))
        }
    }
    
    /// CTFrame
    open var frameRef: CTFrame? {
        
        didSet{
            
            if frameRef != nil { setNeedsDisplay() }
        }
    }
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        // 正常使用
        backgroundColor = UIColor.clear
    }
    
    /// 绘制
    open override func draw(_ rect: CGRect) {
        
        if (frameRef == nil) {return}
        
        let ctx = UIGraphicsGetCurrentContext()
        
        ctx?.textMatrix = CGAffineTransform.identity
        
        ctx?.translateBy(x: 0, y: bounds.size.height);
        
        ctx?.scaleBy(x: 1.0, y: -1.0);
        
        CTFrameDraw(frameRef!, ctx!);
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
