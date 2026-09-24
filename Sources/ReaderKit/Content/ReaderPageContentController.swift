//
//  ReaderPageContentController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/08.
//

import UIKit

open class ReaderPageContentController: ReaderScreenController {
    
    /// 当前页阅读记录对象
    open var readingRecord: ReaderReadRecordModel!

    /// 阅读对象(用于显示书名以及书籍首页显示书籍信息)
    open weak var bookModel: ReaderBookModel!
    
    /// 顶部状态栏
    open var topView: ReaderStatusTopView!
    
    /// 底部状态栏
    open var statusFooter: ReaderStatusBottomView!
    
    /// 页码（仅翻页模式左下角显示：当前页/章节总页数）
    private var folioLabel: UILabel!
    
    /// 阅读视图
    private var pageView: ReaderPageView!
    
    /// 书籍首页视图
    private var coverPage: ReaderBookCoverView!
    /// 当前承载正文渲染的视图，供朗读高亮等跨文件能力取用。
    ///
    /// 为什么用转发入口而不是把 `pageView` 直接放开为 internal：
    /// 子类 `ReaderLongPressController` 声明了同名的 `pageView`（类型是
    /// `ReaderPageView` 的子类 `ReaderLongPressView`）。两个 `pageView` 现在能共存，
    /// 恰恰是因为本类这个是 `private`、对子类不可见，不构成 override 关系。
    /// 一旦放开为 internal，子类的存储属性就会与继承来的属性冲突（Swift 不允许
    /// 用存储属性 override 属性），编译不过。
    ///
    /// 改成可重写的计算属性后，调用方拿到的始终是「这一页实际在渲染的那个视图」，
    /// 不必关心自己面对的是哪个子类。
    /// - Returns: 书名页（`isHomePage`）没有正文视图，此时返回 nil。
    open var renderingPageView: ReaderPageView? { pageView }
    
    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // 设置阅读背景
        view.backgroundColor = ReaderConfiguration.shared().bgColor
        
        // 刷新阅读进度
        reloadProgress()
    }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        // 阅读使用范围
        let readRect = READER_RECT!
        
        // 左右翻页模式（Left&Right）下，页眉与页脚由父控制器统一持有（固定不动，不随翻页动画走），
        // 单页只负责左下角页码；上下滚动模式则由 ReaderScrollController 自己持有。
        let isPageTurnMode = ReaderConfiguration.shared().effectType == .translation
        
        // 顶部状态栏
        topView = ReaderStatusTopView()
        topView.storyName.text = bookModel.storyName
        topView.chapterTitleLabel.text = readingRecord.activeChapter.name
        view.addSubview(topView)
        topView.frame = CGRect(x: readRect.minX, y: readRect.minY, width: readRect.width, height: READER_STATUS_TOP_VIEW_HEIGHT)
        topView.isHidden = isPageTurnMode
        
        // 底部状态栏
        statusFooter = ReaderStatusBottomView()
        view.addSubview(statusFooter)
        statusFooter.frame = CGRect(x: readRect.minX, y: readRect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT, width: readRect.width, height: READER_STATUS_BOTTOM_VIEW_HEIGHT)
        statusFooter.isHidden = isPageTurnMode
        
        // 页码（仅 Left&Right 翻页模式在左下角显示，位于正文下方预留的页码区内，左边缘与正文对齐）
        folioLabel = UILabel()
        // 设计稿 Reader/Page Number：Regular 12，颜色 textSubtle，与页脚信息栏同为 60% 透明度
        folioLabel.font = ReaderEnvironment.fonts.uiRegular(readerScaled(12))
        folioLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textSubtle
        folioLabel.textAlignment = .left
        folioLabel.alpha = 0.6
        view.addSubview(folioLabel)
        let pageNumberBandTop = readRect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT
        folioLabel.frame = CGRect(x: readRect.minX,
                                       y: pageNumberBandTop + ReaderStatusBottomView.contentTopInset,
                                       width: readRect.width,
                                       height: ReaderStatusBottomView.contentHeight)
        folioLabel.isHidden = !isPageTurnMode
        
        // 阅读视图
        initReadView()
    }
    
    /// 初始化阅读视图
    open func initReadView() {
        
        // 翻页与滚动模式的阅读区域差异已统一在 READER_VIEW_RECT 中处理：
        // 翻页模式从顶栏下方延伸到底部页码区上方，滚动模式与顶栏有 -10 重叠。
        let viewRect: CGRect = READER_VIEW_RECT
        
        // 是否为书籍首页
        if readingRecord.layoutPage.isHomePage {
            
            topView.isHidden = true
            statusFooter.isHidden = true
            folioLabel.isHidden = true
            
            coverPage = ReaderBookCoverView()
            coverPage.bookModel = bookModel
            view.addSubview(coverPage)
            coverPage.frame = viewRect
            
        }else{
            
            pageView = ReaderPageView()
            pageView.content = readingRecord.contentAttributedString
            view.addSubview(pageView)
            pageView.frame = viewRect
        }
    }
    
    /// 刷新阅读进度显示
    private func reloadProgress() {
        
        // 左下角页码：始终显示「当前页/章节总页数」，与进度类型设置无关
        if let chapterModel = readingRecord.activeChapter, !readingRecord.layoutPage.isHomePage {
            folioLabel.text = "\(readingRecord.page.intValue + 1)/\(chapterModel.pageCount.intValue)"
        }
        
    }
    
    deinit {
        
        statusFooter?.discardClock()
    }
}
