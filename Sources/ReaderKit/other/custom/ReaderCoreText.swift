//
//  ReaderCoreText.swift
//  ReaderKit
//
//  Created by Asuna on 2025/08/19.
//

import UIKit
import Darwin
import Foundation

open class ReaderCoreText: NSObject {
    
    /// 获得 CTFrame
    ///
    /// - Parameters:
    ///   - attrString: 内容
    ///   - rect: 显示范围
    /// - Returns: CTFrame
    public class func makeFrame(attrString: NSAttributedString, rect: CGRect) ->CTFrame {
        
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        
        let path = CGPath(rect: rect, transform: nil)
        
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        return ctFrame
    }
    
    /// 获得内容分页列表
    ///
    /// - Parameters:
    ///   - attrString: 内容
    ///   - rect: 显示范围
    /// - Returns: 内容分页列表
    public class func pageRanges(attrString: NSAttributedString, rect: CGRect) ->[NSRange] {
        
        var rangeArray: [NSRange] = []
        
        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        
        let path = CGPath(rect: rect, transform: nil)
        
        var range = CFRangeMake(0, 0)
        
        var rangeOffset: NSInteger = 0
        
        repeat{
            
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(rangeOffset, 0), path, nil)
            
            range = CTFrameGetVisibleStringRange(frame)
            
            rangeArray.append(NSMakeRange(rangeOffset, range.length))
            
            rangeOffset += range.length
            
        }while(range.location + range.length < attrString.length)
        
        return rangeArray
    }
    
    /// 获得触摸位置文字的Location
    ///
    /// - Parameters:
    ///   - point: 触摸位置
    ///   - ctFrame: 内容 CTFrame
    /// - Returns: 触摸位置的Index
    public class func touchedCharacterIndex(point: CGPoint, ctFrame: CTFrame?) ->CFIndex {
        
        var location: CFIndex = -1
        
        let line = touchedLine(point: point, ctFrame: ctFrame)
        
        if line != nil {
            
            location = CTLineGetStringIndexForPosition(line!, point)
        }
        
        return location
    }
    
    /// 获得触摸位置那一行文字的Range
    ///
    /// - Parameters:
    ///   - point: 触摸位置
    ///   - ctFrame: 内容 CTFrame
    /// - Returns: 一行的 NSRange
    public class func touchedLineRange(point: CGPoint, ctFrame: CTFrame?) ->NSRange {
        
        let line = touchedLine(point: point, ctFrame: ctFrame)
        
        return lineRange(line: line)
    }
    
    /// 获得触摸位置那一个段落的 NSRange || 一行文字的 NSRange
    ///
    /// - Parameters:
    ///   - point: 触摸位置
    ///   - ctFrame: 内容 CTFrame
    ///   - content: 内容字符串，传了则获取长按的段落 NSRange，没传则获取一行文字的 NSRange
    /// - Returns: 一个段落的 NSRange || 一行文字的 NSRange
    public class func touchedParagraphRange(point: CGPoint, ctFrame: CTFrame?, content: String? = nil) ->NSRange {
        
        let line = touchedLine(point: point, ctFrame: ctFrame)
        
        var range: NSRange =  lineRange(line: line)
        
        // 如果有正文，则获取整个段落的 NSRange
        
        if (line != nil && content != nil) {
            
            let lines: [CTLine] = CTFrameGetLines(ctFrame!) as! [CTLine]
            
            let count = lines.count
            
            let index = lines.index(of: line!)!
            
            var num = 0
            
            var rangeHeader = range
            
            var rangeFooter = range
            
            var isHeader = false
            
            var isFooter = false
            
            repeat {
                
                if (!isHeader) {
                    
                    let newIndex = index - num
                    
                    let line = lines[newIndex]
                    
                    rangeHeader =  lineRange(line: line)
                    
                    let headerString = content?.substring(rangeHeader)
                    
                    isHeader = headerString?.contains(READER_PH_SPACE) ?? true
                    
                    if (newIndex == 0) { isHeader = true }
                }
                
                if (!isFooter) {
                    
                    let newIndex = index + num
                    
                    let line = lines[newIndex]
                    
                    rangeFooter =  lineRange(line: line)
                    
                    let footerString = content?.substring(rangeFooter)
                    
                    isFooter = footerString?.contains("\n") ?? true
                    
                    if (newIndex == (count - 1)) { isFooter = true }
                }
                
                num += 1
                
            } while (!isHeader || !isFooter)
            
            range = NSMakeRange(rangeHeader.location, rangeFooter.location + rangeFooter.length - rangeHeader.location)
        }
        
        return range
    }
    
    /// 获得触摸位置在哪一行
    ///
    /// - Parameters:
    ///   - point: 触摸位置
    ///   - ctFrame: 内容 CTFrame
    /// - Returns: CTLine
    public class func touchedLine(point: CGPoint, ctFrame: CTFrame?) ->CTLine? {
        
        var line: CTLine? = nil
        
        if ctFrame == nil { return line }
        
        let ctFrame: CTFrame = ctFrame!
        
        let path: CGPath = CTFrameGetPath(ctFrame)
        
        let bounds: CGRect = path.boundingBox
        
        let lines: [CTLine] = CTFrameGetLines(ctFrame) as! [CTLine]
        
        if lines.isEmpty { return line }
        
        let lineCount = lines.count
        
        let origins = malloc(lineCount * MemoryLayout<CGPoint>.size).assumingMemoryBound(to: CGPoint.self)
        
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), origins)
        
        for i in 0..<lineCount {
            
            let origin: CGPoint = origins[i]
            
            let tempLine: CTLine = lines[i]
            
            var lineAscent: CGFloat = 0
            
            var lineDescent: CGFloat = 0
            
            var lineLeading: CGFloat = 0
            
            CTLineGetTypographicBounds(tempLine, &lineAscent, &lineDescent, &lineLeading)
            
            let lineWidth: CGFloat = bounds.width
            
            let lineheight: CGFloat = lineAscent + lineDescent + lineLeading
            
            var lineFrame = CGRect(x: origin.x, y: bounds.height - origin.y - lineAscent, width: lineWidth, height: lineheight)
            
            lineFrame = lineFrame.insetBy(dx: -READER_SPACE_5, dy: -READER_SPACE_5)
            
            if lineFrame.contains(point) {
                
                line = tempLine
                
                break
            }
        }
        
        free(origins)
        
        return line
    }
    
    /// 获取内容所有段落尾部 NSRange
    ///
    /// - Parameters:
    ///   - ctFrame: 内容 CTFrame
    ///   - content: 内容字符串，也就是生成 ctFrame 的正文内容
    /// - Returns: [NSRange] 传入内容的所有断尾 NSRange
    public class func paragraphEndRanges (ctFrame: CTFrame?, content: String?) -> [NSRange] {
        
        var ranges: [NSRange] = []
        
        if (ctFrame != nil && content != nil) {
            
            let lines: [CTLine] = CTFrameGetLines(ctFrame!) as! [CTLine]
            
            for line in lines {
                
                let lintRange = lineRange(line: line)
                
                let lineString = content?.substring(lintRange)
                
                let isEnd = lineString?.contains("\n") ?? false
                
                if (isEnd) { ranges.append(lintRange) }
            }
        }
        
        return ranges
    }
    
    /// 获取内容所有段落尾部 CGRect
    ///
    /// - Parameters:
    ///   - ctFrame: 内容 CTFrame
    ///   - content: 内容字符串，也就是生成 ctFrame 的正文内容
    /// - Returns: [CGRect] 传入内容的所有断尾 CGRect
    public class func paragraphEndRects (ctFrame: CTFrame?, content: String?) -> [CGRect] {
        
        var rects: [CGRect] = []
        
        let ranges = paragraphEndRanges(ctFrame: ctFrame, content: content)
        
        for range in ranges {
            
            let rect = rangeRects(range: range, ctFrame: ctFrame, content: content)
            
            rects += rect
        }
        
        return rects
    }
    
    /// 通过 range 返回字符串所覆盖的位置 [CGRect]
    ///
    /// - Parameter range: NSRange
    /// - Parameter ctFrame: 内容 CTFrame
    /// - Parameter content: 内容字符串(有值则可以去除选中每一行区域内的 开头空格 - 尾部换行符 - 所占用的区域,不传默认返回每一行实际占用区域)
    /// - Returns: 覆盖位置
    public class func rangeRects(range: NSRange, ctFrame: CTFrame?, content: String? = nil) -> [CGRect] {
        
        var rects: [CGRect] = []
        
        if ctFrame == nil { return rects }
        
        if range.length == 0 || range.location == NSNotFound { return rects }
        
        let ctFrame = ctFrame!
        
        let lines: [CTLine] = CTFrameGetLines(ctFrame) as! [CTLine]
        
        if lines.isEmpty { return rects }
        
        let lineCount: Int = lines.count
        
        let origins = malloc(lineCount * MemoryLayout<CGPoint>.size).assumingMemoryBound(to: CGPoint.self)
        
        CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), origins)
        
        for i in 0..<lineCount {
            
            let line: CTLine = lines[i]
            
            let lineCFRange = CTLineGetStringRange(line)
            
            let lineRange = NSMakeRange(lineCFRange.location == kCFNotFound ? NSNotFound : lineCFRange.location, lineCFRange.length)
            
            var contentRange: NSRange = NSMakeRange(NSNotFound, 0)
            
            if (lineRange.location + lineRange.length) > range.location && lineRange.location < (range.location + range.length) {
                
                contentRange.location = max(lineRange.location, range.location)
                
                let end = min(lineRange.location + lineRange.length, range.location + range.length)
                
                contentRange.length = end - contentRange.location
            }
            
            if contentRange.length > 0 {
                
                // 去掉 -> 开头空格 - 尾部换行符 - 所占用的区域
                
                if content != nil && !content!.isEmpty {
                    
                    let tempContent: String = content!.substring(contentRange)
                    
                    let spaceRanges: [NSTextCheckingResult] = tempContent.matches("\\s\\s")
                    
                    if !spaceRanges.isEmpty {
                        
                        let spaceRange = spaceRanges.first!.range
                        
                        contentRange = NSMakeRange(contentRange.location + spaceRange.length, contentRange.length - spaceRange.length)
                    }
                    
                    let enterRanges: [NSTextCheckingResult] = tempContent.matches("\\n")
                    
                    if !enterRanges.isEmpty {
                        
                        let enterRange = enterRanges.first!.range
                        
                        contentRange = NSMakeRange(contentRange.location, contentRange.length - enterRange.length)
                    }
                }
                
                // 正常使用(如果不需要排除段头空格跟段尾换行符可将上面代码删除)
                
                let xStart: CGFloat = CTLineGetOffsetForStringIndex(line, contentRange.location, nil)
                
                let xEnd: CGFloat = CTLineGetOffsetForStringIndex(line, contentRange.location + contentRange.length, nil)
                
                let origin: CGPoint = origins[i]
                
                var lineAscent: CGFloat = 0
                
                var lineDescent: CGFloat = 0
                
                var lineLeading: CGFloat = 0
                
                CTLineGetTypographicBounds(line, &lineAscent, &lineDescent, &lineLeading)
                
                let contentRect: CGRect = CGRect(x: origin.x + xStart, y: origin.y - lineDescent, width: fabs(xEnd - xStart), height: lineAscent + lineDescent + lineLeading)
                
                rects.append(contentRect)
            }
        }
        
        free(origins)
        
        return rects
    }
    
    /// 通过 range 获得合适的 MenuRect
    ///
    /// - Parameter rects: [CGRect]
    /// - Parameter ctFrame: 内容 CTFrame
    /// - Parameter viewFrame: 目标ViewFrame
    /// - Parameter content: 内容字符串
    /// - Returns: MenuRect
    public class func menuRect(range: NSRange, ctFrame: CTFrame?, viewFrame: CGRect, content: String? = nil) ->CGRect {
        
        let rects = rangeRects(range: range, ctFrame: ctFrame, content: content)
        
        return menuRect(rects: rects, viewFrame: viewFrame)
    }
    
    /// 通过 [CGRect] 获得合适的 MenuRect
    ///
    /// - Parameter rects: [CGRect]
    /// - Parameter viewFrame: 目标ViewFrame
    /// - Returns: MenuRect
    public class func menuRect(rects: [CGRect], viewFrame: CGRect) ->CGRect {
        
        var menuRect: CGRect = CGRect.zero
        
        if rects.isEmpty { return menuRect }
        
        if rects.count == 1 {
            
            menuRect = rects.first!
            
        }else{
            
            menuRect = rects.first!
            
            let count = rects.count
            
            for i in 1..<count  {
                
                let rect = rects[i]
                
                let minX = min(menuRect.origin.x, rect.origin.x)
                
                let maxX = max(menuRect.origin.x + menuRect.size.width, rect.origin.x + rect.size.width)
                
                let minY = min(menuRect.origin.y, rect.origin.y)
                
                let maxY = max(menuRect.origin.y + menuRect.size.height, rect.origin.y + rect.size.height)
                
                menuRect.origin.x = minX
                
                menuRect.origin.y = minY
                
                menuRect.size.width = maxX - minX
                
                menuRect.size.height = maxY - minY
            }
        }
        
        menuRect.origin.y = viewFrame.height - menuRect.origin.y - menuRect.size.height
        
        return menuRect
    }
    
    
    /// 获取指定内容高度
    ///
    /// - Parameters:
    ///   - attrString: 内容
    ///   - maxW: 最大宽度
    /// - Returns: 当前高度
    public class func attributedStringHeight(attrString: NSAttributedString, maxW: CGFloat) ->CGFloat {
        
        var height: CGFloat = 0
        
        if attrString.length > 0 {
            
            // 注意设置的高度必须大于文本高度
            let maxH: CGFloat = 1000
            
            let framesetter = CTFramesetterCreateWithAttributedString(attrString)
            
            let drawingRect = CGRect(x: 0, y: 0, width: maxW, height: maxH)
            
            let path = CGPath(rect: drawingRect, transform: nil)
            
            let ctFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            
            let lines = CTFrameGetLines(ctFrame) as! [CTLine]
            
            var origins: [CGPoint] = Array(repeating: CGPoint.zero, count: lines.count)
            
            CTFrameGetLineOrigins(ctFrame, CFRangeMake(0, 0), &origins)
            
            let lineY = origins.last!.y
            
            var lineAscent: CGFloat = 0
            
            var lineDescent: CGFloat = 0
            
            var lineLeading: CGFloat = 0
            
            CTLineGetTypographicBounds(lines.last!, &lineAscent, &lineDescent, &lineLeading)
            
            height = maxH - lineY + CGFloat(ceilf(Float(lineDescent)))
        }

        return height
    }
    
    /// 获取一行文字的 Range
    ///
    /// - Parameter line: CTLine
    /// - Returns: 一行文字的 Range
    public class func lineRange(line: CTLine?) ->NSRange {
        
        var range: NSRange = NSMakeRange(NSNotFound, 0)
        
        if line != nil {
            
            let lineRange = CTLineGetStringRange(line!)
            
            range = NSMakeRange(lineRange.location == kCFNotFound ? NSNotFound : lineRange.location, lineRange.length)
        }
        
        return range
    }
    
    /// 获取行高
    ///
    /// - Parameter line: CTLine
    /// - Returns: 行高
    public class func lineHeight(ctFrame: CTFrame?) ->CGFloat {
        
        if ctFrame == nil { return 0 }
        
        let ctFrame: CTFrame = ctFrame!
        
        let lines: [CTLine] = CTFrameGetLines(ctFrame) as! [CTLine]
        
        if lines.isEmpty { return 0 }
        
        return lineHeight(line: lines.first)
    }
    
    /// 获取行高
    ///
    /// - Parameter line: CTLine
    /// - Returns: 行高
    public class func lineHeight(line: CTLine?) ->CGFloat {
        
        if line == nil { return 0 }
        
        var lineAscent: CGFloat = 0
        
        var lineDescent: CGFloat = 0
        
        var lineLeading: CGFloat = 0
        
        CTLineGetTypographicBounds(line!, &lineAscent, &lineDescent, &lineLeading)
        
        return lineAscent + lineDescent + lineLeading
    }
}
