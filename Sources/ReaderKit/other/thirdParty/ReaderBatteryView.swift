//
//  ReaderBatteryView.swift
//  ReaderKit
//
//  Created by Asuna on 2025/12/08.
//

/// 电池宽推荐使用宽高
nonisolated(unsafe) public var ReaderBatterySize: CGSize = CGSize(width: 20, height: 10)

/// 电池量宽度 跟图片的比例
///
/// 取 14 而非原先的 16：切图按设计稿 Figma 253:40061 绘制，外壳占 19pt（余下 1pt 是正极头），
/// 扣掉 1pt 描边后内腔为 1~18pt。电量条从 inset=2pt 起算，若满电宽度仍为 16pt 会一直画到 18pt，
/// 顶死内腔右壁并与右描边、正极头连成一整块，满电时电池糊成实心块。
/// 改为 14pt 后满电覆盖 2~16pt，内腔右侧留出 2pt 间隙，20x10pt 下仍能辨出电池轮廓。
private var ReaderBatteryLevelWidth: CGFloat = 14
private var ReaderBatteryLevelScale = ReaderBatteryLevelWidth / ReaderBatterySize.width

import UIKit

open class ReaderBatteryView: UIImageView {

    /// 颜色
    open override var tintColor: UIColor! {
        
        didSet{ batteryLevelView.backgroundColor = tintColor }
    }
    
    /// BatteryLevel
    open var batteryLevel: Float = 0 {
        
        didSet{ setNeedsLayout() }
    }
    
    /// BatteryLevelView
    private var batteryLevelView: UIView!
    
    /// 初始化
    public convenience init() {
        
        self.init(frame: CGRect(x: 0, y: 0, width: ReaderBatterySize.width, height: ReaderBatterySize.height))
    }
    
    /// 初始化
    public override init(frame: CGRect) {
        
        super.init(frame: CGRect(x: 0, y: 0, width: ReaderBatterySize.width, height: ReaderBatterySize.height))
        
        addSubviews()
    }
    
    open func addSubviews() {
        
        // 进度
        batteryLevelView = UIView()
        batteryLevelView.layer.masksToBounds = true
        addSubview(batteryLevelView)
        
        // 设置样式：外壳走 template 渲染，与内部电量条一起跟随 tintColor 变主题色
        image = ReaderEnvironment.images.battery()
        tintColor = UIColor.white
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        let inset: CGFloat = 2
        
        let batteryLevelViewY: CGFloat = inset
        let batteryLevelViewX: CGFloat = inset
        let batteryLevelViewH: CGFloat = frame.height - inset * 2
        let batteryLevelViewW: CGFloat = frame.width * ReaderBatteryLevelScale
        let batteryLevelViewWScale: CGFloat = batteryLevelViewW / 100
        
        // 判断电量
        var tempBatteryLevel = batteryLevel
        
        if batteryLevel < 0 {
            
            tempBatteryLevel = 0
            
        }else if batteryLevel > 1 {
            
            tempBatteryLevel = 1
            
        }else{}
        
        batteryLevelView.frame = CGRect(x: batteryLevelViewX , y: batteryLevelViewY, width: CGFloat(tempBatteryLevel * 100) * batteryLevelViewWScale, height: batteryLevelViewH)
        batteryLevelView.layer.cornerRadius = batteryLevelViewH * 0.125
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


}
