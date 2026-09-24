//
//  ReaderFontList.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/27.
//

import UIKit

/// Font Size List
public let READER_FONT_SIZE_10: CGFloat = 10
public let READER_FONT_SIZE_12: CGFloat = 12
public let READER_FONT_SIZE_14: CGFloat = 14
public let READER_FONT_SIZE_16: CGFloat = 16

public let READER_FONT_SIZE_SA_10: CGFloat = readerScaled(READER_FONT_SIZE_10)
public let READER_FONT_SIZE_SA_12: CGFloat = readerScaled(READER_FONT_SIZE_12)
public let READER_FONT_SIZE_SA_14: CGFloat = readerScaled(READER_FONT_SIZE_14)
public let READER_FONT_SIZE_SA_16: CGFloat = readerScaled(READER_FONT_SIZE_16)

/// Font List
public let READER_FONT_SA_10 = ReaderFonts.system(READER_FONT_SIZE_SA_10)
public let READER_FONT_SA_12 = ReaderFonts.system(READER_FONT_SIZE_SA_12)
public let READER_FONT_SA_14 = ReaderFonts.system(READER_FONT_SIZE_SA_14)
public let READER_FONT_SA_16 = ReaderFonts.system(READER_FONT_SIZE_SA_16)

// MARK: - 库内默认字体
//
// 注意：这两个是**库内默认字型**（系统字体），不走 `ReaderEnvironment.fonts` 注入。
// 用于内部 UI 度量与兜底；正文与标题字体请走注入点。
extension ReaderFonts {

    /// 系统字体
    public static func system(_ size: CGFloat) ->UIFont { return UIFont.systemFont(ofSize: size) }

    /// 系统粗体（尺寸经屏幕比例换算）
    public static func systemBold(_ size: CGFloat) ->UIFont { return UIFont.boldSystemFont(ofSize: readerScaled(size)) }
}
