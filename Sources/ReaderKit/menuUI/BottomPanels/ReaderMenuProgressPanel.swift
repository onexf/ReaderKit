//
//  ReaderMenuProgressPanel.swift
//  ReaderKit
//
//  Created by Asuna on 2025/11/15.
//

import UIKit

open class ReaderMenuProgressPanel: ReaderMenuPanel {
    
    /// 上一章
    private var previousChapter: UIButton!
    
    /// 进度
    private var slider: ReaderProgressSlider!
    
    /// 下一章
    private var nextChapter: UIButton!
    
    public override init(frame: CGRect) { super.init(frame: frame) }
    
    open override func addSubviews() {
        
        super.addSubviews()
        
        backgroundColor = UIColor.clear
        
        // 上一章
        previousChapter = UIButton(type:.custom)
        previousChapter.titleLabel?.font = READER_FONT_SA_14
        previousChapter.setTitle(ReaderEnvironment.strings.previousChapter, for: .normal)
        previousChapter.setTitleColor(READER_COLOR_MENU_COLOR, for: .normal)
        previousChapter.addAction(UIAction { [weak self] _ in self?.clickPreviousChapter() }, for: .touchUpInside)
        addSubview(previousChapter)
        
        // 下一章
        nextChapter = UIButton(type:.custom)
        nextChapter.titleLabel?.font = READER_FONT_SA_14
        nextChapter.setTitle(ReaderEnvironment.strings.nextChapter, for: .normal)
        nextChapter.setTitleColor(READER_COLOR_MENU_COLOR, for: .normal)
        nextChapter.addAction(UIAction { [weak self] _ in self?.clickNextChapter() }, for: .touchUpInside)
        addSubview(nextChapter)
        
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
        let readModel = readMenu.vc.readModel
        
        // 有阅读记录以及章节数据
        if readModel != nil && (readModel?.recordModel?.chapterModel != nil) {
            
            if ReaderConfiguration.shared().progressType == .total { // 总进度
                
                slider.minimumValue = 0
                slider.maximumValue = 1
                slider.value = ReaderProgress.ratio(readModel: readModel, recordModel: readModel?.recordModel)
                
            }else{ // 分页进度
                
                slider.minimumValue = 1
                slider.maximumValue = readModel!.recordModel.chapterModel.pageCount.floatValue
                slider.value = readModel!.recordModel.page.floatValue + 1
            }
            
        }else{ // 没有则清空
            
            slider.minimumValue = 0
            slider.maximumValue = 0
            slider.value = 0
        }
    }
    
    /// 上一章
    open func clickPreviousChapter() {
        
        readMenu?.delegate?.readerMenuDidTapPreviousChapter(readMenu)
    }
    
    /// 下一章
    open func clickNextChapter() {
        
        readMenu?.delegate?.readerMenuDidTapNextChapter(readMenu)
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
            let readModel = readMenu.vc.readModel
            
            // 有阅读记录以及章节数据
            if readModel != nil && (readModel?.recordModel?.chapterModel != nil) {
                
                // 总章节个数
                let count = (readModel!.chapterListModels.count - 1)
                
                // 获得当前进度的章节索引
                let index = NSInteger(Float(count) * sliderValue)
                
                // 获得章节列表模型
                let chapterListModel = readModel!.chapterListModels[index]
                
                // 页码
                let toPage = (index == count) ? READER_LAST_PAGE : 0
                
                // 传递。章节 id 缺失就不回调 —— 过去这里把 NSNumber! 原样递出去,
                // 宿主侧再 .intValue 才崩,崩的地方离成因很远。
                if let readMenu, let chapterID = chapterListModel.id?.intValue {
                    readMenu.delegate?.readerMenu(readMenu, didSeekToChapter: chapterID, page: toPage)
                }
            }
            
        }else{ // 分页进度
            
            if let readMenu {
                readMenu.delegate?.readerMenu(readMenu, didSeekToPage: Int(sliderValue - 1))
            }
        }
    }
    
    open override func layoutSubviews() {
        
        super.layoutSubviews()
        
        let w = frame.size.width
        let h = frame.size.height
        let buttonW = READER_SPACE_SA_55
        
        // 上一章
        previousChapter.frame = CGRect(x: READER_SPACE_SA_5, y: 0, width: buttonW, height: h)
        
        // 下一章
        nextChapter.frame = CGRect(x: w - buttonW - READER_SPACE_SA_5, y: 0, width: buttonW, height: h)
        
        // 进度条
        let sliderX = previousChapter.frame.maxX + READER_SPACE_SA_10
        let sliderW = w - 2 * sliderX
        slider.frame = CGRect(x: sliderX, y: 0, width: sliderW, height: h)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
