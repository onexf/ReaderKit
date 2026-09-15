# Changelog

## 1.2.0

### 破坏性变更

- **`ReaderBookModel` 属性改名，去掉宿主端与业务术语。** 旧名里 `shortPlayCode`
  是某短剧宿主的字段名，`totalEpisodes`（总集数）是短剧概念，都不该出现在小说阅读器里；
  `book*` 前缀则与库内其他 `book` 语义混杂。映射如下：

  | 旧名 | 新名 |
  |---|---|
  | `bookID` | `storyID` |
  | `bookName` | `storyName` |
  | `bookCover` | `cover` |
  | `author` | `writer` |
  | `bookSourceType` | `storySourceType` |
  | `shortPlayCode` | `externalBookCode` |
  | `totalEpisodes` | `totalChapterCount` |

  `ReaderChapterModel`、`ReaderReadRecordModel`、`ReaderBookmarkModel`、
  `ReaderChapterListItemModel` 上的同名属性与工厂方法参数一并改名
  （如 `ReaderChapterModel.model(bookID:chapterID:)` → `model(storyID:chapterID:)`）。

- **`NSKeyedArchiver` 归档键随属性名一起改。** 上表每一项的归档键与属性同名，
  故旧归档无法被新版本读出，阅读进度、书签、章节缓存会被视为不存在并重新拉取。
  库内**不含**兼容旧键的读取逻辑，也不做迁移：本库尚未有已上线的接入方，
  为此保留双键读取属于纯负债。若你的工程已有线上用户，请勿直接升级到本版本。

- **`ReaderBookmarkDraft.bookId` → `storyId`**，`ReaderBookmarkSyncing` 的
  `syncBookmarks`、`removeBookmark`、`removeBookmarks`、`removeAllBookmarks`
  四个方法的 `bookId:` 参数标签同步改为 `storyId:`。
  注意这是**库侧契约名**，与接入方自己的服务端字段无关：若你的接口字段叫 `bookId`，
  请在实现里保留该字段名，只把取值改成 `draft.storyId`。

`@objc` 类名（`ReaderBookModel` 等 6 个）未改动，不受影响。

### 修复

- **书签徽标、章节锁、抽屉封条、目录箭头四处图标不显示。** 这些位置绕过资源注入点
  直接 `UIImage(named:)` 取图，而对应 asset 已随库剥离业务资源时移除，实际取到 `nil`。
  现改走注入点，`ReaderImages` 新增 `bookmarkBadge`、`chapterLocked`、
  `bookmarkLockSeal`、`disclosureArrow`，`ReaderFonts` 新增 `progressBubble`；
  未注入时回落 SF Symbols，不再空白。

- **清除库内 10 处硬编码文案与地区假设。** 进度面板的「上一章 / 下一章」、
  长按菜单的「复制」、无章节名占位、本地书籍序章标题此前是写死的中文字面量，
  多语言工程无法覆盖。现由 `ReaderStrings` 提供 `previousChapter`、`nextChapter`、
  `copy`、`unnamedChapter`、`localBookPreface` 五项。
  本地 txt 的章节标题正则原先写死中文「第N章」，现由
  `ReaderHostConfiguring.localChapterTitlePattern` 提供，默认值保持原正则。

## 1.1.2

仅文档修正，无代码改动。

- 注入点一览改为**按必要性分三档**（必须 / 强烈建议 / 按需），每项补「不注入会怎样」
  一列。此前只有一句「只有 chapterLoader 是必需的」，接入方仍会漏看——不注入不报错、
  只是能力静默关闭，必须把后果写明。
- 修正 1.1.0 删除 Objective-C 后残留的过时描述：源码说明仍写着
  `Sources/ReaderKitOC`、接入说明仍在讲 `ReaderEngineOCShim` 与 `#if canImport` 转出。
- 修正两处已改名的协议：`ReaderBookshelfPolicy` → `ReaderBookshelfManaging`、
  `ReaderHostConfiguration` → `ReaderHostConfiguring`（1.1.0 改名时文档未同步）。
- 补充说明 Swift 6 严格并发下可直接 `import ReaderKit`，无需 `@preconcurrency`。

## 1.1.1

### 修复

- **接入方不再需要 `@preconcurrency import ReaderKit`。** 库内 10 处可变全局存储
  （`ReaderEnvironment` 的 6 个注入点，以及 `ReaderBatterySize`、`READER_COLOR_MAIN`、
  `READER_COLOR_MENU_COLOR`、`READER_RECORD_CURRENT_CHAPTER_LOCATION`）此前未做并发
  标注，在 `SWIFT_VERSION = 6.0` + `SWIFT_STRICT_CONCURRENCY = complete` 的工程里
  会报 `reference to static property 'strings' is not concurrency-safe`。
  现统一标注 `nonisolated(unsafe)`，由库承担责任，运行时行为不变。

  使用契约：**在展示阅读器之前配置一次注入点，之后视为只读**，库内不对其做同步。

  未采用 `@MainActor`：本地 txt 解析（`ReaderFastTextFileParser.parser(url:completion:)`）
  运行在后台队列，其中会读取 `ReaderEnvironment.fonts`，主线程隔离与该既有路径冲突。

- `ReaderDefaultHostConfiguration` 补 `public init()`。此前它是 `public class` 但
  初始化器为隐式 `internal`，接入方无法实例化，导致「只覆盖其中一项、其余委托默认实现」
  这种用法无法实现。现与 `ReaderDefaultThemeProvider` 保持一致。

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
