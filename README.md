# ReaderKit

小说阅读器引擎。排版分页、左右翻页与上下滚动两种阅读模式、阅读菜单、目录与书签、
六套主题换肤。**库内零业务代码**：内容来源、章节解锁、书架收藏、埋点、页面跳转
等全部经注入点交由接入方提供。

- 最低系统：iOS 15.1
- 源码：`Sources/ReaderKit`，**纯 Swift 单 target**，无 Objective-C
- **零资源依赖**：库只有源码，不携带任何图片与字体；默认用系统 SF Symbols 与系统字体，
  接入方按需注入自己的设计资产

## 接入

### SPM

```swift
.package(url: "https://github.com/onexf/ReaderKit.git", from: "1.8.2")
// 本地开发也可用路径引用：.package(path: "../ReaderKit")
```

### CocoaPods

```ruby
pod 'ReaderKit', :path => 'Modules/ReaderKit'
```

两种方式指向同一份源码。

Swift 6 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`）下可直接
`import ReaderKit`，无需 `@preconcurrency`——库内可变全局已标注
`nonisolated(unsafe)`，契约是「展示阅读器前配置一次注入点，之后只读」。

## 最小接入

阅读器入口处配置环境与注入点：

```swift
// 1) 进程级环境：文案、图标、字体、宿主配置（各有库内默认值，按需覆盖）
ReaderEnvironment.strings = myStrings              // ReaderStrings
ReaderEnvironment.fonts = myFonts                  // ReaderFonts
ReaderEnvironment.images = myImages                // ReaderImages
ReaderEnvironment.hostConfiguration = myConfig     // ReaderHostConfiguring
ReaderEnvironment.presentErrorNotice = { container, message in /* 自己的 Toast */ }

// 2) 实例级注入点：挂在阅读器控制器上
reader.chapterLoader = myChapterLoader             // ReaderChapterLoading（必需）
reader.terminalPageProvider = myTerminalProvider   // 书末页
reader.bookmarkSync = myBookmarkSync               // 书签远端同步
reader.bookshelfPolicy = myBookshelfPolicy         // 书架收藏
reader.catalogueSupplier = myCatalogueSupplier     // 分页目录补齐
reader.hostActionHandler = myHostActions           // 反馈入口 / 详情页跳转 / 导航栈清理
reader.placeholderProvider = myPlaceholderProvider // 加载失败空态
```

## 注入点一览

`Sources/ReaderKit/Contracts/` 下每个文件顶部都写了设计取舍与使用约束。

**除必须项外，其余不注入都不会崩溃、也不会报错，而是对应能力静默关闭**，
所以要先看清「不注入会怎样」这一列，再决定是否隐藏相关入口。

### 必须

不注入则阅读器不可用。

| 注入点 | 挂载位置 | 不注入会怎样 |
|---|---|---|
| `readModel` | `reader.readModel` | 阅读对象为空，无法启动 |
| `ReaderChapterLoading` | `reader.chapterLoader` | **拿不到正文**。引擎只能读已缓存章节，网络书源等于白屏 |

### 强烈建议

不注入能跑，但外观与体验会明显不像成品。

| 注入点 | 挂载位置 | 不注入会怎样 |
|---|---|---|
| `ReaderImages` | `ReaderEnvironment.images` | 图标退化为系统 SF Symbols（细线条符号，不是空白） |
| `ReaderFonts` | `ReaderEnvironment.fonts` | 正文用系统衬线体、界面用系统字体 |
| `ReaderThemeProviding` | `ReaderEnvironment.themeProvider` | 六套主题用库内中性配色，非设计稿色值 |
| `ReaderStrings` | `ReaderEnvironment.strings` | 文案为英文默认值（非英文 App 视同必须） |
| `presentErrorNotice` | `ReaderEnvironment.presentErrorNotice` | 章节加载失败时静默无提示 |

### 按需

对应业务能力若产品上不需要，可以不注入。

| 注入点 | 挂载位置 | 不注入会怎样 |
|---|---|---|
| `ReaderTerminalPageProviding` | `reader.terminalPageProvider` | 无书末页 |
| `ReaderBookmarkSyncing` | `reader.bookmarkSync` | 书签只存本地，不与服务端同步 |
| `ReaderBookshelfManaging` | `reader.bookshelfPolicy` | 无收藏能力，应同时隐藏收藏入口 |
| `ReaderCatalogueSupplying` | `reader.catalogueSupplier` | 引擎按「目录已完整」处理，不再续拉分页目录 |
| `ReaderHostActionHandling` | `reader.hostActionHandler` | 反馈、详情页跳转等入口无响应，应同时隐藏 |
| `ReaderPlaceholderProviding` | `reader.placeholderProvider` | 加载失败不显示占位视图 |
| `ReaderChapterAccessDelegate` | `reader.chapterUnlockDelegate` | 章节未解锁 / 目录未加载完时无回调 |
| `ReaderHostConfiguring` | `ReaderEnvironment.hostConfiguration` | 图片 URL 原样返回（不拼 CDN 压缩参数），书签上限取默认 99 |
| `ReaderNotifications` | 由接入方 `NotificationCenter.post` | 目录分页更新、书签远端合并后列表不刷新 |
| `ReaderSpeechCoordinating` | `reader.speechCoordinator` | 朗读仍完整可用（库内自管音频会话与锁屏），只是锁屏没有封面图 |
| `advanceToNextPageHandler` | `reader.advanceToNextPageHandler` | 左右翻页模式下朗读不自动翻页；朗读本身照常推进，只是正文停在原页 |
| `presentPositionHandler` | `reader.presentPositionHandler` | 后台听完回到前台时正文不对齐到朗读位置 |

### 语音朗读（TTS）

朗读是**开箱可用**的：不实现上表最后三项也能正常朗读、高亮、跨章续读、后台播放与锁屏控制。

唯一的必做项在接入方工程侧 —— `Info.plist` 声明 `UIBackgroundModes` 含 `audio`，
否则切后台或锁屏后朗读会被系统挂起。

```swift
// 从当前展示页开始朗读
reader.speechController.startFromCurrentPage()

reader.speechController.pause()
reader.speechController.resume()
reader.speechController.stop()

// 界面判断三态：朗读位置是否落在当前展示页
let range = reader.speechController.speakingRange
```

`speechController` 首次访问时才创建（它会持有 `AVSpeechSynthesizer` 并注册音频中断监听），
不使用朗读功能的接入方不会为此付代价。需要「查询是否已启用而不触发创建」时用
`isSpeechEngaged` 或 `engagedSpeechController`。

高亮样式经 `ReaderEnvironment.speechHighlightStyle` 选择，色值取自当前主题的
`speechHighlightFill` / `speechHighlightText`，两者都有由 `accent` 派生的默认实现。

设计口径：**协议里不出现业务模型**。书签用中立的 `ReaderBookmarkDraft` /
`ReaderBookmarkReceipt`，反馈入口用 `ReaderPositionContext`。
职责划分是「引擎判定何时该做，接入方决定怎么做」——例如加书架的阈值判定在引擎，
接口调用在接入方。

## 资源：库不携带，全部由接入方注入

库内**没有任何图片与字体文件**，也没有 resource bundle。这是有意的：

- 图标与字体属各接入方的设计体系，夹带某个 App 的资产会让其它接入方拿到不属于自己的外观
- 字体文件各有授权条款，随库分发等于代为再分发
- 零资源也让库的集成更简单（无 bundle 定位、无运行时字体注册）

### 图标

`ReaderEnvironment.images` 有 20 个角色（返回、反馈、加书架、字号增减、行距增减、
阅读方向、进度滑块、目录/书签标签、日夜切换、电量、书封占位、书签空态）。
默认值全部取系统 SF Symbols，按 template 渲染以跟随阅读主题染色。

```swift
var images = ReaderImages()
images.back = { UIImage(named: "my_back")?.withRenderingMode(.alwaysTemplate) }
images.tabBookmark = { UIImage(named: "my_bookmark")?.withRenderingMode(.alwaysTemplate) }
ReaderEnvironment.images = images
```

不覆盖也能跑，只是外观是系统符号风格。返回 `nil` 表示不显示该图标。

### 字体

`ReaderEnvironment.fonts` 有 6 个角色（正文、正文标题、页眉、界面常规/强调/弱化）。
默认值是系统字体，其中正文三项用系统衬线字体（`.serif` design），长文阅读比无衬线合适。

```swift
var fonts = ReaderFonts()
fonts.bodyText = { UIFont(name: "MyBrandSerif", size: $0) ?? .systemFont(ofSize: $0) }
ReaderEnvironment.fonts = fonts
```

字体文件由接入方自己放进 App bundle 并在 `Info.plist` 的 `UIAppFonts` 声明。

## 已知遗留

- 归档 model 用 `@objc(Reader*Model)` 固定了 ObjC 类名，与模块名、Swift 类名解耦。
  **改动这些固定名会破坏已发布版本的归档数据**，届时必须在 `ReaderArchiver`
  里重新引入 `setClass(_:forClassName:)` 映射。
- 埋点处于整体下线状态（代码注释保留）。恢复时应经协议由接入方实现，
  引擎不直连任何埋点 SDK。

## 许可与来源

本库的阅读器内核衍生自 [DZMeBookRead](https://github.com/dengzemiao/DZMeBookRead)
（MIT，Copyright (c) 2018 dengzemiao），在其基础上做了重构、模块化、边界解耦与功能调整。

- 上游作品按其**原始许可证**授权，见 `THIRD-PARTY-NOTICES.md`
- 本库在此之上的修改与新增部分采用专有许可（保留所有权利），见 `LICENSE`

接入方分发 App 时，需在应用内（如「关于 / 开源许可」页面）一并展示
`THIRD-PARTY-NOTICES.md` 中的声明，以满足 MIT 的署名要求。
