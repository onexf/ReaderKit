//
//  ReaderChapterModel+BookmarkPaging.swift
//  ReaderKit
//
//  书签精确定位:翻页模式临时分页 + 滚动模式内容偏移计算
//  设计来源:spec `bookmark-precise-positioning`
//
//  核心约束:
//  - 临时分页(applyBookmarkPaging)只改内存态 layoutPages/pageCount,绝不 save(),
//    切章 / 切排版 / 重进阅读后自动回归常规分页。
//  - 书签字符所在「段落」锚定为页首,保证缩进与排版正确(段首对齐)。
//

import UIKit
import ObjectiveC

private var kBookmarkPagingKey: UInt8 = 0

extension ReaderChapterModel {
    
    /// 是否处于书签临时分页状态(内存态,不参与归档)
    public var isBookmarkPaging: Bool {
        get { (objc_getAssociatedObject(self, &kBookmarkPagingKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &kBookmarkPagingKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// 把 location 往前对齐到最近的段落起点(最近的 "\n" 之后位置)
    /// 保证书签所在段完整、页首缩进正常;无法找到则回退原 location。
    public func coordinatedParagraphBegin(for location: Int) -> Int {
        guard let full = typesetContent, full.length > 0 else { return max(0, location) }
        let clamped = min(max(location, 0), full.length - 1)
        let string = full.string as NSString
        // 在 [0, clamped) 范围内找最后一个换行符,段首 = 换行符的下一个字符
        let searchRange = NSRange(location: 0, length: clamped)
        let nl = string.rangeOfCharacter(from: CharacterSet.newlines, options: .backwards, range: searchRange)
        if nl.location != NSNotFound {
            return min(nl.location + nl.length, full.length - 1)
        }
        // 没有更早的换行 → 属于首段,对齐到 0
        return 0
    }
    
    /// 翻页模式临时分页:以 location 为分界点重新分页,使书签所在段成为页首
    /// - 不调用 save(),不污染持久化数据
    public func adoptBookmarkPaging(at location: Int) {
        
        // 确保常规分页已构建(typesetContent 就绪)
        reviseFont()
        
        guard let full = typesetContent, full.length > 0 else { return }
        
        let splitAt = coordinatedParagraphBegin(for: location)
        
        // 分界点在章首:常规分页下书签段本就接近页首,无需特殊处理
        guard splitAt > 0, splitAt < full.length else { return }
        
        let rect = CGRect(origin: .zero, size: READER_VIEW_RECT.size)
        
        let headAttr = full.attributedSubstring(from: NSRange(location: 0, length: splitAt))
        let tailAttr = full.attributedSubstring(from: NSRange(location: splitAt, length: full.length - splitAt))
        
        let headPages = ReaderTypesetter.pageing(attrString: headAttr, rect: rect, isFirstChapter: false)
        let tailPages = ReaderTypesetter.pageing(attrString: tailAttr, rect: rect, isFirstChapter: false)
        
        // 修正 tail 段每页 range.location(子串分页得到的是相对偏移)
        for p in tailPages {
            p.range = NSRange(location: p.range.location + splitAt, length: p.range.length)
        }
        
        let merged = headPages + tailPages
        for (i, p) in merged.enumerated() { p.page = NSNumber(value: i) }
        
        // 写入内存态(关键:不 save)
        layoutPages = merged
        pageCount = NSNumber(value: merged.count)
        isBookmarkPaging = true
    }
    
    /// 丢弃临时分页,回到常规分页(强制重建,与当前排版一致)
    public func restoreBookmarkPaging() {
        guard isBookmarkPaging else { return }
        isBookmarkPaging = false
        // 清空分页签名,强制 updateFont 重建常规分页
        forceRebuildPaging()
    }
    
    /// 强制按当前排版重建常规分页(不依赖 updateFont 的签名短路)
    /// typesetContent 在临时分页时未被修改,直接整体重新分页即可恢复常规分页
    public func forceRebuildPaging() {
        guard let full = typesetContent, full.length > 0 else {
            reviseFont()
            return
        }
        let rect = CGRect(origin: .zero, size: READER_VIEW_RECT.size)
        layoutPages = ReaderTypesetter.pageing(attrString: full, rect: rect, isFirstChapter: false)
        pageCount = NSNumber(value: layoutPages.count)
    }
    
    /// 滚动模式:计算 location 对应的 contentOffset.y(相对本章顶部)
    /// 累加 location 所在页之前各页 (contentSize.height + headerInsetHeight),
    /// 再对所在页内 [页首, location) 子串做高度补偿。
    public func contentOffsetY(forLocation location: Int) -> CGFloat {
        guard let full = typesetContent, full.length > 0 else { return 0 }
        let target = min(max(location, 0), full.length - 1)
        
        var y: CGFloat = 0
        let maxW = READER_VIEW_RECT.width
        
        for p in layoutPages {
            guard let range = p.range else { continue }
            let start = range.location
            let end = range.location + range.length
            
            if end <= target {
                // 整页在书签之前
                y += p.contentSize.height + p.headerInsetHeight
            } else if start <= target {
                // 书签落在这一页内
                y += p.headerInsetHeight
                let headLen = target - start
                if headLen > 0 {
                    let sub = full.attributedSubstring(from: NSRange(location: start, length: headLen))
                    y += ReaderCoreText.attributedStringHeight(attrString: sub, maxW: maxW)
                }
                break
            } else {
                break
            }
        }
        return max(0, y)
    }

    /// 滚动模式:计算 location 在其所在页 cell 内的纵向偏移
    /// 用整页 CTFrame 的真实行排版求 location 所在行的行顶 Y(与渲染完全一致),
    /// = headerInsetHeight + 行顶相对内容区的 Y;供 pageScrollAnchor 复用滚动控制器定位恢复。
    /// CTFrame 不可用时回退到子串测高。
    public func inPageOffsetY(forLocation location: Int) -> CGFloat {
        let p = page(location: location).intValue
        guard p >= 0, p < layoutPages.count, let range = layoutPages[p].range else { return 0 }
        let layoutPage = layoutPages[p]
        let headH = layoutPage.headerInsetHeight ?? 0
        let localIdx = min(max(location - range.location, 0), range.length)
        
        if let lineTop = rowPeakY(inPage: p, localIndex: localIdx) {
            return max(0, headH + lineTop)
        }
        
        // 回退:子串测高
        guard let full = typesetContent, full.length > 0 else { return max(0, headH) }
        var y: CGFloat = headH
        if localIdx > 0 {
            let sub = full.attributedSubstring(from: NSRange(location: range.location, length: localIdx))
            y += ReaderCoreText.attributedStringHeight(attrString: sub, maxW: READER_VIEW_RECT.width)
        }
        return max(0, y)
    }

    /// 滚动模式:由 page + 页内纵向偏移反算最接近的字符 location(inPageOffsetY 的逆运算)
    /// 用整页 CTFrame 真实行排版,取"行顶最接近偏移"的那一行的行首字符作为锚点,
    /// 与 inPageOffsetY 共用同一套布局,round-trip 对齐到同一行(误差 ≤ 半行)。
    public func location(forPage pageIndex: Int, inPageOffsetY offsetY: CGFloat) -> Int {
        guard let full = typesetContent, full.length > 0,
              pageIndex >= 0, pageIndex < layoutPages.count,
              let range = layoutPages[pageIndex].range else { return 0 }
        let layoutPage = layoutPages[pageIndex]
        let headH = layoutPage.headerInsetHeight ?? 0
        let yInText = offsetY - headH
        if yInText <= 0 { return range.location }
        
        let contentH = layoutPage.contentSize.height
        if contentH > 0 {
            let ctFrame = ReaderCoreText.makeFrame(attrString: layoutPage.showContent,
                                                     rect: CGRect(origin: .zero, size: layoutPage.contentSize))
            let lines = CTFrameGetLines(ctFrame) as! [CTLine]
            if !lines.isEmpty {
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)
                
                var bestLocalStart = 0
                var bestDelta = CGFloat.greatestFiniteMagnitude
                for i in 0..<lines.count {
                    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                    CTLineGetTypographicBounds(lines[i], &ascent, &descent, &leading)
                    let lineTop = contentH - origins[i].y - ascent
                    let delta = abs(lineTop - yInText)
                    if delta < bestDelta {
                        bestDelta = delta
                        bestLocalStart = CTLineGetStringRange(lines[i]).location
                    }
                }
                return min(range.location + max(0, bestLocalStart), full.length - 1)
            }
        }
        
        // 回退:子串测高二分
        let maxW = READER_VIEW_RECT.width
        var lo = 0
        var hi = range.length
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let sub = full.attributedSubstring(from: NSRange(location: range.location, length: mid))
            let h = ReaderCoreText.attributedStringHeight(attrString: sub, maxW: maxW)
            if h <= yInText {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return min(range.location + lo, full.length - 1)
    }

    /// 取某页内第 localIndex 个字符所在行的行顶 Y(相对内容区顶部,UIKit 坐标)
    /// 用整页 CTFrame 的行起点计算,失败返回 nil。
    private func rowPeakY(inPage pageIndex: Int, localIndex: Int) -> CGFloat? {
        guard pageIndex >= 0, pageIndex < layoutPages.count else { return nil }
        let layoutPage = layoutPages[pageIndex]
        let contentH = layoutPage.contentSize.height
        guard contentH > 0 else { return nil }
        
        let ctFrame = ReaderCoreText.makeFrame(attrString: layoutPage.showContent,
                                                 rect: CGRect(origin: .zero, size: layoutPage.contentSize))
        let lines = CTFrameGetLines(ctFrame) as! [CTLine]
        guard !lines.isEmpty else { return nil }
        
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)
        
        for i in 0..<lines.count {
            let lineRange = CTLineGetStringRange(lines[i])
            let start = lineRange.location
            let end = lineRange.location + lineRange.length
            if localIndex >= start && localIndex < end || (i == lines.count - 1 && localIndex >= start) {
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                CTLineGetTypographicBounds(lines[i], &ascent, &descent, &leading)
                // CoreText 原点在左下,翻成 UIKit 行顶
                let lineTop = contentH - origins[i].y - ascent
                return max(0, lineTop)
            }
        }
        return nil
    }
}
