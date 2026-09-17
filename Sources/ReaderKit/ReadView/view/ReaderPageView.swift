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
            
            sourceAttributedText = pageModel.showContent
            
            sourceRect = CGRect(origin: CGPoint.zero, size: pageModel.contentSize)
            
            // 页数据换了就把朗读高亮清掉。
            //
            // 这一行是滚动模式的必需品：ReaderPageCell 会被 UITableView 复用，
            // 复用时只重设 pageModel，若不清高亮，上一页的高亮矩形会留在新页上
            // （表现为高亮出现在没在朗读的段落上）。放在这里而不是 cell 里，
            // 是因为两种阅读模式都经本 setter 换页，一处清理即可覆盖，也不会被漏掉。
            //
            // 代价：滚出屏幕再滚回来的页会丢失高亮，需要由编排层在页重新可见时补设。
            highlightRange = nil
            
            rebuildFrameRef()
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
            
            sourceAttributedText = content
            
            sourceRect = CGRect(origin: CGPoint.zero, size: READER_VIEW_RECT.size)
            
            // 换页即清朗读高亮，理由同 pageModel setter
            highlightRange = nil
            
            rebuildFrameRef()
        }
    }
    
    /// CTFrame
    open var frameRef: CTFrame? {
        
        didSet{
            
            if frameRef != nil { setNeedsDisplay() }
        }
    }
    
    
    // MARK: - 朗读高亮
    
    /// 当前朗读句在**本页内**的范围。为 nil 时不绘制高亮。
    ///
    /// 注意坐标基准是**页内**，不是章内：编排层拿到的句范围是章内绝对坐标，
    /// 需要先与 `ReaderPageModel.range` 求交集、再平移 `-range.location` 才能传进来。
    open var speechHighlightRange: NSRange? {
        
        get { highlightRange }
        
        set {
            
            guard newValue != highlightRange else { return }
            
            highlightRange = newValue
            
            applyHighlightAlter()
        }
    }
    
    /// 高亮范围的实际存储。
    ///
    /// 用私有存储 + 计算属性而不是直接 `didSet`：换页时需要「静默清空」
    /// （不触发重建，因为紧接着就会用新数据重建一次），直接写这个存储即可绕过副作用。
    private var highlightRange: NSRange?
    
    /// 构建 CTFrame 用的源富文本。留着它才能在文字变色样式下重建带高亮属性的 frame。
    private var sourceAttributedText: NSAttributedString?
    
    /// 构建 CTFrame 用的排版范围。
    private var sourceRect: CGRect = CGRect.zero
    
    /// 下划线样式的线宽
    private let highlightUnderlineHeight: CGFloat = 1.5
    
    /// 高亮变化后刷新显示。
    private func applyHighlightAlter() {
        
        // 背景色块与下划线都是在既有 CTFrame 之外叠一层绘制，重绘即可；
        // 文字变色改的是字形前景色，属于排版属性，必须重建 CTFrame。
        //
        // ⚠️ 因此 .textColor 样式每换一句就要重建一次 CTFrame（整页重新排版）。
        // 默认样式是 .background 正是为了避开这个开销；接入方若选 .textColor，
        // 需要在老机型（iPhone SE 2 一档）上确认滚动与朗读同时进行时不掉帧。
        if ReaderEnvironment.speechHighlightStyle == .textColor {
            
            rebuildFrameRef()
            
        }else{
            
            setNeedsDisplay()
        }
    }
    
    /// 依据当前源文本与高亮样式重建 CTFrame。
    private func rebuildFrameRef() {
        
        guard let sourceAttributedText else {
            
            frameRef = nil
            
            return
        }
        
        var typesetSource = sourceAttributedText
        
        if ReaderEnvironment.speechHighlightStyle == .textColor,
           let range = clampedHighlightRange(limit: sourceAttributedText.length) {
            
            let tinted = NSMutableAttributedString(attributedString: sourceAttributedText)
            
            tinted.addAttribute(.foregroundColor,
                                value: ReaderConfiguration.shared().currentThemeColors.speechHighlightText,
                                range: range)
            
            typesetSource = tinted
        }
        
        frameRef = ReaderCoreText.makeFrame(attrString: typesetSource, rect: sourceRect)
    }
    
    /// 把高亮范围夹到源文本长度内。
    ///
    /// 必要性：句范围来自章内坐标换算，而本页的富文本长度由分页决定，
    /// 两者在重新分页（改字号 / 行高 / 主题）的瞬间可能短暂不一致。
    /// 不夹取就会在 CoreText 里越界。
    private func clampedHighlightRange(limit: Int) -> NSRange? {
        
        guard let highlightRange,
              highlightRange.location != NSNotFound,
              highlightRange.length > 0,
              highlightRange.location < limit else { return nil }
        
        let end = min(NSMaxRange(highlightRange), limit)
        
        return NSMakeRange(highlightRange.location, end - highlightRange.location)
    }
    
    /// 当前朗读高亮在**本视图坐标系**（UIKit，y 轴向下）里的外接矩形。未高亮时为 nil。
    ///
    /// `ReaderCoreText.rangeRects` 给的是 CoreText 坐标（y 轴向上、原点在左下），
    /// 这里统一翻回 UIKit，调用方（滚动容器判断要不要滚、往哪滚）就不必关心坐标系差异。
    ///
    /// 多行句返回各行矩形的并集：滚动跟随只关心纵向区间，逐行处理没有意义。
    open var speechHighlightRectInView: CGRect? {
        
        guard let sourceAttributedText,
              let range = clampedHighlightRange(limit: sourceAttributedText.length) else { return nil }
        
        let rects = ReaderCoreText.rangeRects(range: range,
                                              frameRef: frameRef,
                                              content: sourceAttributedText.string)
        
        guard let first = rects.first else { return nil }
        
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        
        return CGRect(x: union.minX,
                      y: bounds.height - union.maxY,
                      width: union.width,
                      height: union.height)
    }
    
    /// 本视图坐标系里某一点落在第几个字符上。定位不到时返回 nil。
    ///
    /// 供滚动容器求「屏幕最顶端那一行的首字符」，从而把朗读起点定到用户**真正看得见**
    /// 的位置。传 `x = 0` 即取该行行首。
    ///
    /// 坐标系说明：`ReaderCoreText.touchedCharacterIndex` 内部已把行框换算成 y 轴向下的
    /// 矩形，所以这里直接传视图坐标，不需要翻转。
    open func characterIndex(atViewPoint point: CGPoint) -> Int? {
        
        let index = ReaderCoreText.touchedCharacterIndex(point: point, frameRef: frameRef)
        
        guard index >= 0 else { return nil }
        
        return index
    }
    
    /// 绘制高亮。在已翻转的 CoreText 坐标系里调用。
    ///
    /// `ReaderCoreText.rangeRects` 返回的矩形基于 `CTFrameGetLineOrigins`，
    /// 是 CoreText 坐标（y 轴向上），所以必须在 `draw(_:)` 完成 translate + scale
    /// 之后使用，不能拿到 UIKit 坐标系里用。
    private func drawHighlight(in ctx: CGContext, style: ReaderSpeechHighlightStyle) {
        
        guard let sourceAttributedText,
              let range = clampedHighlightRange(limit: sourceAttributedText.length) else { return }
        
        let rects = ReaderCoreText.rangeRects(range: range, frameRef: frameRef, content: sourceAttributedText.string)
        
        guard !rects.isEmpty else { return }
        
        let colors = ReaderConfiguration.shared().currentThemeColors
        
        let path = CGMutablePath()
        
        switch style {
            
        case .background:
            
            colors.speechHighlightFill.setFill()
            
            path.addRects(rects)
            
        case .underline:
            
            colors.speechHighlightFill.setFill()
            
            // CoreText 坐标 y 轴向上，矩形的 minY 即行框底边，下划线画在这里
            path.addRects(rects.map {
                CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: highlightUnderlineHeight)
            })
            
        case .textColor:
            
            // 文字变色不需要叠加绘制，颜色已在 rebuildFrameRef() 里写进排版属性
            return
        }
        
        ctx.addPath(path)
        
        ctx.fillPath()
    }
    
    public override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        // 正常使用
        backgroundColor = UIColor.clear
    }
    
    /// 绘制
    ///
    /// ⚠️ **子类不要重写本方法**。要叠加自己的图形请重写 `drawUnderlay(in:)` /
    /// `drawOverlay(in:)` —— 重写 `draw(_:)` 会把朗读高亮一起丢掉，
    /// 而且这类丢失在编译期与代码审查里都看不出来（子类看起来只是「自己画自己的」）。
    open override func draw(_ rect: CGRect) {
        
        if (frameRef == nil) {return}
        
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.textMatrix = CGAffineTransform.identity
        
        ctx.translateBy(x: 0, y: bounds.size.height);
        
        ctx.scaleBy(x: 1.0, y: -1.0);
        
        let highlightStyle = ReaderEnvironment.speechHighlightStyle
        
        // 背景色块要垫在文字下面，所以先画
        if highlightStyle == .background { drawHighlight(in: ctx, style: highlightStyle) }
        
        // 子类的底层图形压在朗读高亮之上：长按选区是用户当下的直接操作，
        // 两者重叠时该让选区赢
        drawUnderlay(in: ctx)
        
        CTFrameDraw(frameRef!, ctx);
        
        // 下划线压在文字之上，避免被字形遮住
        if highlightStyle == .underline { drawHighlight(in: ctx, style: highlightStyle) }
        
        drawOverlay(in: ctx)
    }
    
    /// 正文之下的附加绘制。子类重写以叠加自己的底层图形（如长按选区色块）。
    ///
    /// 传入的 `ctx` 已完成 CoreText 坐标翻转（translate + scale），
    /// 所以可以直接用 `ReaderCoreText.rangeRects` 的返回值，不需要再换算。
    open func drawUnderlay(in ctx: CGContext) { }
    
    /// 正文之上的附加绘制。坐标系同 `drawUnderlay(in:)`。
    open func drawOverlay(in ctx: CGContext) { }
    
    public required init?(coder aDecoder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}
