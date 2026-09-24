//
//  ReaderColorHex.swift
//  Reader Engine
//
//  引擎自有的十六进制颜色初始化。
//
//  为什么不复用接入方的 `UIColor(hex:)`：那属于接入方的 UIKit 扩展，库不能依赖外部符号。
//
//  为什么参数标签叫 `readerHex` 而不是同名的 `hex`：引擎当前仍与宿主编译在同一个
//  target 里，同名同签名的 `convenience init(hex:)` 会与宿主那份重复声明。用独立标签
//  可以在「引擎已抽成独立模块」和「引擎仍在主工程内」两种状态下都成立。
//
//  实现与宿主那份等价（同样的 Scanner 解析与位移取值），保证换用后颜色完全一致。
//

import UIKit

extension UIColor {

    /// 用十六进制字符串构造颜色。
    ///
    /// - Parameters:
    ///   - readerHex: 十六进制色值，可带 `#`，如 `"#6555F2"` 或 `"6555F2"`。
    ///     非字母数字字符会被剥除，故 `"0x6555F2"` 之类也能解析。
    ///   - alpha: 透明度，默认不透明。
    public convenience init(readerHex: String, alpha: CGFloat = 1.0) {
        let sanitized = readerHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue = UInt64()
        Scanner(string: sanitized).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: alpha
        )
    }
}
