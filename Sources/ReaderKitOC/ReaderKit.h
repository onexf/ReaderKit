//
//  ReaderKit.h
//  ReaderKit —— 伞形头文件
//
//  Swift 编译器为含 @objc 声明的模块生成的 `ReaderKit-Swift.h` 会去 import
//  `<ReaderKit/ReaderKit.h>`（与模块同名的伞形头）。CocoaPods 以 framework 形式
//  集成时若没有这个文件，框架头文件解析会直接失败：
//    ReaderKit-Swift.h: fatal error: 'ReaderKit/ReaderKit.h' file not found
//
//  故显式提供该伞形头，导出库内 Objective-C 组件的公开头文件。
//  SPM 下多一个头文件无副作用（ReaderKitOC 的 publicHeadersPath 为 "."）。
//

#import <UIKit/UIKit.h>

#import "ASValueTrackingSlider.h"
#import "ASValuePopUpView.h"
