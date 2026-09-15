# ReaderKit

小说阅读器引擎。排版分页、左右翻页与上下滚动两种阅读模式、阅读菜单、目录与书签、
六套主题换肤。**库内零业务代码**：内容来源、章节解锁、书架收藏、埋点、页面跳转
等全部经注入点交由接入方提供。

- 最低系统：iOS 15.1
- 源码：`Sources/ReaderKit`（Swift）+ `Sources/ReaderKitOC`（进度条 OC 组件）
- **零资源依赖**：库只有源码，不携带任何图片与字体；默认用系统 SF Symbols 与系统字体，
  接入方按需注入自己的设计资产

## 接入

### SPM

```swift
.package(url: "https://github.com/onexf/ReaderKit.git", from: "1.1.0")
// 本地开发也可用路径引用：.package(path: "../ReaderKit")
```

### CocoaPods

```ruby
pod 'ReaderKit', :path => 'Modules/ReaderKit'
```

两种方式指向同一份源码。CocoaPods 原生支持单 target 混编，故 podspec 不拆 OC；
SPM 不支持，所以 OC 独立成 `ReaderKitOC` target，由
`other/public/ReaderEngineOCShim.swift` 用 `#if canImport` 透明转出，引擎内引用无需改动。

## 最小接入

阅读器入口处配置环境与注入点：

```swift
// 1) 进程级环境：文案、图标、字体、宿主配置（各有库内默认值，按需覆盖）
ReaderEnvironment.strings = myStrings              // ReaderStrings
ReaderEnvironment.fonts = myFonts                  // ReaderFonts
ReaderEnvironment.images = myImages                // ReaderImages
ReaderEnvironment.hostConfiguration = myConfig     // ReaderHostConfiguration
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

只有 `chapterLoader` 是必需的（引擎要靠它取正文）；其余不注入即对应能力静默关闭，
接入方应同时隐藏相关入口。

## 注入点一览

`Sources/ReaderKit/Contracts/` 下每个文件顶部都写了设计取舍与使用约束。

| 注入点 | 作用 |
|---|---|
| `ReaderChapterLoading` | 取章节正文。接口、CDN、解密、缓存全归接入方 |
| `ReaderTerminalPageProviding` | 提供书末页控制器 |
| `ReaderBookmarkSyncing` | 书签远端同步（引擎自带本地书签模型） |
| `ReaderBookshelfPolicy` | 收藏状态查询/设置、阅读达标自动加书架 |
| `ReaderCatalogueSupplying` | 分页目录续加载 |
| `ReaderHostActionHandling` | 跳宿主页面（反馈、详情），导航栈清理 |
| `ReaderPlaceholderProviding` | 加载失败空态视图 |
| `ReaderChapterAccessDelegate` | 章节未解锁 / 目录未加载完的回调 |
| `ReaderStrings` / `ReaderFonts` / `ReaderImages` | 文案、字体、图标（均有库内默认） |
| `ReaderHostConfiguration` | 图片压缩 URL、书签数量上限等配置 |
| `ReaderNotifications` | 引擎监听的通知名，由接入方在相应时机发送 |

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
