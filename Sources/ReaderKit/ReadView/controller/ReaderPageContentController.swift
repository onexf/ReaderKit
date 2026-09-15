//
//  ReaderPageContentController.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/08.
//

import UIKit

open class ReaderPageContentController: ReaderScreenController {
    
    /// 当前页阅读记录对象
    open var recordModel: ReaderReadRecordModel!

    /// 阅读对象(用于显示书名以及书籍首页显示书籍信息)
    open weak var readModel: ReaderBookModel!
    
    /// 顶部状态栏
    open var topView: ReaderStatusTopView!
    
    /// 底部状态栏
    open var bottomView: ReaderStatusBottomView!
    
    /// 页码（仅翻页模式左下角显示：当前页/章节总页数）
    private var pageNumberLabel: UILabel!
    
    /// 阅读视图
    private var readView: ReaderPageView!
    
    /// 书籍首页视图
    private var homeView: ReaderBookCoverView!
    
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
        topView.storyName.text = readModel.storyName
        topView.chapterName.text = recordModel.chapterModel.name
        view.addSubview(topView)
        topView.frame = CGRect(x: readRect.minX, y: readRect.minY, width: readRect.width, height: READER_STATUS_TOP_VIEW_HEIGHT)
        topView.isHidden = isPageTurnMode
        
        // 底部状态栏
        bottomView = ReaderStatusBottomView()
        view.addSubview(bottomView)
        bottomView.frame = CGRect(x: readRect.minX, y: readRect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT, width: readRect.width, height: READER_STATUS_BOTTOM_VIEW_HEIGHT)
        bottomView.isHidden = isPageTurnMode
        
        // 页码（仅 Left&Right 翻页模式在左下角显示，位于正文下方预留的页码区内，左边缘与正文对齐）
        pageNumberLabel = UILabel()
        // 设计稿 Reader/Page Number：Regular 12，颜色 textT2，与页脚信息栏同为 60% 透明度
        pageNumberLabel.font = ReaderEnvironment.fonts.uiRegular(readerScaled(12))
        pageNumberLabel.textColor = ReaderConfiguration.shared().currentThemeColors.textT2
        pageNumberLabel.textAlignment = .left
        pageNumberLabel.alpha = 0.6
        view.addSubview(pageNumberLabel)
        let pageNumberBandTop = readRect.maxY - READER_STATUS_BOTTOM_VIEW_HEIGHT
        pageNumberLabel.frame = CGRect(x: readRect.minX,
                                       y: pageNumberBandTop + ReaderStatusBottomView.contentTopInset,
                                       width: readRect.width,
                                       height: ReaderStatusBottomView.contentHeight)
        pageNumberLabel.isHidden = !isPageTurnMode
        
        // 阅读视图
        initReadView()
    }
    
    /// 初始化阅读视图
    open func initReadView() {
        
        // 翻页与滚动模式的阅读区域差异已统一在 READER_VIEW_RECT 中处理：
        // 翻页模式从顶栏下方延伸到底部页码区上方，滚动模式与顶栏有 -10 重叠。
        let viewRect: CGRect = READER_VIEW_RECT
        
        // 是否为书籍首页
        if recordModel.pageModel.isHomePage {
            
            topView.isHidden = true
            bottomView.isHidden = true
            pageNumberLabel.isHidden = true
            
            homeView = ReaderBookCoverView()
            homeView.readModel = readModel
            view.addSubview(homeView)
            homeView.frame = viewRect
            
        }else{
            
            readView = ReaderPageView()
            readView.content = recordModel.contentAttributedString
            view.addSubview(readView)
            readView.frame = viewRect
        }
    }
    
    /// 刷新阅读进度显示
    private func reloadProgress() {
        
        // 左下角页码：始终显示「当前页/章节总页数」，与进度类型设置无关
        if let chapterModel = recordModel.chapterModel, !recordModel.pageModel.isHomePage {
            pageNumberLabel.text = "\(recordModel.page.intValue + 1)/\(chapterModel.pageCount.intValue)"
        }
        
    }
    
    deinit {
        
        bottomView?.discardClock()
    }
}
