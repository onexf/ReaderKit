//
//  ReaderEngineOCShim.swift
//  Reader Engine
//
//  让引擎里的 Objective-C 组件在不同构建形态下都可见。
//
//  引擎内含一个 OC 三方组件 ASValueTrackingSlider（菜单里的阅读进度条），
//  两种形态下 Swift 看到它的方式不同：
//  - 编译进宿主 App target：靠 bridging header 隐式可见，无需 import
//  - SPM：不支持单 target 混编，OC 必须单独成 target（`ReaderKitOC`），
//    Swift 侧要显式 import 才能看到
//
//  用 `canImport` 条件导入同时满足两者：主工程里没有 `ReaderKitOC` 这个模块，
//  条件不成立、整段为空，行为不变；SPM 构建时条件成立，`@_exported` 把 OC 类型
//  转出到引擎模块，引擎内那两处对 ASValueTrackingSlider 的引用无需改动。
//
//  `@_exported` 是下划线开头的非正式 API，但这是当前把依赖 target 的符号
//  透明转出的通行做法（SwiftPM 混编场景常见）。替代方案是在用到的文件里逐个
//  加 `import ReaderKitOC`，那样主工程会因找不到模块而编译失败。
//

#if canImport(ReaderKitOC)
@_exported import ReaderKitOC
#endif
