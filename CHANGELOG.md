# Changelog

## 1.1.0

### 破坏性变更

- **移除 Objective-C 组件与 `ReaderKitOC` target。** 进度条原先使用第三方 OC 组件
  ASValueTrackingSlider，现已用 Swift 重写为 `ReaderProgressSlider`（继承 `UISlider`）。
  随之移除的公开符号：`ASValueTrackingSlider`、`ASValuePopUpView`、
  `ASValueTrackingSliderDelegate`、`ASValueTrackingSliderDataSource`，以及
  `ReaderKitOC` 模块与伞形头文件 `ReaderKit.h`。
  库现为纯 Swift 单 target。

  若此前直接引用过这些 OC 类型，请改用 `ReaderProgressSlider`：

  ```swift
  let slider = ReaderProgressSlider()
  slider.bubbleTextProvider = { value in "\(Int(value))" }  // 原 dataSource
  slider.onDragFinished = { value in /* 跳转 */ }            // 原 sliderWillHidePopUpView
  slider.bubbleColor = .darkGray
  slider.bubbleTextColor = .white
  slider.bubbleFont = .systemFont(ofSize: 22, weight: .bold)
  slider.bubbleArrowLength = 5
  ```

### 修复

- **滚动模式滚到内容末尾时页码停在倒数第二页。** 页码取「屏幕最顶端那一行像素所属的页」，
  而末页通常不足一屏，滚到底时它虽已完整呈现，顶端像素仍落在前一页，导致正文已显示到
  结尾、页码却停在 `14/15`。现增加到底判定，此时取可见的最后一页。
- 进度条气泡字体缺失时不再把 `nil` 赋给字体属性，改为回落系统粗体。

### 其他

- 补齐上游署名：本库衍生自 [DZMeBookRead](https://github.com/dengzemiao/DZMeBookRead)
  （MIT），许可全文见 `THIRD-PARTY-NOTICES.md`；`LICENSE` 中 All Rights Reserved 的
  范围明确收窄为本库自有的修改与新增部分。
- 代码风格统一：类型标注冒号后、逗号后补空格（约 640 处，纯空白改动）。
- `Package.swift` 与 `ReaderKit.podspec` 随单 target 化简化。

## 1.0.0

首个版本。自包含的 iOS 小说阅读器引擎：正文排版与分页、左右翻页与上下滚动两种阅读模式、
阅读菜单（字号 / 行距 / 主题 / 翻页模式）、章节目录、书签、长按选中与复制、六套主题换肤。

库内零业务代码与零资源：内容来源、章节解锁、书架收藏、埋点、页面跳转，以及图标、字体、
主题配色，全部经 `Contracts/` 下的注入点交由接入方提供。
