//
//  ReaderStatusTopView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/08.
//

import UIKit

/// topView 高度
public let READER_STATUS_TOP_VIEW_HEIGHT: CGFloat = 44

/// 阅读器页眉
///
/// 按设计稿（Figma 阅读器 162:8599）页眉只展示章节名：
/// - 时间与电池已下移到页脚 `ReaderStatusBottomView`
/// - 正文页不显示返回按钮；空态页与书末页需要保留退出入口，创建后显式把 `showsBackButton` 置 true
open class ReaderStatusTopView: UIView {

    /// 返回按钮点击回调
    open var onBackTapped: (() -> Void)?

    /// 是否显示返回按钮（默认不显示，与设计稿一致）
    open var showsBackButton: Bool = false {
        didSet {
            backButton.isHidden = !showsBackButton
            setNeedsLayout()
        }
    }

    /// 返回按钮
    private var backButton: UIButton!

    /// 书名
    public private(set) var bookName: UILabel!
    
    /// 章节名
    public private(set) var chapterName: UILabel!
    
    /// 设计稿中章节名距页眉顶部的内边距
    private let chapterNameTopInset: CGFloat = 10
    
    /// 返回按钮图标尺寸
    private let backIconSize: CGFloat = 18
    
    /// 返回按钮点击区域尺寸（大于图标，便于点击）
    private let backButtonTapSize: CGFloat = 36
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        addSubviews()
    }
    
    private func addSubviews() {
        
        // 返回按钮（默认隐藏，仅空态页与书末页显示）
        backButton = UIButton(type: .custom)
        backButton.setImage(ReaderEnvironment.images.statusBarBack(), for: .normal)
        backButton.tintColor = ReaderConfiguration.shared().currentThemeColors.textT2
        backButton.addTarget(self, action: #selector(clickBack), for: .touchUpInside)
        backButton.isHidden = true
        addSubview(backButton)
        
        // 书名
        bookName = UILabel()
        bookName.font = READER_FONT_SA_10
        bookName.textColor = ReaderConfiguration.shared().statusTextColor
        bookName.textAlignment = .left
        bookName.isHidden = true
        addSubview(bookName)
        
        // 章节名
        chapterName = UILabel()
        // 设计稿 Reader/Subtitle：Newsreader Medium 12，颜色 textT2
        chapterName.font = ReaderEnvironment.fonts.chapterHeader(readerScaled(12))
        chapterName.textColor = ReaderConfiguration.shared().currentThemeColors.textT2
        chapterName.textAlignment = .left
        addSubview(chapterName)
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let w = frame.size.width
        let h = frame.size.height
        
        // 获取当前视图在屏幕中的位置，保证内容始终距屏幕左边 20
        var offsetX: CGFloat = 0
        if let window = self.window {
            let frameInWindow = self.convert(self.bounds, to: window)
            offsetX = frameInWindow.minX
        }
        let leftMargin = max(0, READER_SPACE_SA_20 - offsetX)
        
        // 书名（已隐藏）
        bookName.frame = CGRect(x: 0, y: 0, width: 0, height: h)
        
        // 章节名所在文本行：设计稿 padding 10px 0，顶部对齐
        let chapterNameHeight = ceil(chapterName.font.lineHeight)
        var chapterNameX = leftMargin
        
        if showsBackButton {
            
            // 返回按钮：图标 18x18 居中于 36x36 点击区，与章节名同行垂直居中
            let backButtonX = leftMargin - (backButtonTapSize - backIconSize) / 2
            let backButtonY = chapterNameTopInset + (chapterNameHeight - backButtonTapSize) / 2
            backButton.frame = CGRect(x: backButtonX, y: backButtonY, width: backButtonTapSize, height: backButtonTapSize)
            
            // 章节名：在返回按钮右边，间距 4
            chapterNameX = leftMargin + backIconSize + 4
            
        } else {
            
            backButton.frame = .zero
        }
        
        chapterName.frame = CGRect(x: chapterNameX, y: chapterNameTopInset, width: max(0, w - chapterNameX), height: chapterNameHeight)
    }
    
    // MARK: - 返回
    
    @objc private func clickBack() {
        if let callback = onBackTapped {
            callback()
        } else {
            // 兜底：沿响应链找到阅读主控制器
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let reader = next as? ReaderViewController {
                    reader.handleMenuBack()
                    return
                }
                responder = next
            }
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更新主题颜色
    open func reviseColors() {
        let themeColors = ReaderConfiguration.shared().currentThemeColors
        bookName.textColor = ReaderConfiguration.shared().statusTextColor
        chapterName.textColor = themeColors.textT2
        backButton.tintColor = themeColors.textT2
    }
}
