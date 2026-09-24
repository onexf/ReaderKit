//
//  ReaderMenuProgressPanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

open class ReaderMenuProgressPanel: ReaderMenuPanel {
    
    /// 上一章
    private var priorChapterButton: UIButton!
    
    /// 进度
    private var slider: ReaderProgressSlider!
    
    /// 下一章
    private var followingChapterButton: UIButton!
    
    public override init(frame: CGRect) { super.init(frame: frame) }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        backgroundColor = UIColor.clear
        
        // 上一章
        priorChapterButton = UIButton(type:.custom)
        priorChapterButton.titleLabel?.font = READER_FONT_SA_14
        priorChapterButton.setTitle(ReaderEnvironment.strings.priorChapterTitle, for: .normal)
        priorChapterButton.setTitleColor(READER_COLOR_MENU_COLOR, for: .normal)
        priorChapterButton.addAction(UIAction { [weak self] _ in self?.goToPriorChapter() }, for: .touchUpInside)
        addSubview(priorChapterButton)
        
        // 下一章
        followingChapterButton = UIButton(type:.custom)
        followingChapterButton.titleLabel?.font = READER_FONT_SA_14
        followingChapterButton.setTitle(ReaderEnvironment.strings.followingChapterTitle, for: .normal)
        followingChapterButton.setTitleColor(READER_COLOR_MENU_COLOR, for: .normal)
        followingChapterButton.addAction(UIAction { [weak self] _ in self?.goToFollowingChapter() }, for: .touchUpInside)
        addSubview(followingChapterButton)
        
        // 进度条
        slider = ReaderProgressSlider()
        slider.setThumbImage(ReaderEnvironment.images.progressThumb(), for: .normal)
        // 气泡文案：总进度显示百分比，分页进度显示页码
        slider.bubbleTextProvider = { [weak self] value in
            return self?.bubbleText(for: value) ?? ""
        }
        // 拖动结束后跳转（原 sliderWillHidePopUpView 的时机）
        slider.onDragFinished = { [weak self] value in
            self?.commitProgress(value)
        }
        // 气泡背景颜色
        slider.bubbleColor = READER_COLOR_MAIN
        // 气泡字体颜色
        slider.bubbleTextColor = READER_COLOR_MENU_COLOR
        // 气泡字体走注入点，库内默认系统粗体
        slider.bubbleFont = ReaderEnvironment.fonts.progressBubble(22)
        // 气泡箭头高度
        slider.bubbleArrowLength = READER_SPACE_SA_5
        // 当前进度颜色
        slider.minimumTrackTintColor = READER_COLOR_MAIN
        // 总进度颜色
        slider.maximumTrackTintColor = READER_COLOR_MENU_COLOR
        // 当前拖拽圆圈颜色
        slider.tintColor = READER_COLOR_MENU_COLOR
        addSubview(slider)
        reloadProgress()
    }
    
    /// 刷新阅读进度显示
    open func reloadProgress() {
       
        // 有阅读数据
        let bookModel = hostMenu.vc.bookModel
        
        // 有阅读记录以及章节数据
        if bookModel != nil && (bookModel?.readingRecord?.activeChapter != nil) {
            
            if ReaderConfiguration.shared().progressType == .total { // 总进度
                
                slider.minimumValue = 0
                slider.maximumValue = 1
                slider.value = ReaderProgress.ratio(bookModel: bookModel, readingRecord: bookModel?.readingRecord)
                
            }else{ // 分页进度
                
                slider.minimumValue = 1
                slider.maximumValue = bookModel!.readingRecord.activeChapter.pageCount.floatValue
                slider.value = bookModel!.readingRecord.page.floatValue + 1
            }
            
        }else{ // 没有则清空
            
            slider.minimumValue = 0
            slider.maximumValue = 0
            slider.value = 0
        }
    }
    
    /// 上一章
    open func goToPriorChapter() {
        
        hostMenu?.delegate?.readerMenuDidTapPreviousChapter(hostMenu)
    }
    
    /// 下一章
    open func goToFollowingChapter() {
        
        hostMenu?.delegate?.readerMenuDidTapNextChapter(hostMenu)
    }
    
    // MARK: 气泡文案
    
    /// 气泡上显示的文案
    private func bubbleText(for value: Float) -> String {
        
        if ReaderConfiguration.shared().progressType == .total { // 总进度
            
            // 如果有需求可显示章节名
            return ReaderProgress.text(progress: value)
            
        }else{ // 分页进度
            
            return "\(NSInteger(value))"
        }
    }
    
    // MARK: 拖动提交
    
    /// 拖动结束后按当前值跳转
    private func commitProgress(_ sliderValue: Float) {
  
        if ReaderConfiguration.shared().progressType == .total { // 总进度
            
            // 有阅读数据
            let bookModel = hostMenu.vc.bookModel
            
            // 有阅读记录以及章节数据
            if bookModel != nil && (bookModel?.readingRecord?.activeChapter != nil) {
                
                // 总章节个数
                let count = (bookModel!.catalogueEntries.count - 1)
                
                // 获得当前进度的章节索引
                let index = NSInteger(Float(count) * sliderValue)
                
                // 获得章节列表模型
                let chapterListModel = bookModel!.catalogueEntries[index]
                
                // 页码
                let toPage = (index == count) ? READER_LAST_PAGE : 0
                
                // 传递。章节 id 缺失就不回调 —— 过去这里把 NSNumber! 原样递出去,
                // 宿主侧再 .intValue 才崩,崩的地方离成因很远。
                if let hostMenu, let chapterID = chapterListModel.id?.intValue {
                    hostMenu.delegate?.readerMenu(hostMenu, didSeekToChapter: chapterID, page: toPage)
                }
            }
            
        }else{ // 分页进度
            
            if let hostMenu {
                hostMenu.delegate?.readerMenu(hostMenu, didSeekToPage: Int(sliderValue - 1))
            }
        }
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let w = frame.size.width
        let h = frame.size.height
        let buttonW = READER_SPACE_SA_55
        
        // 上一章
        priorChapterButton.frame = CGRect(x: READER_SPACE_SA_5, y: 0, width: buttonW, height: h)
        
        // 下一章
        followingChapterButton.frame = CGRect(x: w - buttonW - READER_SPACE_SA_5, y: 0, width: buttonW, height: h)
        
        // 进度条
        let sliderX = priorChapterButton.frame.maxX + READER_SPACE_SA_10
        let sliderW = w - 2 * sliderX
        slider.frame = CGRect(x: sliderX, y: 0, width: sliderW, height: h)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
