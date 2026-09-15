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
//  为什么拆两个 target：SPM 不支持单 target 内混编 Swift 与 Objective-C，
//  而阅读菜单的进度条用了 OC 三方组件 ASValueTrackingSlider，故 OC 独立成
//  ReaderKitOC，由 Sources/ReaderKit/other/public/ReaderEngineOCShim.swift
//  用 `#if canImport` 条件转出，Swift 侧引用无需改动。
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
            name: "ReaderKitOC",
            path: "Sources/ReaderKitOC",
            publicHeadersPath: "."
        ),
        .target(
            name: "ReaderKit",
            dependencies: ["ReaderKitOC"],
            path: "Sources/ReaderKit",
            exclude: [
                "Contracts/README.md"
            ]
        )
    ]
)
