// swift-tools-version:5.9
//
//  ReaderKit —— 小说阅读器引擎
//
//  小说阅读器内核：排版分页、翻页与滚动两种阅读模式、阅读菜单、
//  目录与书签、主题换肤。库内零业务代码：内容来源、解锁、收藏、埋点、跳转等
//  全部经注入点交由接入方提供（见 Sources/ReaderKit/Contracts/）。
//
//  同一份源码提供两种接入方式：
//  - SPM：本文件（新项目走这条）
//  - CocoaPods：ReaderKit.podspec（自研 Tuist DSL 不支持 SPM 依赖的工程走这条）
//
//  纯 Swift 单 target。原先因进度条使用 Objective-C 三方组件而拆出的 ReaderKitOC
//  target、`@_exported` 转出 shim 与伞形头文件均已随该组件的 Swift 重写一并移除。
//

import PackageDescription

let package = Package(
    name: "ReaderKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "ReaderKit", targets: ["ReaderKit"])
    ],
    targets: [
        .target(
            name: "ReaderKit",
            path: "Sources/ReaderKit",
            exclude: [
                "Contracts/README.md"
            ]
        )
    ]
)
