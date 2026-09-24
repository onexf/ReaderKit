# Changelog

## 1.33.0
按设计稿修菜单底栏两处像素差，并随本版发布之前积压的**源码目录重组**。
无行为与接口变化，`import ReaderKit` 的一方无需改任何代码。

### 源码目录重组（62 个文件纯移动，无内容改动）
`Sources/ReaderKit/` 由原先按「类型」分的 `menuUI/ model/ controller/ view/ other/…`
改为按**关注点**分的 `Contracts/ Reader/ Content/ Typesetting/ Models/ Menu/ Drawer/
Speech/ Persistence/ Primitives/ Theme/ Support/`，只保留一层（`Menu/Panels/` 是唯一二层）。
目录职责表见 README「目录结构」。
Package.swift 走 `path: "Sources/ReaderKit"`、podspec 走 `**/*.swift`，两边都不需要跟着改。

### 呼出菜单顶部圆角 12 → 16
`READER_MENU_BOTTOM_VIEW_CORNER_RADIUS`。设计稿菜单帧给的是 16，之前取了 12。
⚠️ 设计稿自身不一致：反馈弹层那一帧标的是 12。以菜单帧为准 —— 这个常量只作用于呼出菜单。
### 底栏 tab 文字 10 → 9
`ReaderMenuTabRail`。设计稿是 Lexend Deca Light 9，之前取了 10，"Directory" 因此宽出约 4pt。
`titleHeight` **刻意保持 14**：9pt 行高约 11.7，收窄它会连带改 `itemHeight`(64) →
`READER_MENU_BOTTOM_TAB_BAR_HEIGHT`(84) → 菜单收起态与展开态两个高度，改动面远大于收益。
所以 tab 栏总高与图标位置一点没动。

## 1.32.2

修**朗读位置跳变后，锁屏 / 通知中心 / 控制中心的进度与正文里的朗读位置对不上**。

### 现象

朗读中在阅读器里往后翻几页，再点「从这里开始读」，正文从新位置读起，
而通知中心的进度条与已播时间仍停在翻页前的位置（截图里是 `0:17 / -3:45`，
实际已经读到章节中段）。往前翻页则相反，进度条偏大。

### 成因

已播时间与朗读位置是两套量纲，只在「从头连续读一章」时才天然一致：

| 量 | 口径 |
| --- | --- |
| `chapterProgress`（正文高亮的位置） | 当前句句首偏移 / 本章字符数 |
| `estimatedElapsed`（锁屏时间轴） | 实际出声的墙钟秒数累计 |

两者唯一的对齐点是「换章时把计时归零」，而那句归零写在 `prepare(chapter:)` 里 ——
**它对同一章直接短路返回**。于是同章内跳转（翻页后「从这里开始读」）计时一秒没断，
位置却跳了，偏差保持到本章读完。

跨章同样有一处：往前翻页跨到上一章会落在**章末**，计时刚归零、位置却在 90% 处，
偏差最大。

### 修法

归零与重锚从 `prepare(chapter:)` 挪到新的 `anchorSpeakingTime(toLocation:)`，
由 `beginSpeaking(fromLocation:)` 调用 —— 那里是「跳到某个位置开口读」的唯一咽喉，
覆盖翻页重播、跨章、目录跳章、锁屏上一章 / 下一章全部路径。
锚点按句首字符偏移折算，用的语速与 `makeContext()` 算总时长的**同一个**，
所以重锚当场 `elapsed / duration` 精确等于 `chapterProgress`。

### ⚠️ 这不是 1.7.1 的老路

1.7.1 的错是把已播时间**整体**换成句首折算值，于是整句朗读期间它一动不动，
系统看到「声称在播、时间却不走」就不再采信我们声明的 `rate`。
本版只在位置跳变的那一刻重设基准，之后照旧由墙钟往前推，连续性与单调性不受影响。
`resume()` 里「重新提交同一句」那条路径显式传 `anchorsTimeline: false` ——
它是原地继续、不是跳变，重锚会让进度条在点继续时先倒退一下。

**不要把重锚挪进逐句推进的路径**（`advanceToNextSentence` / `speechPlayerDidStart`），
那就正好复现 1.7.1。

## 1.32.1

**1.32.0 的朗读行为改动全部回退，只保留日志。** 那三处改动在真机上引发了三个回归：

| 现象 | 成因 |
| --- | --- |
| 暂停之后点继续没反应 | `resume()` 里「会话激活失败就 `return`」。`setActive(true)` 失败不等于放不出声，而拒绝续播是确定性失败 |
| 读着读着自动暂停 | 同上那条 guard 挡住了中断结束（`.shouldResume`）触发的自动续播 |
| 跨章读完标题就暂停 | 「播放器非预期停住」判据（`timeControlStatus == .paused && state == .playing`）在正常播放里也会短暂成立 —— 预合成用系统 TTS 渲染时会碰共享会话，而那一刻正好落在短句（章节标题）播完之后 |

根因是同一个判断错误：**「宁可不播也不谎称在播」在这条路径上是错的**。状态显示不对只是显示问题，
而拒绝播放 / 误判暂停会把核心功能掐掉。这条路径的状态机横跨 `AVPlayer`、`AVAudioSession`、
系统 TTS 与远程命令，四方的先后顺序靠读代码定不下来 —— 没有真机日志就不该动它的行为。

### 1.32.1 保留了什么

行为上**等价于 1.31.0**，另加两处不碰播放的改动：

- 回前台（`didBecomeActive`）补写一次锁屏信息、并按权威状态刷一次界面。只读状态，不改播放
- dock 中央图标的 `isSpeaking` 口径改成 `activity == .playing || .preparing`
  （原先 `.idle` 也算「在播」），`ReaderSpeechDock` 与其中央控件的默认值 `true` → `false`

以及一批日志 —— 这是下一轮定位的唯一依据：

```
[Speech] 音频会话激活失败 code=…                       ← 此前这个 catch 完全静默
[Speech] 音频中断开始（来电 / 其它 App 抢占 / 系统 TTS）
[Speech] 音频中断结束 shouldResume=true/false
[Speech] 中断结束请求继续，上次暂停来源=user/system
[Speech] 输出设备不可用（拔耳机 / 蓝牙断开），暂停
[Speech] 播放器读到停住（位置 3/5s），1.5s 后复核
[Speech] 播放器非预期停住（仅记录，不改状态）activity=…   ← 纯观察，不再收敛
[Speech] pause(origin=user|system) 进入 activity=… player=…
[Speech] resume() 进入 activity=… player=… sessionActive=…
```

「非预期停住」现在只打日志、不改任何状态，所以 1.32.0 想修的那个问题**仍然存在**：
系统侧停掉播放器时 `activity` 会停在 `.playing`（声音没了、界面还显示在播）。
这是刻意的取舍，等日志证实那条判据只在真被停掉时成立，再让它动手。

### ⚠️ 1.32.0 请勿使用

它的图标注入点与几何修正（见下方 1.32.0「二」）都保留在本版里，直接升 1.32.1 即可。

## 1.32.0

这一版装了两件互不相干的事：**锁屏播放状态修复**，和**朗读控件的图标注入点 + 几何修正**。
后者新增 8 个 `ReaderImages` 槽位，并改了四处布局几何 —— 接入方即使一张图都不注入，
外观也会变（都是往设计稿方向靠），见「二」。

---

## 一、锁屏播放状态

修「锁屏点暂停之后，控制中心显示暂停、App 内显示播放中，而且没有声音」。

### 现象与成因

QA 步骤：播放中锁屏 → 在锁屏页点暂停 → 回到 App 进朗读播放器页。
此时控制中心与锁屏显示**暂停**、声音也确实没了，而 App 内显示**播放中**；
点一下那颗按钮两边又同步了。

权威状态只有 `ReaderSpeechController.activity` 一个，两侧都从它派生，所以持久的
不一致只能来自「`activity` 与真实播放器脱节」。三处成因叠加：

1. **`resume()` 乐观置 `.playing`**。`AVAudioSession.setActive(true)` 在后台经常被系统拒
   （`CannotInterruptOthers`），而那个错误被 `catch` 吞掉且**一行日志都不打**；
   随后播放器照样 `play()` 到一个没激活的会话上 —— 没有声音，状态却已是 `.playing`。
   最容易触发它的是中断结束带 `.shouldResume` 那条路：用户在锁屏暂停之后，
   来一次通知音或闹钟就会走到。
2. **`timeControlStatus` 的观察只认 `.playing`**，任何**系统侧发起**的停止（会话被别的
   App 抢走、中断通知在进程挂起期间没送达）都无人接管，`activity` 永久停在播放中。
3. **回前台不对账**。`didBecomeActive` 只把正文对齐到朗读句，而那条链路被四个 guard
   门着、锁屏信息更是一次都不会重写。于是一次瞬时错位会永久留在界面上，
   只有用户主动点一下才恢复 —— 这正是 QA 看到的样子。

### 改了什么

- `resume()`：激活失败就**保持暂停态**并打日志，不再往下走
- `ReaderSpeechAudioSession.activate()`：`catch` 里补日志，带 `NSError.code`
- 播放器新增 `speechPlayerDidStallUnexpectedly`：`timeControlStatus` 变成 `.paused`
  而我们没要求过，就按暂停收敛。自然播完用「位置是否已到时长末尾」排除，
  不依赖结束通知与状态观察谁先到
- `didBecomeActive`：无条件 `reconcileWithPlayer()` + 重写锁屏 + 刷新界面，
  放在原有对齐链路**之前**
- 新增暂停来源记账：`.shouldResume` 只恢复**系统发起**的那次暂停。
  此前用户在锁屏按的暂停会被一次通知音顶掉、自己读下去
- `ReaderViewController.reviseSpeechDock`：`isSpeaking` 口径由 `activity != .paused`
  改成 `activity == .playing || activity == .preparing`（原先 `.idle` 也算在播），
  `ReaderSpeechDock` 与其中央控件的 `isSpeaking` 默认值由 `true` 改成 `false`

### 行为变更（一处）

音频会话激活失败时，点「继续」现在**没有反应**（以前是「显示在播但没声音」）。
两者都不理想，但前者有日志、状态也是真的；后者会让人以为功能坏了却查不到原因。

### 给接入方的提醒

这一版新增的日志（`音频会话激活失败 code=…`、`播放器非预期停住`、`回前台对账`）
是排这类问题的唯一现场。`ReaderEnvironment.log` 如果只接了 `print`，
测试包在用户手里时拿不到 —— 建议同时落盘。

---

## 二、朗读控件：图标可注入 + 几何对齐设计稿

起因是接入方反馈 dock 里那颗播放/暂停看着偏小。查下去发现两件事：一是这些图标全是库内
自绘、接入方连替换的口子都没有；二是自绘的几何有四处和设计稿不符，其中两处**代码和自己
的注释就是打架的**。

### 新增 API：8 个 `ReaderImages` 槽位

```swift
speechDockPause / speechDockResume          // dock 中央 36pt 控件的图标（环内侧）
speechDockClose                             // dock 最右的关闭 ✕（20pt）
speechScreenPause / speechScreenResume      // 全屏播放页中央 64pt 控件的图标
speechScreenPreviousChapter / …NextChapter  // 全屏播放页的上/下一章（28pt）
speechScreenDismiss                         // 全屏播放页顶部收起箭头（24pt 图标框）
```

**默认全是 `nil`，此时库按设计稿几何自绘**，和 `battery` 同一条路径 —— 所以不注入的接入方
不会退化成 SF Symbol。

⚠️ 注入的图**按自身尺寸居中绘制，不缩放**（`contentMode = .center`）。切图的画板尺寸就是
最终渲染尺寸，位置也由画板内的留白决定。用 `scaleAspectFit` 的话，一张 16pt 的图落进 36pt
的控件会被拉到 36pt，设计稿的留白全丢。

**两个进度环刻意没开放注入**：它们要跟着播放进度动，画不成静态图。

### 行为变更（四处，不注入切图也会变）

| 位置 | 改前 | 改后 |
| --- | --- | --- |
| 全屏页书封纵向 | 在「章节名底边 → 正文版位顶边−64」区间内**垂直居中** | **底边固定**在正文版位上方 64，松量全给上方 |
| dock 中央环 | 外径 = 控件边长（36） | 外径 30，即 36 的画板里四周各留 3 |
| 全屏页 64pt 图标 | 三角 22×23.6、右偏 1.76；竖条 3.4×23.6、间距 6 | 三角 22.19×28.1、右偏 3.1；竖条 4×24、间距 12 |
| 全屏页收起箭头 | 44 热区左边缘贴页边距 → 图形中心 x=42 | 24pt 图标框左边缘贴页边距 → 图形中心 x=32 |

前两处是**代码与注释不一致**，注释才是对的：

- `coverTextInset` 的注释一直写着「书封底边到正文窗口顶边」，代码却拿它当区间下沿再居中，
  于是松量被两边平分、书封随屏幕高度往上飘。375×812 上偏 40pt，390×844 上偏 55pt ——
  **屏幕越大偏越多，所以在小屏上很难发现**。
- `ReaderSpeechDockToggle` 的注释写着「环外径 30（36 里留 3 边距），路径半径 13.5」，
  而代码 `radius = (边长 − 环宽) / 2` 算出来是 16.5，把那 3pt 边距吞了。

后两处是照设计稿重新量的：64pt 的播放三角原先按「宽度的 8%」估光学右偏，现在直接用设计稿
给的绝对位置；收起箭头则是**对齐页边距的应该是图标框而不是热区**，热区不可见，所以这种错
不会被"看出来"，只表现为箭头和书名左边缘对不齐。

### 记录修订

本节描述的代码实际**随 1.32.0 一同发出**，当时漏记，且 1.32.0 原文写的「无 API 变更」是错的。
这里补回，未改动任何已发布的代码。

## 1.31.0

内部重构，**无 API 变更、无行为变更**，接入方只需升版本号。

符号面（改名）在 1.30.0 已无可改项，这一版换另一种手段：**减少重复代码本身**。
`ReaderScrollController` 的 `preloadingPrior` 与 `preloadingFollowing` 去空白后逐行
相似度 78.7%，其中相当一部分是两边逐字相同的样板。

### 抽出四段共用逻辑

| 新增私有成员 | 取代的重复 |
| --- | --- |
| `beginPreload(_:towards:isAtBoundary:)` | 前置判定 + 记入在途列表。边界谓词由调用方传（`isFirstChapter` / `isLastChapter`） |
| `endPreload(_:)` | `firstIndex(of:)` + `remove(at:)` 这对动作，原先散在 8 处 |
| `abortPreloadIfLocked(_:)` | 目录查锁那段 |
| `reviseNeighborLinks(of:chapterID:catalogueEntries:)` | 用目录相邻项回填 `priorChapterID` / `followingChapterID`，原先 3 处逐字相同 |

`beginPreload` 返回非可选的 `chapterID`，因此方法体里几十处 `chapterID!` 和
`guard let chapterID = chapterID` 一并消失。这不是放宽约束：`READER_NO_MORE_CHAPTER`
本身就是 nil，到边界时边界谓词先短路，原来的强解包本来就不可能走到 nil。

### 刻意没抽的部分

`preloadingPrior` 里的 `contentOffset` 补偿、以及两个方向各自的插入索引算法
（`max(0, currentIndex - 1)` vs `currentIndex + 1` 加越界 guard）**原样保留、平铺在各自方法里**。

往当前章**上方**插 section 会把已有内容往下顶，所以 Prior 必须记录相对偏移、
`reloadData` 后再恢复；Following 往下方插，不影响当前可见内容，不需要补偿。
这是两个方向本质不同的地方，参数化成一个「带方向参数的插入函数」只会把这个差异藏进
`if direction == .prior` 里，读起来更糟，也更容易在后续改动中被一起改坏。

### 一个顺手记下的坑

`reviseNeighborLinks` 里的两处回填**不要改写成三目运算**：

```swift
model.priorChapterID = chapterIndex > 0 ? catalogueEntries[chapterIndex - 1].id : READER_NO_MORE_CHAPTER
```

两个分支都是隐式解包可选（`NSNumber!`），类型检查会优先取解包后的 `NSNumber`，
而 `READER_NO_MORE_CHAPTER` 本身就是 nil —— 编译通过，运行到边界章时当场崩。
所以那里保留 `if` / `else` 两条赋值。

## 1.30.0

把 1.29.1 那个 bug 的**成因**从注释约束变成编译期约束。

### 破坏性变更：`loadChapter` 的返回值从 `Bool` 换成枚举

```swift
public enum ReaderChapterLoadDispatch: Sendable {
    case dispatched   // 已发起，回调一定来
    case joined       // 同一章已在途，回调挂在那次上，一定来
    case throttled    // 被节流，两个回调都不来，调用方自己收尾
}
```

`ReaderChapterLoading.loadChapter(...)` 与便捷重载的返回类型都改了。
实现方会编译报错，按下表改：

| 原来 `return` | 现在 |
| --- | --- |
| 被节流 → `false` | `.throttled` |
| **同一章已在途（去重）→ `false`** | **`.joined`**（并把回调挂到在途那次上） |
| 正常发起 → `true` | `.dispatched` |

引擎侧只看 `dispatch.willCallBack`。

### 为什么要改

1.29.x 的 `Bool` 语义是「请求是否已真正派发」，文档写明 `false` 只表示被节流。
但实现方很自然地也拿 `false` 表示「去重了」—— 而这两件事对调用方的要求**完全相反**：

- 被节流 → 回调不会来，必须自己收尾
- 去重 → 在途那次会完成，回调应该送达

混用的后果：引擎把「去重」当成「回调不会来」提前收尾。朗读那条路径的收尾是 `stop()`，
于是**连续切章时朗读莫名暂停**，日志里是「摘除远程命令 target」+
「activity playing → idle」，紧接着才看到正文到达 —— 内容是到了的，只是没人接。

只在操作够快、撞上在途请求时才出现，而在途请求的多少又取决于预取命中率，
所以它表现得像「偶发」，很难复现。`Bool` 给不了任何编译期提示，注释也没人逐字读。

### ⚠️ 去重时该怎么写

不是「返回 `.joined` 就完事」——**回调必须真的送达**。参考实现：

```swift
if loadingChapterIDs.contains(chapterId) {
    waiters[chapterId, default: []].append { result in … }   // 挂到在途那次上
    return .joined
}
```

另外：**在途标记要在回调之前摘掉**。摘在回调之后（比如用 `defer`）的话，
回调里若又请求同一章会被误判成「撞上在途」，挂进等待队列后再也没人唤醒它。

## 1.29.1

修 1.27.0 引入的回归：**朗读换章快一点就卡住**。1.27.0/1.28.0/1.29.0 必须升。

### 现象

用播放器或通知中心连续切章，切得慢没事，切快了就停住不出声。
正文页也可能是空的。日志里看得到 `activity playing → idle` 之后才开始下载正文。

### 根因

`ReaderChapterModel.isExist(storyID:chapterID:)` 只查**文件存不存在**，
而它是全工程「这一章缓存好了吗」的唯一判据 —— 接入方的邻章预取、滚动模式的邻章加载、
朗读换章都在用它。网络书的章节归档只在下载成功后写，所以
**「文件存在 ⇒ 有正文」本来是成立的**。

1.27.0 把全部归档键名改了，于是 1.27.0 之前写下的归档解不出内容。
同版本加的「解档失败回落新实例」兜底住了崩溃，**但把解不动的文件留在了磁盘上** ——
`isExist` 从此恒为真，那一章永远不会被重新下载：

- 预取跳过它 → 朗读换章每次都得现走网络
- 朗读推进（单句 0.2 秒、命中缓存几乎瞬时）远快于网络加载 → 切快了就追上，停在 idle
- 正文页拿到的是空壳模型 → 页面空白

慢切之所以没事，是因为网络来得及。

### 修法

`ReaderBookModel` / `ReaderChapterModel` / `ReaderReadRecordModel` 三个 `model(...)`
工厂里，解档失败时**先删掉那个文件**再回落新实例。`isExist` 恢复诚实，
预取与按需加载都跟着恢复。

这个修法对「归档文件损坏」同样有效，不只针对键名变更。

### ⚠️ 留给接入方的一条

`isExist` 的语义是「有归档文件」，**不是「有可朗读的正文」**。库内朗读路径另外用
`content` 非空做了二次判断（见 `ReaderSpeechController`）。接入方拿 `isExist`
当「已缓存」用是对的（有了本版的删除兜底），但**别拿它当「内容完整」**。

## 1.29.0

对着 2026-09-23 更新后的对比报告收尾。1.28.0 之后总分 13.21 → 11.86，
`class_surface` 从 48 组「类改名但成员未改」降到 8 组，其中还剩 3 组是本库的。

### 为什么这一版改了前几轮刻意保留的名字

前几轮把 `pageModel` / `chapterID` / `chapterModel` 留着，理由是「域内自然命名，
改了更难读」。当时它们各是某个配对里 5 个共有成员之一，改一个只从 5/5 降到 4/5。

新报告里这三组**每组只剩 1 个共有成员**：

| 配对 | 剩余共有成员 | 相似度 |
| --- | --- | --- |
| `ReaderPageCell` → `NLDZMReadViewCell` | `pageModel` | 80.7% |
| `ReaderBookmarkModel` → `NLDZMReadMarkModel` | `chapterID` | 71.0% |
| `ReaderReadRecordModel` → `NLDZMReadRecordModel` | `chapterModel` | 63.6% |

改 1 个名就能让整组配对消失，性价比完全不同了，所以这一版改。

### 破坏性变更

- `pageModel` → `layoutPage`（全库，98 处。和 `ReaderChapterModel.layoutPages` 成单复数对应）
- `ReaderBookmarkModel.chapterID` → `chapterKey`（**只有这个类**，和它的归档键 `"chapterKey"` 对齐。
  其它类的 `chapterID` 不动 —— 那是域内自然命名，且不构成配对）
- `ReaderReadRecordModel.chapterModel` → `activeChapter`（**只有这个类**，和归档键 `"activeChapter"` 对齐；
  `modify(chapterModel:page:isSave:)` 的实参标签一并改成 `activeChapter:`）
- `ReaderBookModel.fullText` → `rawText`、`externalBookCode` → `sourceBookCode`、
  `coverURL` → `coverImageURL`（归档键同步改成 `"coverImageURL"`）
- `ReaderMenu.singleTap` → `menuTapRecognizer`
- `ReaderSpeechDock.isPlaying` / `ReaderSpeechScreenController.isPlaying` → `isSpeaking`
- `ReaderBookmarkDeleteSheet`：`onRemove` → `onRemoveConfirmed`、`onCancel` → `onDismissed`、
  `onConfirm` → `onAlertConfirmed`、`removeButton/Label` → `removeControl/Caption`、
  `cancelTitle` → `cancelCaption`、`handleBar` → `grabber`
- `ReaderProgressSlider.arrowLength` → `caretLength`、
  `ReaderSpeechAudioRenderer.renderQueue` → `synthesisQueue`、
  `ReaderMenuTopBar/TabRail` 的 `selectedImage` → `activeIcon`、
  `ReaderCatalogueCell.itemSpacing` → `glyphGap`

`coverImageURL` 的归档键跟着改了，所以**装过 1.27.0/1.28.0 的设备升上来，封面地址会丢一次**
（下次进书重新写入，无感）。其余归档键未动。

### 回收三个 1.26/1.27 自己起的名字

`cancelTitle`（1.26.0 起）、`coverURL`（1.27.0 起，属性+归档键）、`pageIndex`（1.27.0 归档键）
在新报告里成了命中 —— 对比方也有这几个名字。

**这说明什么**：追着「一般」强度的通用词改名是个跑步机，改完可能撞上别的。
所以本版之后**不再改通用命名**（`isAnimating` / `closeButton` / `titleLabel` /
`titleHeight` / `contentHeight` 这类）。判据是：**这个名字换个业务场景还成立吗？**
成立就是通用词，撞上不构成证据，别改。

### 报告里剩下的（本库已无可改项）

`runtime_names` 的铁证只剩 `preferredStatusBarStyle` / `isModalInPresentation`，
系统属性 override，改不了。`dsym_classes` 13.9% 与 `dsym_methods` 11.5% 全是
Alamofire / SnapKit 的符号。`image_perceptual` 66.7% 报告自己标了
「样本量过小，接近随机基线，不可信」，命中全是 SwiftMessages 自带的图标。

## 1.28.0

去同质化的收尾：把对比报告里**还落在本库自己代码上**的名字清完。
1.26.0 改 Swift 标识符、1.27.0 改磁盘键名与字符串常量，这一版处理剩下的
存储属性与 `@objc` 选择器。

### 先纠正 1.26.0 的一个语义错误（这条最要紧）

`ReaderBookmarkDeleteSheet` 有两个清空回调，1.26.0 改名时**改反了**：

| 参数 | 真实语义 | 1.26.0 错叫 | 现在 |
| --- | --- | --- | --- |
| 点 Clear All 按钮即回调（埋点，早于二次确认） | 点击 | `onClearAllConfirmed` ❌ | `onClearAllTapped` |
| 二次确认后真正执行清除 | 确认 | `onClearAll` | `onClearAllConfirmed` |

也就是说 1.26.0 之后，名字叫「已确认」的那个其实在「刚点下去」就触发。
接在它上面做删除动作会**跳过二次确认**。本库内的调用点没有踩到（走的是另一个），
但接入方如果按名字接线就会中招。**1.26.0 / 1.27.0 的接入方请检查这两个回调。**

### 存储属性改名

Swift 存储属性名进 `__swift5_reflstr`，`private` 也躲不掉。这一批是阅读器专有语义的：

| 旧 | 新 | | 旧 | 新 |
| --- | --- | --- | --- | --- |
| `chapterListModels` | `catalogueEntries` | | `isMenuShow` | `isMenuVisible` |
| `markModels` | `bookmarkEntries` | | `isAnimateComplete` | `transitionSettled` |
| `recordModel` | `readingRecord` | | `isTapAnimating` | `tapTurnInFlight` |
| `markView` | `bookmarkList` | | `isTouchCursor` | `isCursorGrabbed` |
| `scrollController` | `flowController` | | `selectRange` | `selectedSpan` |
| `scrollPoint` | `lastContentOffset` | | `isScrollUp` | `isDraggingUpward` |
| `settingPanelView` | `contentContainer` | | `openLongPress` | `longPressSelectionEnabled` |
| `nightModeButton` | `themeToggleButton` | | `onBackTapped` | `onLeaveTapped` |
| `settingButton` | `settingsTab` | | `emptyLabel` | `placeholderLabel` |
| `fontSizeLabel` | `sizeReadout` | | `decreaseButton` | `fontSizeDownButton` |
| | | | `increaseButton` | `fontSizeUpButton` |

`addToBookshelf` 一名两用，拆开了：注入点里的图标提供者
`ReaderEnvironment.images.addToBookshelf` → `shelfAddIcon`，
`ReaderMenuTopBar` 里那个按钮 → `shelfButton`。

### `@objc` 选择器改名

只有 `@objc` 成员会进 ObjC 选择器表，普通 Swift 方法不会。这几个是手势 target：

`ReaderSpeechDock.clickCover` → `dismissByArtworkTap`、
`ReaderSpeechDockToggle.handleTap` → `toggleTapped`、
`ReaderSpeechDockCloseButton.handleTap` → `closeTapped`、
`ReaderSpeechScreenController.handleDismissPan` → `screenDismissDragged`、
`ReaderSpeechScreenChevron/SkipButton/ToggleButton.handleTap` →
`chevronTapped` / `skipTapped` / `playToggleTapped`。

五个类共用一个 `handleTap` 本来就不好读 —— 顺手按各自职责分开了。

### 为什么没把手势换成闭包

`UIGestureRecognizer` 没有闭包 API（`UIAction` 只有 `UIControl` 有）。要去掉 `@objc`
得引入一个持闭包的 `NSObject` 代理，而**那个代理里仍然有一个 `@objc func invoke`** ——
净效果是 N 个 `@objc` 收成 1 个，代价是多一个必须被正确持有的对象，漏持有则手势静默失效。
报告给这几个选择器的是「一般」强度，不值得拿泄漏风险换。结论同 1.25.0。

### 通知 observer 可以换 Combine（本版未做，接入方可参考）

1.25.0 说「通知那 7 个能去但有退化风险」，理由是
`addObserver(forName:queue:using:)` 的 block 版本要自己存 token 并在 `deinit` 里移除。
**这条对 Combine 不成立**：`NotificationCenter.publisher(for:)` + `AnyCancellable`，
持有者析构即自动取消，不需要注销代码。唯一代价是 `sink` 闭包必须写 `[weak self]`
（否则 `self → cancellables → 闭包 → self` 成环，泄漏且不报错）。

本库内这 8 个（`handleInterruption` / `handleRouteAlter` / `handleMediaServicesReset` /
`handleDidBecomeActive` / `handleCatalogueRefresh` ×3 / `handleBookmarkMerge`）
**已不在对比报告的命中里**，换过去属于额外改动，本版没做。哪天动它们照上面的写法。

## 1.27.0

接着 1.26.0 做完去同质化的另一半：**磁盘上的键名与二进制里的字符串常量**。

1.26.0 只改了 Swift 标识符，`__cstring` 里还留着一批和对比方逐字相同的串 ——
归档键名、阅读偏好的 `UserDefaults` 键、章节标题正则、分页签名格式。
当时没动是怕老用户缓存解档崩，接入方确认本 App 尚未发布、没有老用户，故一并处理。

### ⚠️ 破坏性：磁盘数据不兼容

**装了 1.26.0 或更早版本的设备，升级后阅读缓存与阅读偏好会被丢弃。**

| 数据 | 后果 |
| --- | --- |
| 章节正文归档 | 重新下载，无感 |
| 阅读进度 / 书签 / 目录归档 | **丢失，不可恢复** |
| 阅读偏好（主题 / 字号 / 行距 / 阅读方向） | 回到默认值 |

没有写迁移代码 —— 迁移要同时保留两套键名读一遍，为一个未发布的 App 引入长期负担不值得。

### 先补的兜底（这是改键名的前提）

`ReaderBookModel` / `ReaderChapterModel` / `ReaderReadRecordModel` 三个
`model(...)` 工厂原先是 `if isExist { 解档 } else { 新建 }`，解档失败（`as?` 得到 nil）
就把 nil 顺着非可选返回类型漏出去 —— 而这些类的字段是隐式解包可选，调用方访问
`name` / `content` 时崩。改成**先尝试解档，nil 则回落新实例**。

这本身是个该修的健壮性问题：**归档文件损坏在旧版本里就会崩**，只是没人遇到过。

### 归档键名与属性名对齐

36 个键全部改成和 1.26.0 之后的属性名一致，不再有
`priorChapterID = decodeObject(forKey: "previousChapterID")` 这种对不上的写法。
几个和对比方相同的：`previousChapterID` → `priorChapterID`、
`scrollOffsetInPage` → `pageScrollAnchor`、`chapterListModels` → `catalogueEntries`、
`pagingSignature` → `layoutFingerprint`、`headTypeHeight` → `headerInsetHeight`。
**注意 `ReaderArchiver.archivedClassNames` 里的类名字符串没动**，那张表和键名是两回事。

### 阅读偏好的 UserDefaults 键

`ReaderConfiguration.StoreKey` 九个键改成和属性名一致
（`bgColorIndex` → `themeType`、`lineHeightMultipleValue` → `lineHeightPercent`…）。
这一组本来就是安全的：`load(from:)` 逐键读、读不出保留属性声明处的默认值，
不会崩也不会读到半份配置。

### 章节标题正则

`localChapterTitlePattern` 默认值从 `第[0-9一二三四五六七八九十百千]*[章回].*`
改为 `第[\d〇零一二三四五六七八九十百千]*[章回节].*` —— 顺带多认「节」与「〇」。
只影响本地 txt 导入，纯网络书源的接入方走不到。

### 分页签名格式

`activePagingSignature()` 的拼串格式改写（原来带 `_leftAlign_indent` 字样）。
**格式本身没有语义**，只要「参数变了串就变」，所以随时可改；改了等于让已归档章节重排一次。
参与签名的参数一个没少。

### 协议改名

`ReaderThemeColors` → `ReaderTintPalette`（对比方也有同名类型）。具体类型
`ReaderTintAssign` 不变，接入方实现方只需改协议名。

### 关联对象 key 不再用字符串

`UIPageViewController+Extension` 里两个 `objc_setAssociatedObject` 的 key 从
`private var x = "x"` 改成 `private nonisolated(unsafe) var x: UInt8 = 0`。
关联对象只用变量**地址**，字符串值从来没人读，白留在 `__cstring` 里。
**新增关联对象照这个写法**，不要再用字符串当 key。

## 1.26.0

**破坏性变更：约 130 个成员 / 属性 / 实参标签改名。** 逻辑一行没动，纯改名。

### 为什么

二进制同质化比对报告（本包 vs 同团队另一款线上 App）列出 48 组
「类改名但成员未改」—— 类名换了、成员名一字未动，读起来就是「把抄来的代码改了个类名」。
其中 40 组在本库。这一版把它们清掉。

Swift 的**存储属性名会进 `__swift5_reflstr` 反射元数据**，`strings` 直接读得到，
`private` 也躲不掉；计算属性和普通方法不进。所以这次改的重点是存储属性，
外加剩余 `@objc` 成员的选择器（`@objc` 才会进 ObjC 选择器表）。

### ⚠️ 归档键名刻意没跟着改

六个参与 NSCoding 的模型里，属性改名了但 `forKey:` 的字符串**保持原样**，于是会看到
`priorChapterID = aDecoder.decodeObject(forKey: "previousChapterID")` 这种名字对不上的写法。
**这是对的，不要"顺手修一下"**：键名跟着改，已落盘的章节 / 书签缓存解档就拿到 nil，
而这些字段是隐式解包可选 —— 访问即崩，且只在老用户升级时才崩。

### 接入方必须改的公开 API

| 旧 | 新 | 所在 |
| --- | --- | --- |
| `previousChapterID` | `priorChapterID` | ReaderChapterModel |
| `nextChapterID` | `followingChapterID` | ReaderChapterModel |
| `pageModels` | `layoutPages` | ReaderChapterModel |
| `fullContent` | `typesetContent` | ReaderChapterModel |
| `headTypeHeight` | `headerInsetHeight` | ReaderPageModel |
| `headTypeIndex` | `headerKindRaw` | ReaderPageModel |
| `headType` | `headerKind` | ReaderPageModel |
| `alreadyLock` | `unlockState` | ReaderChapterListItemModel |
| `isVipContent` | `premiumZoneFlag` | ReaderChapterListItemModel |
| `cover` | `coverURL` | ReaderBookModel |
| `marks` | `bookmarks` | ReaderBookmarkCluster |
| `chapterName` | `chapterCaption` | ReaderBookmarkCluster |
| `scrollOffsetInPage` | `pageScrollAnchor` | ReaderReadRecordModel |
| `bookmarkId` | `remoteMarkID` | ReaderBookmarkDraft / Receipt / Syncing |
| `characterOffset` | `textLocation` | ReaderBookmarkDraft |
| `contentSnippet` | `excerptText` | ReaderBookmarkDraft |
| `readModel` | `bookModel` | ReaderViewController 等 11 处 |
| `readMenu` | `hostMenu` | ReaderViewController / ReaderMenuPanel |
| `readChapterIDs` | `visitedChapterIDs` | ReaderViewController |
| `currentDisplayController` | `visiblePageController` | ReaderViewController |
| `cachedEndViewController` | `terminalPageCache` | ReaderViewController |
| `chapterUnlockDelegate` | `accessDelegate` | ReaderViewController |
| `bottomView` | `statusFooter` | ReaderPageContentController |
| `bottomView` | `bottomBar` | ReaderMenu |
| `cover` | `nightTint` | ReaderMenu |
| `cover` | `dimOverlay` | ReaderContentView |
| `catalogBackgroundView` | `catalogueBackdrop` | ReaderMenu |
| `catalogView` | `cataloguePanel` | ReaderMenuBottomBar |
| `catalogView` | `catalogueList` | ReaderDrawerView |
| `funcView` | `settingsPanel` | ReaderMenuBottomBar |
| `progressView` | `progressPanel` | ReaderMenuBottomBar |
| `catalogueButton` | `catalogueTab` | ReaderMenuTabRail |
| `bottomTabBar` | `tabRail` | ReaderMenuSettingsPanel |
| `onChapterSelected` | `onChapterChosen` | ReaderMenuCataloguePanel |
| `clickPreviousChapter` / `clickNextChapter` | `goToPriorChapter` / `goToFollowingChapter` | ReaderMenuProgressPanel |
| `spaceLine` | `divider` | ReaderCatalogueCell / ReaderDrawerView |
| `chapterName` | `chapterTitleLabel` | ReaderStatusTopView / ReaderCatalogueCell |
| `chapterAscending` | `isAscendingOrder` | ReaderBookmarkListView |
| `isNightMode` | `isDarkTheme` | ReaderConfiguration / ReaderMenuTabRail |
| `hasUserSelectedTheme` | `themeChosenByUser` | ReaderConfiguration |
| `hasUserSelectedEffect` | `effectChosenByUser` | ReaderConfiguration |
| `frameRef` | `ctFrame` | ReaderPageView |
| `isTorB` | `isTopCursor` | ReaderLongPressCursorView |
| `isOpenDrag` | `isDragActive` | ReaderLongPressView |
| `customTapGestureRecognizer` | `pageTapRecognizer` | ReaderSheetController |
| `touchTap(tap:)` | `handlePageTap(tap:)` | ReaderSheetController（`@objc open`） |
| `previousChapter` / `nextChapter` | `priorChapterTitle` / `followingChapterTitle` | ReaderStrings |
| `chapterTitle` | `chapterCaption` | ReaderSpeechContext |
| `chapterNumber` | `chapterOrdinal` | ReaderPositionContext |

**实参标签也变了一个**（不改会编译报错）：

```
ReaderChapterAccessDelegate.readController(_:didAttemptToLoadLockedChapter:chapterName:chapterOrdinal:)
                                                                          ^^^^^^^^^^^  → chapterCaption:
```

主题色 16 个语义色改了 11 个名字，`ReaderThemeColors` 的实现方逐项对照：

| 旧 | 新 | | 旧 | 新 |
| --- | --- | --- | --- | --- |
| `textT0` | `textStrong` | | `iconDefault` | `iconStandard` |
| `textT1` | `textBody` | | `iconDisable` | `iconMuted` |
| `textT2` | `textSubtle` | | `fillPopup` | `fillSheet` |
| `textT3` | `textFaint` | | `fill2` | `fillAccent` |
| `textDisable` | `textMuted` | | `fill3` | `fillExtreme` |
| `dividerLine` | `separatorTint` | | | |

`page` / `fill` / `fillControl` / `line` / `accent` / 两个 `speechHighlight*` 没动。

### 刻意没改的

- **`pageViewController`**：接入方实现 `UIPageViewControllerDataSource` / `Delegate` 时，
  方法名和形参名也叫这个，token 层面分不开，自动改名会把协议实现改没。
  而且它本来就是 UIKit 的口径，撞名不构成证据。
- **`chapterID` / `chapterId` / `chapterModel` / `pageModel`**：域内自然命名，
  改成别的只会更难读；报告里它们是「一般」强度，不是铁证。
- **系统 API 名**（`titleLabel`、`panGestureRecognizer`、`setModalPresentationStyle:` …）：
  改不了，也不该改。

## 1.25.0

26 处按钮的 `addTarget(self, action: #selector(…))` 换成 `UIAction` 闭包，
连带去掉 28 个 `@objc`。**Swift 接入方无需改动**（改掉的方法全是 `private`，
三个 `open` 的只去了 `@objc`、名字和签名没动）。

### ⚠️ 这个改法有一个必须注意的陷阱

`addTarget(_:action:for:)` 里 **UIControl 对 target 是弱引用**，换成 `UIAction` 闭包之后
变成强持有，于是 `view → control → UIAction → self(view)` 成环。
**漏写 `[weak self]` 就泄漏整个阅读页，而且不报错、不崩溃。**

本次所有 27 处 `addAction` 都带了 `[weak self]`（唯一没带的是
`ReaderBookmarkDeleteSheet.configurePressBtn`，它转发的闭包在调用点已经 weak 过）。
后续新增按钮照这个写。

### 顺带清掉的东西

- **色块不再用 `button.tag` 传数据。** 以前 `button.tag = theme.rawValue`，点击时
  `ReaderThemeType(rawValue: sender.tag)` 反查；现在闭包直接捕获 `theme`。
  tag 当数据用一向容易和别处的 tag 语义撞车 —— 本类另外四个按钮就用 tag 存「能不能点」。
- **`clickVerticalMode` / `clickHorizontalMode` 两个纯转发的壳子删掉**，闭包直接调
  `alterReadingVariant(to:)`。
- **`buttonType: String` 参数删掉**（`alterReadingVariant` 与 `commitLineHeight` 各一个）。
  埋点下线之后它就没有读者了。
- `ReaderContentView.clickCover` → `handleCoverTap`，`ReaderMenuTopBar.clickBack` →
  `handleBackTap` 之类的改名，是因为 `clickXxx` 这个命名本来就是 target-action 的产物。

### 剩下 25 处 `@objc` 及各自的理由

| 用途 | 个数 | 能不能去 |
| --- | --- | --- |
| `UIGestureRecognizer` 的 target | 16 | 能，但要引入一个 target 代理对象（见下） |
| `NotificationCenter.addObserver(_:selector:)` | 7 | 能，但有实际退化风险（见下） |
| `UIMenuItem` + `canPerformAction(_:withSender:)` | 1 | **不能**。`UIMenuController` 没有闭包 API，`canPerformAction` 也是比 selector |
| `ReaderLongPressView` 里长按功能关闭后留的两个 | 2 | 不该去。注册代码是注释掉的，它们是文档化的恢复路径 |

**手势那 16 个**：UIKit 没给手势提供闭包 API，要去掉就得引入一个持有闭包的 `NSObject`
代理（里面仍有一个 `@objc func invoke`）。净效果是 16 个 `@objc` 变 1 个，代价是多一个
需要正确持有的对象 —— 漏持有的话手势静默失效。

**通知那 7 个**：`addObserver(forName:object:queue:using:)` 的 block 版本需要自己存 token
并在 `deinit` 里移除，而且不写 `[weak self]` 就强持有 self；而 selector 版本从 iOS 9 起
observer 析构时自动摘除。也就是说换过去**更容易出错，不是更安全**。
（`ReaderSpeechPlayer` 里已经在用 block 版本，那几个是播放期的短生命周期观察者、有显式移除。）

## 1.24.1

修「跟随系统深色模式」从来没生效过。**无破坏性变更，接入方无需改动。**

### 症状

全新安装 + 系统开着深色模式，第一次进阅读页是浅色的。

### 原因：`syncWithSystemDarkVariantIfRequired()` 一个调用者都没有

这个方法和它那一大段关于「为什么必须读 scene 级 traitCollection」的说明一直在库里，
但**库内和接入方都没有人调它**，所以整个功能是死代码。`hasUserSelectedTheme` 一直是 false，
主题一直停在属性声明的默认值 `.lightDefault`。

这是这个模块第二次出现同一类错误（上一次是「`.readerChapterListDidUpdate` 通知没人发，
导致目录列表补页后不刷新」）：**能力做好了、注释写清了，就是没接上线**，而且不报错。

### 接在哪

调用点收进库自己的生命周期，接入方不需要知道这件事：

- **`ReaderViewController.initialize()`** —— 建任何视图之前。必须早于 `addSubviews()`：
  菜单顶栏底色、正文底色、页眉页脚都在那之后按配置取色，定得晚会先用浅色渲染一帧再跳成夜间。
  放在这里首次进场没有闪烁，也不需要刷 UI。
- **`ReaderViewController.viewWillAppear`** —— 离开阅读页期间系统开关被改过，再进来时跟上。
  变了就走接入方现成的 `readerMenuDidChangeTheme` 换肤路径（点色块换主题走的是同一个）。
  正文还没上屏时跳过刷新：换肤会重建正文容器，那条路径要求阅读记录里已经有章节。

⚠️ **阅读页正在前台时改系统开关不会即时跟随**，要退出再进。因为接入方通常会
`window.overrideUserInterfaceStyle = .light` 把 App 锁成浅色，于是 VC 的 trait 根本不变、
`traitCollectionDidChange` 不触发，库拿不到通知。

### `detectSystemDarkVariant()` 顺带加固

- 多 scene（iPad 分屏）时取**前台**那个，原先取 `first` 可能读到后台 scene 的陈旧 trait。
- scene 还没建起来时退到 `UIScreen.main.traitCollection`，原先直接返回 `false`（当成浅色）。
  它同样不受 window override 影响。

## 1.24.0

`ReaderConfiguration` 从「十个 `@objc NSNumber!` 索引 + KVC 落盘」改成普通 Swift 存储属性 +
逐键读写。**破坏性变更**，接入方读写阅读配置的地方要跟着改（对照表在下面）。
至此库内再无 `@objc` 属性。

### 原来的设计有三个毛病，而且都不报错

```swift
@objc open var bgColorIndex: NSNumber!            // ← 十个这样的
…
if dict != nil { setValuesForKeys(dict as! [String : Any]) }   // ← KVC 读回
open override func setValue(_ value: Any?, forUndefinedKey key: String) { }   // ← 空实现
```

- **那个空实现把一切失败都吞了。** 键名写错、值类型不对、属性忘了标 `@objc` —— 全都不报错，
  表现是用户的阅读设置每次启动静默回到默认值。
- **十个 IUO。** 每个读取点 `.intValue` / `.boolValue`，每个写入点 `NSNumber(value:)`。
- **`effectType` 这类访问器是 `ReaderEffectType!`**（从 `Int` 反查枚举），
  也就是把「这个 Int 是不是合法枚举值」推到了运行时。

### 现在

存储属性直接就是配置本身，**没有「索引」这一层**：

```swift
open var themeType: ReaderThemeType = .lightDefault
open var effectType: ReaderEffectType = .scroll
open var fontType: ReaderFontType = .system
open var spacingType: ReaderSpacingType = .small
open var progressType: ReaderProgressType = .page
open var fontSize: Int = READER_FONT_SIZE_DEFAULT
open var lineHeightPercent: Int = 160
open var hasUserSelectedTheme = false
open var hasUserSelectedEffect = false
```

读回来在 `load(from:)` 里逐键显式取，**读不出来或不是合法值就保留属性声明处的默认值**。
所以「补默认值」的代码没有了 —— 默认值只写在属性声明上一处。漏一个键是看得见的
（那一行不存在），不再是静默回落。

磁盘上的键名**保持原样**（`bgColorIndex`、`lineHeightMultipleValue` …），登记在
`StoreKey` 里，所以已有的用户设置照旧读得出来。那几个字符串一经发布不要再改。

### 迁移对照表

| 1.23.0 | 1.24.0 |
| --- | --- |
| `config.bgColorIndex.intValue` | `config.themeType`（是枚举，不是 Int） |
| `config.bgColorIndex = NSNumber(value: t.rawValue)` | `config.themeType = t` |
| `config.effectIndex = NSNumber(value: m.rawValue)` | `config.effectType = m` |
| `config.fontIndex` / `spacingIndex` / `progressIndex` | `config.fontType` / `spacingType` / `progressType` |
| `config.fontSize.intValue` | `config.fontSize`（`Int`） |
| `config.lineHeightMultipleValue.intValue` | `config.lineHeightPercent`（`Int`） |
| `config.hasUserSelectedTheme.boolValue` | `config.hasUserSelectedTheme`（`Bool`） |
| `config.hasUserSelectedEffect = NSNumber(value: true)` | `config.hasUserSelectedEffect = true` |
| `config.themeSchemaVersion` | 不再对外，迁移用，已转为 private |
| `ReaderPalette.colors(forIndex:)` | `ReaderPalette.colors(for:)`（传枚举） |

`effectType` / `fontType` / `spacingType` / `progressType` 从 `Xxx!` 变成非可选，
`== .scroll` 一类的判断写法不变。

`lineHeightMultipleValue` → `lineHeightPercent`：原名说是「倍数」而存的是整数百分比
（160 = 1.6 倍），名字一直在说反话。用整数而不是 `CGFloat` 倍数是刻意的 ——
这个值要进分页签名做相等比较，浮点数没法判相等。

### 顺带

- `ReaderConfiguration` 不再继承 `NSObject`（KVC 没了就不需要了），
  `class func model(_:)` 与 `setValue(_:forUndefinedKey:)` 一并删除。
- `ReaderPalette.colors(forIndex:)` 删除。它是 `ReaderThemeType.allCases[index]` 的
  下标查表，依赖「rawValue 等于声明顺序」这个隐含约定；现在配置里存的就是枚举，不需要它了。

## 1.23.0

归档类名从 6 个类上的 `@objc(名字)` 挪进 `ReaderArchiver` 的一张映射表。
**磁盘格式一个字节都没变**（写下去的还是同样那 6 个字符串），Swift 接入方无需改动。
至此库内再无 `@objc` 类。

### 为什么挪

要解决的问题没变：Swift 类归档写入的类名默认是「模块名.Swift 类名」，于是改模块名或改
类名都会让已有归档读不出来 —— 而且是静默的（解档返回 nil → 上层当成本地没缓存 →
用户的进度、书签、已下载章节凭空消失）。

原先的办法是给 6 个类各挂一个 `@objc(Reader*Model)`。挪进映射表有两个好处：

- **不必为了归档把这些类暴露进 ObjC 运行时。** 本库没有任何 Objective-C 代码，
  那份暴露是白付的代价。
- **归档格式收在存储层一个文件里**，而不是散在 6 个文件的类声明上。改名字只看一处。

```swift
// ReaderArchiver.swift
private static let archivedClassNames: [(AnyClass, String)] = [
    (ReaderBookModel.self, "ReaderBookModel"),
    …
]
```

写盘改用 `NSKeyedArchiver(requiringSecureCoding: false)` + `setClassName(_:for:)`
（`archiveRootObject(_:toFile:)` 那条便捷方法不给机会设类名，而且 iOS 12 起已废弃）；
读盘改用 `NSKeyedUnarchiver(forReadingFrom:)` + `setClass(_:forClassName:)`
（顺带让原先那个抓不到任何错误的 `do/catch` 真正起作用）。

### 维护规则（比过去更要紧，因为编译器不再帮你）

**表里的字符串一经发布不可再改。** 新增归档类型必须在表里登记 —— **漏登记不报错**，
写盘时退回「模块名.类名」，于是下次改模块名它就悄悄失联。过去这条约束由 `@objc(名字)`
写在类声明上、比较难漏；现在集中了，代价是新增类型时要记得回来加一行。

### 顺带

`ReaderChapterListItemModel.id` 的 `@objc` 也去掉了：这个类只以 `init()` 构造，
从来没走过 `setValuesForKeys`，那个 `@objc` 没有用处。

## 1.22.1

去掉 23 处没有任何调用方的 `@objc`。**Swift 接入方无需改动**（`@objc` 不影响 Swift 侧调用）。

### 去掉了哪些

全部是 `@objc public class func`：`ReaderCoreText` 14 个、`ReaderTypesetter` 4 个、
`ReaderTextFileParser` / `ReaderFastTextFileParser` 各 1 个、三个 model 的 `model(storyID:...)`
工厂方法。

库里没有一个 `.m` / `.h` 文件，接入方也是纯 Swift —— 这些 `@objc` 是从 DZMeBookRead
继承下来的历史残留，白搭一份 ObjC thunk，还把参数类型钉在 ObjC 可表达的范围内。
性质与 1.21.0 那批协议一样：只有代价，没有用处。

### 剩下的 `@objc` 都是必需的，不要顺手清掉

`@objc` 在本库还有三处用法，每一处去掉都会出问题，而且**都不报错**：

1. **`@objc(ReaderXxxModel)` 固定类名 × 6** —— `NSKeyedArchiver` 把类名写进归档文件。
   改掉之后老用户的阅读进度、书签、已缓存章节全部反序列化不出来。
   `ReaderArchiver.swift` 里有专门的注释盯这件事。

2. **`ReaderConfiguration` 的 10 个 `@objc open var`** —— 阅读配置是以
   `[String: NSNumber]` 字典存进 `UserDefaults` 的，读回来走 `setValuesForKeys`（KVC），
   而 KVC 只认 `@objc` 属性。更要命的是 `setValue(_:forUndefinedKey:)` 被覆盖成空实现，
   所以去掉 `@objc` 既不报错也不崩溃，**每次启动静默把字号 / 行距 / 主题 / 翻页模式
   重置成默认值**。

3. **53 处 `@objc private/open func`** —— 全是 `#selector` 的靶子（按钮、手势、通知）。
   `#selector` 是编译期检查的，没有 `@objc optional` 那个静默失效的毛病。要去掉得把按钮
   换成 `UIAction`、手势包一层 proxy、通知换 block API 并自行管理 token，换来的是更多
   样板代码，不是改进。

## 1.22.0

抽屉头部的「全书共多少章」改成完整的文案注入点。**无破坏性变更**，不注入时默认值是
`20 Chapters`（1.21.0 及以前是 `Chapter 20`，词序与单复数都变了）。

### 新增 `ReaderStrings.chapterCount`

```swift
public var chapterCount: (_ count: Int) -> String = { count in "\(count) Chapters" }
```

此前那行是库内拼出来的：`"\(strings.chapter) \(totalChapterCount)"`。问题不在于词不对，
而在于**词序也是本地化的一部分** —— 英文是 `20 Chapters`，中文是「共 20 章」，
库没法替接入方决定。而且这里要的是复数形态，和目录 cell 前缀那个单数 `chapter`
根本不是同一个词，复用一个字段就注定有一处是错的。

用闭包而不是带 `%@` 的格式串，理由与 `chapterLoadFailed` 一致：占位符的数量与类型
在编译期不受检查。

`strings.chapter` 保持原样，仍然是目录 cell 前缀、菜单里当前章节标签用的单数词。

## 1.21.0

最后四个 `@objc` 协议改成原生 Swift 协议。**破坏性变更**，四个协议的方法名与代理属性
类型都变了，接入方必须跟着改，迁移对照表在下面。

### 为什么要改

这四个协议没有一个需要 Objective-C 运行时：没有 `respondsToSelector:` 判断、
没有 `performSelector`、没有 ObjC 侧的实现者。`@objc` 在这里只带来三样代价：

- **`@objc optional` 的方法签名写错不报错**，只会静默不被调用 —— 漏接表现为
  「点了没反应」，要靠运行时发现。
- **IUO 到处传染**：`open weak var delegate: XxxDelegate!` 与
  `viewController: UIViewController!`，调用方拿到的每个值都要自己判空。
- 参数类型被限制在 ObjC 可表达的范围内，`didClickMenuButton button: Int` 这种
  1/2/3 魔法数字只能用 `Int` 表达，而它本该是枚举。

改完之后：能不能不实现由协议扩展的默认实现明确表达，签名写错是**编译错误**。

### 迁移对照表

| 1.20.0 | 1.21.0 |
| --- | --- |
| `ReaderSheetController.aDelegate` | `ReaderSheetController.pageTapDelegate` |
| `pageViewController(_:getViewControllerBefore:)` | `sheetControllerDidRequestPreviousPage(_:)` |
| `pageViewController(_:getViewControllerAfter:)` | `sheetControllerDidRequestNextPage(_:)` |
| `contentViewClickCover(contentView:)` | `contentViewDidTapCover(_:)` |
| `catalogViewClickChapter(catalogView:chapterListModel:)` | `catalogueView(_:didSelect:)` |
| `catalogViewDidReachBottomEdge(catalogView:)` | `catalogueViewDidReachBottomEdge(_:)` |
| `catalogViewDidRequestRetry(catalogView:)` | `catalogueViewDidRequestRetry(_:)` |
| `markViewClickMark(markView:markModel:)` | `bookmarkListView(_:didSelect:)` |
| `markViewDidChangeMarks(markView:)` | `bookmarkListViewDidChangeBookmarks(_:)` |
| `markView(_:willExposeMark:)` | `bookmarkListView(_:willExpose:)` |
| `markView(_:willShowMenuForMark:)` | `bookmarkListView(_:willShowMenuFor:)` |
| `markView(_:didClickMenuButton:forMark:)` | `bookmarkListView(_:didSelectMenuAction:for:)` |
| `markView(_:requestDeleteMarks:completion:)` | `bookmarkListView(_:requestDelete:completion:)` |
| `markViewRequestClearAll(_:completion:)` | `bookmarkListView(_:requestClearAllWithCompletion:)` |

两个被删掉的参数：点击翻页那两个方法原来带 `viewController: UIViewController!`
（当前页），没有任何接入方用它，且用它就意味着接入方要自己管容器内部状态。

### 哪些方法现在是必须实现的

`ReaderSheetControllerDelegate`、`ReaderContentViewDelegate`、`ReaderCatalogueDelegate`
的全部方法都是**必须实现**的 —— 它们每一个都关系到基本可用性（翻不了页、收不起抽屉、
目录补不上），可选没有意义。

`ReaderBookmarkListDelegate` 只有两个必须实现：`bookmarkListView(_:didSelect:)` 与
`bookmarkListViewDidChangeBookmarks(_:)`。其余五个在协议扩展里有默认实现：

- 三个埋点回调默认什么都不做。
- **两个删除请求默认回 `completion(false)`，也就是不删。** 与 1.20.0 下
  「不实现 → completion 永远不被调用 → 列表不移除」的实际行为一致。书签要与服务端对账，
  宿主没接删除接口时本地不该自己删，否则换设备再进来它又回来了。

### `didClickMenuButton` 的魔法数字换成枚举

```swift
public enum ReaderBookmarkMenuAction {
    case remove     // 原 button: 1
    case clearAll   // 原 button: 2
    case cancel     // 原 button: 3
}
```

### 代理属性不再是 IUO

四个视图的 `delegate` 从 `XxxDelegate!` 变成 `(any XxxDelegate)?`。赋值方式不变，
只有「读出来直接用」的代码要补 `?`。

## 1.20.0

目录列表的「加载中」指示视图改成注入点。**无破坏性变更**，不注入的行为与 1.19.0 一致。

### 新增 `ReaderEnvironment.makeLoadingIndicator`

```swift
nonisolated(unsafe) public static var makeLoadingIndicator: (_ tintColor: UIColor) -> UIView
```

此前目录 footer 里硬编码 `UIActivityIndicatorView`，是库内唯一一处「外观没法被接入方覆盖」
的控件 —— 而 `images` / `fonts` / `strings` / `themeProvider` 都早就开成注入点了，
转圈的样式同样属接入方的设计体系（系统菊花、Lottie、自绘）。默认实现仍是系统菊花。

约定三条：

- **返回的视图自己会动。** 库不会调 `startAnimating()` 一类的方法，它不知道你给的是什么。
  收起时库把整个 footer 从 `tableFooterView` 摘下来，视图跟着离屏。
- **返回的视图要能自己决定大小**（有固有尺寸，或自带宽高约束）。库用**约束**把它居中、
  不设它的尺寸 —— 否则像 `LottieAnimationView` 这种没有固有尺寸的会是 0×0，
  表现为「loading 出现了但什么都看不到」。
- 主题切换时库会**重建**这个视图（`adoptThemeColors` 里），所以实现只需按传入的颜色
  一次性配置好。重建而不是改色，是因为接入方给的可能是 Lottie 那种配色烤在文件里的东西，
  库无从得知该改哪个属性。

`tintColor` 传的是当前阅读主题的次要文字色（`textT3`），用不上可以忽略。

## 1.19.0

`onPageDragEnded` 改为**只报方向**，「容器接手了没有」交给接入方判。
签名没变，但 1.17 / 1.18 的接入方必须跟着改判断方式，否则会漏触发或误触发。

### 用几何量判「翻不过去」是错的，两版都不成立

1.16.0 用「位移超过 20pt」就回调 —— 会在章内正常翻页时也回调。
1.17.0 改成「内部 scrollView 越出 contentSize 范围（橡皮筋）」，真机数据推翻了它：

```
内部 scrollView: offset=393.0 contentSize=1179.0 bounds=393.0   ← 3 页窗口，静止居中
回调触发 direction=backward     ← 在 page 10 / 9 / 8 / 7 / 6 / 5 / 3 / 2 上每次都触发
```

也就是往前拖时那个条件恒为真，而这些位置前面明明有页、容器也确实翻过去了。

容器内部怎么摆放那三页、什么时候重新居中，都是**未文档化**的，靠它反推状态不可靠。
所以这一版彻底不看几何量，回到按 `translation.x` 报方向。

### 接入方要怎么判

用 `UIPageViewControllerDelegate` 的 `pageViewController(_:willTransitionTo:)` ——
**容器一旦开始转场就会调它，从没调过就说明那个方向真的没有页**：

```swift
private var didBeginPageTransition = false

func pageViewController(_ pvc: UIPageViewController,
                        willTransitionTo pending: [UIViewController]) {
    didBeginPageTransition = true
}

sheet.onPageDragEnded = { [weak self] direction in
    guard let self else { return }
    let handled = self.didBeginPageTransition
    self.didBeginPageTransition = false
    guard !handled else { return }   // 容器自己在翻，别插手
    self.fallback(forward: direction == .forward)
}
```

这是文档化的回调，也是唯一能确定性回答「容器接手了没有」的信号。

### 另外提醒一次（1.18.0 已写过）

兜底里要换页时，**不要用 `setViewControllers` 复用容器** —— 那一刻内部 scrollView
还在回弹，复用会把它留在半页位置（正文被裁掉一截、画在页上的页码跑出屏幕）。
整个重建容器是安全的。

## 1.18.0

修 `onPageDragEnded`（1.16.0 新增）**一次都不会回调**。接口没变，1.16 / 1.17 的接入方
直接升级即可。

### 内部 scrollView 的发现时机错了

`UIPageViewController` 是**懒建**内部那个 scrollView 的，而 1.16.0 只在 `viewDidLoad` 与
`didMove(toParent:)` 里去找它 —— 这两个时机都早于第一次 `setViewControllers`，那时候它
通常还不存在。于是 `internalScrollView` 恒为 nil，拖动监听挂不上，`onPageDragEnded`
一次都不回调。

**而这不会报错，只表现为「滑动没反应」** —— 和它本来要修的症状一模一样，所以很难区分是
没接线还是没生效。

改成在 `viewDidLayoutSubviews` 里也找一次（两个方法都幂等，重复调只有第一次有成本）。
布局之后那个 scrollView 一定存在。

同一个坑也影响 `suspendPageTurn(_:)` 与 `requirePageScrollToFail(_:)`：它们内部都调
`ensurePrivateScrollView()`，此前只有在被调用得足够晚时才碰巧能拿到 scrollView。
现在统一由布局兜住。

### 给接入方的提醒

收到 `onPageDragEnded` 后如果要 `setViewControllers` 翻页，**传 `animated: false`**。
那一刻用户的手指刚离开、内部 scrollView 还在橡皮筋回弹中，带动画的切换会和它打架 ——
容器会停在两页之间，表现是正文被裁掉一截、固定页脚的页码也不见了。

## 1.17.0

修 `onPageDragEnded`（1.16.0 新增）的触发条件。**接口签名没变，但语义收窄了 ——
1.16.0 的接入方需要跟着简化。**

### 1.16.0 的判据会误报

那一版用「手指位移超过 20pt」判方向就回调，也就是**每一次有效拖动都回调**，包括章内正常
翻页那些。接入方如果在回调里直接翻页（而不只是「缺了才下载」），就会和容器自己的翻页动画
打架 —— 表现是连翻两页或画面错乱。

### 改成只在「容器确实没翻过去」时回调

判据换成内部 scrollView 在拖动结束那一刻**越出了 contentSize 的范围**：

- 那个方向还有页可去时，offset 始终落在 `[0, maxOffsetX]` 内，容器会自己完成翻页，
  **不回调**。
- 没有页可去时内部 scrollView 会橡皮筋越过边界再弹回，拖动结束的这一刻 offset 在区间外，
  **回调**。方向由越界的那一侧决定，不再需要位移阈值。

也不要按「offset 偏离一页宽」判（1.16.0 之前的草稿和参考实现都这么写）：静止 offset 只在
前后都有页时才等于一页宽，缺前一页时它是 0、两边都缺时也是 0，按偏离判会把正常拖动算成越界。

于是接入方拿到回调就可以直接动作，**不需要自己判「刚才翻成功了没有」**。

### 接入方要知道的一件事

`UIPageViewController` 在 `.scroll` 样式下问过一次 `viewControllerBefore/After`、拿到 nil
之后，会**缓存这个结论**，只要显示的 VC 不变就不再问第二次。所以「邻章第一次滑动时还没
下载、之后被预取补上」这种情况下，光靠 dataSource 是永远翻不过去的 —— 收到本回调后除了
「缺了就下载」，还要处理「已经有了就直接 `setViewControllers` 翻过去」，后者同时也让容器
重新问一遍邻居、作废那个缓存的 nil。

## 1.16.0

修「目录抽屉从不定位到当前章」，并补上「滑动到边界」的回调。**无破坏性变更，全部是追加或内部修复。**

### 修复：目录列表从不定位到当前章

`ReaderCatalogueView.scrollEntry()` 里的 `scrollToRow` 在**自身还没有尺寸**时是无效的
（而且不报错）。而抽屉的既有装配顺序是「先灌数据、再设 frame」—— `ReaderDrawerView` 以
`.zero` 创建，接入方在 `presentDrawer` 里先赋 `readModel`（`didSet` 链里就调了
`scrollEntry()`）、后设 frame。于是首次打开时定位必然落空，列表停在第一条。

当前章靠后时看起来像「没滚到位」，当前章是第 1 章时干脆看不出异常 —— 这也是它一直没被
发现的原因。

改法：尺寸不可用时记下待办，`layoutSubviews` 拿到尺寸后补做。同时把找行的 for 循环换成
`firstIndex(where:)`，并为「当前章不在已加载目录里」加了显式早退（分页目录下这是常态，
原先会走到 `row == -1` 然后静默什么都不做）。

### 修复：列表顶部偶发多出一段空白

`tableView.contentInsetAdjustmentBehavior` 设为 `.never`。抽屉以 `.zero` 创建时表格
恰好贴在屏幕左上角，会被判成「贴着安全区顶边」而自动加一段顶部 inset；等抽屉拿到真实
frame、inset 归零时 contentOffset 未必跟着回位。这个列表永远嵌在抽屉里、不贴屏幕边，
自动调整对它没有意义。

### 新增：`ReaderSheetController.onPageDragEnded`

```swift
public enum ReaderPageDragDirection { case forward, backward }
open var onPageDragEnded: ((ReaderPageDragDirection) -> Void)?
```

`UIPageViewControllerDataSource` 返回 nil 时，UIPageViewController **只是不让翻，不会
告诉任何人用户试过**。于是「邻章还没下载」这种情况下滑动就是死路：橡皮筋弹回来，没有任何
反馈 —— 而点击翻页有 `aDelegate` 那条路可以兜底。接入方拿这个回调把滑动也接到同一个
兜底实现上。

两个实现上的选择，接入方改这块前先看：

- **挂在内部 scrollView 已有的 pan 手势上，没有动 `scrollView.delegate`。**
  UIPageViewController 自己就是那个 delegate，它靠那些回调驱动转场与
  `didFinishAnimating`，换掉等于把容器的翻页记账拆了。同一个手势挂多个 target 是
  文档化的行为。
- **只报方向，不判断「翻成功了没有」。** 那件事要看宿主的阅读记录（是不是本章最后一页、
  邻章在不在本地）。内部 scrollView 的 contentOffset 在边界处含义不稳定：
  `viewControllerBefore` 返回 nil 时静止 offset 是 0 而不是一页宽，按「偏离中心」判会把
  每一次拖动都当成越界。

## 1.15.0

目录列表的加载态：修转圈跑到列表顶部，并补上失败态。**无破坏性变更，全部是追加。**

### 修复：目录列表的转圈会跑到列表顶部，压在前几行章节上

`ReaderCatalogueView.layoutLoadingFooter()` 把 footer 的 frame 整个重设成
`CGRect(x: 0, y: 0, width:, height:)` —— **连 origin 一起写了**。

`tableFooterView` 的位置本该由 UITableView 按 contentSize 计算。手动把 origin 写成
(0, 0) 之后，只有在表格下一次重新布局时才会被纠正；而 `layoutSubviews` 里那条
「宽度跟随列表」的复位又会把它重新按回原点（只改 origin 不改 size，表格不会因此重新
布局）。于是转圈停在列表坐标系的原点，视觉上浮在第 1~2 行章节上。

改成只设 `frame.size`，位置交给表格。高度确实变化时（转圈 44 ↔ 失败态 56）重新赋一次
`tableFooterView`，因为表格只在挂载时读一次 footer 高度，光改 frame 它不会给 contentSize
重新留位。

### 新增：目录 footer 的失败态

原先 footer 只有两态，判据是 `!readModel.isChapterListComplete` —— 它表达不了
「还没补完、但已经失败了」。后果是补页失败后转圈永久转，用户既看不出失败也没有重试入口。

- `ReaderCatalogueView.isCatalogueSupplyFailed`（`open var`，默认 `false`）：
  宿主在补页彻底失败时置 `true`，重新开始补页时置回 `false`。置位即刷新 footer。
- `ReaderCatalogueDelegate.catalogViewDidRequestRetry(catalogView:)`（`@objc optional`）：
  用户点了失败提示。与 `catalogViewDidReachBottomEdge` 分开 —— 那条是滚动自动触发、
  可以静默失败，这条是用户明确要求重试，宿主应当绕开失败计数一类的节流。
- `ReaderStrings.catalogueLoadFailed`：失败提示文案，默认
  `"Failed to load. Tap to retry"`。

三态由此闭合：目录完整 → 不挂 footer；未完整且未失败 → 转圈；未完整且已失败 →
可点重试的文案。**不设这个属性的接入方行为与 1.14.0 完全一致。**

## 1.14.0

`ReaderMenuDelegate` 从 Obj-C 形状改成原生 Swift 协议，并修「菜单呼出时还能翻页」。
**有破坏性变更，接入方必须改代码。**

### 破坏性变更（三项）

1. **`ReaderMenuDelegate` 不再是 `@objc` 协议**，改为 `public protocol ReaderMenuDelegate:
   AnyObject`。`@objc optional` 换成协议扩展里的空默认实现 —— 行为等价（不实现就没反应），
   但不再经 Obj-C 运行时，参数去掉了 IUO，`NSInteger` / `NSNumber` 换成 `Int`。

   方法按 Swift API 设计指南改名，第一个参数不再带标签：

   | 旧 | 新 |
   |---|---|
   | `readMenuWillDisplay(readMenu:)` | `readerMenuWillPresent(_:)` |
   | `readMenuDidDisplay(readMenu:)` | `readerMenuDidPresent(_:)` |
   | `readMenuWillEndDisplay(readMenu:)` | `readerMenuWillDismiss(_:)` |
   | `readMenuDidEndDisplay(readMenu:)` | `readerMenuDidDismiss(_:)` |
   | `readMenuClickBack(readMenu:)` | `readerMenuDidTapBack(_:)` |
   | `readMenuClickAddToBookshelf(readMenu:)` | `readerMenuDidTapAddToBookshelf(_:)` |
   | `readMenuClickFeedback(readMenu:)` | `readerMenuDidTapFeedback(_:)` |
   | `readMenuClickCatalogue(readMenu:)` | `readerMenuDidTapCatalogue(_:)` |
   | `readMenuClickPreviousChapter(readMenu:)` | `readerMenuDidTapPreviousChapter(_:)` |
   | `readMenuClickNextChapter(readMenu:)` | `readerMenuDidTapNextChapter(_:)` |
   | `readMenuDraggingProgress(readMenu:toPage:)` | `readerMenu(_:didSeekToPage:)` |
   | `readMenuDraggingProgress(readMenu:toChapterID:toPage:)` | `readerMenu(_:didSeekToChapter:page:)` |
   | `readMenuClickBGColor(readMenu:)` | `readerMenuDidChangeTheme(_:)` |
   | `readMenuClickFontSize(readMenu:)` | `readerMenuDidChangeFontSize(_:)` |
   | `readMenuClickLineHeight(readMenu:)` | `readerMenuDidChangeLineHeight(_:)` |
   | `readMenuClickEffect(readMenu:)` | `readerMenuDidChangeReadingMode(_:)` |

   `readerMenuDidChangeTheme` 换名是因为它从来就不只管背景色：日夜切换由库内自己改主题
   索引，改完回调的也是这一个方法，接入方在这一处做整套主题重刷。

   ⚠️ **默认实现和过去的 `@objc optional` 有同一个坑**：签名写错不报错，静默走默认实现。
   迁移时对照上表逐项核，不要靠「点了没反应」来发现漏改。

2. **删除五个从未被库内调用的回调**：`readMenuClickMark`、`readMenuClickDayAndNight`、
   `readMenuClickFont`、`readMenuClickSpacing`、`readMenuClickDisplayProgress`。
   前两个是历史残留（顶栏书签入口已随设计改版移除；日夜切换由库内处理、回调的是
   `readerMenuDidChangeTheme`），后三个在设置面板里没有对应控件。
   留着没人调的回调会让接入方以为自己接好了，实际是死代码。

   ⚠️ 接入方若把**加书签**的逻辑挂在 `readMenuClickMark` 上，那段逻辑此前就已经不会执行 ——
   库里没有任何加书签的 UI 入口（侧栏书签 tab 只能查看和删除）。删这个回调会让它变成编译
   错误，正好暴露问题。需要入口请自行在菜单或长按正文上加。

3. **删除 `ReaderMenuTopBar.verifyForMark()` 与 `reviseMarkBtn()`**。顶栏去掉书签按钮后
   这两个就是空实现，保留它们让调用方以为「这里刷新了书签状态」。

### 修复：菜单呼出时仍能左右翻页

呼出遮罩 `menuBackdrop` 不参与命中测试（这是对的，否则会把整块区域上的所有手势一起吃掉），
于是触摸穿透到下层的 `ReaderSheetController`，点击翻页手势照常识别 ——
症状是点半透明区域菜单收起的同时翻了一页。分三处治：

- **点击翻页**：`ReaderSheetController.gestureRecognizer(_:shouldReceive:)` 在菜单呼出时
  拒掉 `customTapGestureRecognizer`。只拒这一个手势。
- **滑动翻页**：新增 `ReaderSheetController.suspendPageTurn(_:)`，由
  `ReaderMenu.presentDropdown` 调用，只关内部 scrollView 的 pan。
  **不动 `isScrollEnabled` / `isUserInteractionEnabled`** —— 菜单开着时上一章 / 下一章 /
  拖进度条都走 `setViewControllers(animated:)`，那条路径依赖内部 scrollView 的偏移动画，
  整体关掉会一起废掉它。
  容器会在菜单呼出期间被重建（改字号 / 主题 / 阅读模式都会重建），新建的 pan 默认是开的，
  所以 `didMove(toParent:)` 里按当前菜单状态补一次。
- **滑动也要能收起菜单**：新增 `ReaderMenu.dismissPan`，装在 `contentView` 上，
  只在 `isMenuShow` 为真时允许开始，在 `.began` 那一下收菜单（不跟手）。
  `cancelsTouchesInView = false` 且对所有配对放开并存 —— 它只是个观察者，
  不吞触摸也不抢识别权，否则会把侧滑返回和滚动模式的正文滚动一起挤掉。

  排除区沿用 `shouldReceive` 那套（顶栏 / 底栏 / 目录面板 / 朗读 dock / UIControl），
  所以在底部面板上拖动不会把菜单收掉。

另外 `touchSingleTap` 里「滚动模式只有中间 1/3 响应」加了 `!isMenuShow` 前置：
那条限制只管**唤起**，菜单已呼出时点哪儿都该收起，再判位置会让点两侧毫无反应。

## 1.13.0

修页脚电量指示「填充两边顶满、看不出电池轮廓」。无破坏性变更。

### 修复：`ReaderImages.battery` 的默认值不成立

默认值原为 SF Symbol `battery.100`。**那个图形自带满格填充**，长宽比与留白也与
`ReaderBatterySize`（20×10）完全不同，库再把电量条叠上去就是一块实心疙瘩 ——
也就是说凡是**没注入自己切图的接入方开箱即错**，而错因在库里。

默认值改为 `nil`：此时 `ReaderBatteryView` 自己画外壳与正极头，几何照设计稿
Figma `253:40061` 折算：

| 元素 | 设计稿 | 折算比例 |
|---|---|---|
| 外壳 | 19×10，描边 1，圆角 2 | 宽 0.95、描边 0.1h、圆角 0.2h |
| 正极头 | (19,4) 1×2，右侧圆角 0.2 | 紧贴外壳无间隙，只右两角圆角 |
| 电量条 | (2,2) 高 6，圆角 1 | 内缩 0.2h，圆角 0.1h |

设计稿的电量条起点是 (2,2)，而 1pt 描边的内边缘在 (1,1) —— **描边与填充之间本来就留着
1pt 的缝，四边都留**。这道缝不是后加的修饰，缺了它满电时填充贴死内壁、与描边连成一片，
正是这次要修的观感。

用比例而非写死 pt，是因为 `ReaderBatterySize` 是公开可改的，接入方调大尺寸时应等比放大。

**注入切图这条路保持可用**：注入非 nil 时改用其切图作外壳，电量条仍由库按同一套比例绘制、
跟随主题色。注入的切图需遵守外壳比例（总宽 20 份中外壳占 19、正极头占 1，
描边宽为高度的 1/10），偏离太多时填充会对不上内腔 —— 这条约束已写进注入点的文档注释。

### 顺带修正

满电宽度从 14 改为 15（= 19 − 2×2）。旧值多留了 1pt，是为了躲一张来源不明切图的内壁；
现在外壳由库自己画，按设计稿四边等缝算即可。

低电量时电量条圆角改为夹在自身宽度的一半以内，避免那一小条被挤成一个点。

## 1.12.0

新增整屏朗读播放器页。无破坏性变更，全部是追加。

### 新增：`ReaderSpeechScreenController`

入口只有一处 —— 呼出菜单上 `ReaderSpeechDock` 播放态里的那个小书封。
接入方无需接线，引擎自行 present。

页面结构：放大书封铺底 + 高斯模糊 + 主题色罩 → 向下箭头 → 书名 / 章节名 →
156×208 书封 → 3 行正文窗口（当前朗读句居中并高亮）→ 上一章 / 播放暂停 / 下一章。

**它依附阅读器存在**：朗读状态、章节全文、跨章能力都来自 `ReaderSpeechController`，
而后者与 `ReaderViewController` 强绑定（26 处依赖）。所以只能由阅读器 present，
当不了「书架上继续听书」那种独立入口 —— 那需要先把朗读从阅读器解耦，属另一件事。

几处实现上的取舍：

- **正文窗口用固定 20 号排版**，不跟随阅读器的字号设置。窗口只有 3 行高，
  跟随大字号会退化成只看得见一行。
- **按整行显示，不露半行**。窗口高度不写死，而是按 CTFrame 的真实行边界
  （ascent / descent）取连续 3 行、目标行居中，高度收成这 3 行的实际高度。
  写死高度时行边界对不上，底部会露出下一行的上半截。
  为此把「版位」（固定 123，只用于给书封与控件定位）与「窗口」（实际高度）拆开 ——
  不拆的话段间距带来的几 pt 差异会把书封和控件位置带着晃。
- **窗口内容取「当前句所在段落 + 前后各一段」**。按段落而不是按字符数截取，
  否则窗口第一行会以半个词开头。
- **纵向布局是「上固定 + 下固定 + 中间弹性」**：导航与标题自上而下、控件与正文窗口
  自下而上，剩余空隙给书封居中。照设计稿绝对 y 摆会在非 812 高的屏幕上失准。
- **背景拆成模糊 + 色罩两层**：`UIVisualEffectView` 的 `backgroundColor` 会被自己的
  材质盖掉，压不住色。色罩取 `colors.page`，所以六套主题各自成立。
- **下拉关闭跟手**，用 `transform` 而非改 `frame`（后者每帧触发 `layoutSubviews`，
  正文窗口会跟着重排）。阈值为屏高 22% 或速度 1000pt/s，向上**不位移** ——
  本页是 `.overFullScreen`，向上挪一点底边就露出下层阅读器。
  松手关闭时顺着当前速度自己推出屏幕再无动画 dismiss，
  直接 `dismiss(animated: true)` 会先跳回原位再滑下去。

### 新增：`ReaderPageView.adoptContent(_:typesetSize:)`

允许调用方指定 CoreText 版面尺寸。既有的 `content` setter 把尺寸写死取
`READER_VIEW_RECT.size`（阅读区域），播放器页用固定字号、宽度也不是阅读区域宽，
但仍要复用本类的高亮绘制与 `rect(forRange:)` —— 另写一份必然与阅读页跑偏。

### 新增：`ReaderSpeechController` 的四个只读属性

- `speakingChapterText` / `speakingChapterTitle`：朗读中章节的全文纯文本与章节名。
  只给纯文本是因为取用方要用自己的固定字号重排，拿富文本反而要先剥属性。
- `hasPreviousChapterForSkip` / `hasNextChapterForSkip`：此刻能否跳章。
  播放器页的按钮置灰、锁屏命令可用性、跳章动作三处读同一个判断，不会发散。

### 变更：`ReaderSpeechDock` 的书封可点

新增 `onCoverAction`。此前书封是 `isUserInteractionEnabled = false` 的纯展示。

## 1.11.0

消掉句与句之间的渲染停顿，并让偶发的渲染失败自愈。无破坏性变更。

### 新增：预合成后续句

当前句进播放器后立刻预渲染后面 2 句，**只入缓存不播**，靠 `submitCurrentSentence()`
既有的缓存命中分支自然生效 —— 不需要把预合成产物交接给播放链路，少一条容易出错的路径。

两处时序是必须的，不是优化：

1. **挂在「当前句开始播」之后**，不能更早。渲染是串行的（`AVSpeechSynthesizer.write`
   并发会互相干扰、产出截断音频），提前提交只会跟当前句抢队列，把起播拖慢。
   等当前句进了播放器再排，队列必然空闲。
2. **`beginSpeaking()` 开头补 `renderer.cancelAll()`**。用户点「从这里开始读」时，
   这一句本来要排在最多 2 个预合成任务之后，白等一两秒 —— 而他刚点的这句才是最急的。
   已落盘的预合成音频不受影响，`cancelAll()` 只作废在途结果。

深度取 2 而非 1：一句通常播几秒、一次渲染 0.2~1 秒，理论上 1 句余量就够，
但短句（「他笑了。」）播完只要一秒多，余量太薄容易被追上。代价只是缓存多一个文件，
LRU 上限本来兜着。

### 新增：渲染失败重试一次

`ReaderSpeechRenderError` 新增 `isTransient`（纯追加，不破坏既有代码）：
`timedOut` / `renderFailed` 为 true，`voiceUnavailable` / `emptyText` 为 false ——
后两者重试一万次结果一样，只会白等一个超时周期。

瞬时性失败对同一句重提一次再放弃。系统侧 TTS 偶发不回调 / 返回空数据，
重提通常就成了；直接放弃会让用户看到一次莫名的「朗读失败」。每句只重试一次。

**预合成失败完全静默** —— 不提示、不打断朗读（用户根本不知道有这件事），
只撤掉标记，真正播到那句时才走正常渲染路径，那时才该报错。

### 关于降级路径：不做，理由记录在此

早期设计里「渲染持续失败时退回 `AVSpeechSynthesizer` 直接出声」是阶段三的一项。
现决定**不实现**，`ReaderSpeechSynthesizing` 整套仍保留但不接入编排层：

1. 它要求**双模播放** —— pause / resume / stop / 推进全部分流到播放器与合成器两套，
   等于把九个版本才拆掉的 `pauseSpeaking` / `continueSpeaking` 不可靠路径请回来，
   状态机翻倍。
2. **降级态下锁屏状态又会不对**，而那正是整个重构要解决的问题。用户会遇到
   「有时候锁屏是好的、有时候不是」，比稳定地失败更难排查。
3. **能救的场景比看起来少**：`voiceUnavailable` 降级同样失败（那条路也要音色）；
   `timedOut` / `renderFailed` 是系统 TTS 出问题，直接出声大概也不灵。
   真正只有「磁盘写满」这一种情况降级能救，而那时整个 App 都在出问题。

替代方案就是上面的「重试一次」，用几行覆盖绝大部分瞬时失败。若真机出现
「渲染反复失败导致读不了」，按实际原因针对性处理，比预先建一套双模机制划算。

## 1.10.0

朗读入口从「页脚常驻胶囊」改为「呼出菜单上的 dock」，并把锁屏跳章按钮按章节边界置灰。

### 新增：`ReaderSpeechDock`（呼出菜单上的朗读入口 / 迷你播放器）

一个视图两种形态，**只在菜单呼出期间可见**，菜单收起后由页脚胶囊接手：

| | 未朗读 | 朗读中 |
|---|---|---|
| 菜单展开 | dock 入口态（右下 54×54，耳机图标） | dock 播放态（左下 124×48，书封 + 进度环 + 关闭） |
| 菜单收起 | 无 | `ReaderSpeechActionButton`（页脚） |

两态**底边锚定在同一条线**（菜单面板收起态顶边上方 20），所以形态切换只动 x / width / height。
锚点按收起态算死，不跟踪面板动画的中间值 —— 设置面板展开时 dock 本来就要隐藏。

**库内零资源不变**：进度环、暂停/播放图标、关闭的 X 全部 `CAShapeLayer` 绘制
（环必须动态，本来画不成静态图；另两个图形足够简单，顺带免掉「播放态配什么图标」这个
设计稿没给的东西）。只有入口耳机图标需要图片，走新增注入点 `ReaderImages.speechDockEntry`
（默认 SF Symbol `headphones`）。书封走既有的 `loadRemoteImage` / `coverPlaceholder`。

接入方需要做的：在 `ReaderMenu` 初始化**之后**调一次 `installSpeechDock()`。
注意与 `installSpeechActionButton()` 的时机相反 —— dock 要浮在菜单遮罩之上，
页脚胶囊要被遮罩压住，两者层级要求相反。不调的话 dock 不出现，其余功能不受影响。

### 变更：页脚胶囊只在朗读中出现

`isSpeechActionButtonHidden` 现在只存接入方的隐藏**意图**，实际可见性再叠一个
「当前确实在朗读」。所以 `.idle` 一律不显示 —— 未朗读时入口在 dock 上，页脚不该常驻一个
「从这里开始读」与之重复，那条信息带本来就窄。

接入方代码无需改动：仍按「页脚让位就隐藏」写即可，朗读状态由引擎自己叠加。
**注意 getter 读到的是意图而非屏幕实际状态**，此前若有代码读它来判断可见性需复核。

### 新增：锁屏 / 控制中心的跳章按钮按边界置灰

首章时「上一曲」、末章时「下一曲」置 `isEnabled = false`，系统会画成灰色且点不动，
比「亮着但点了没反应」清楚。

`ReaderSpeechContext` 随之新增 `hasPreviousChapter` / `hasNextChapter`（带默认值，
既有构造点不受影响）。

**判据刻意不用 `queueIndex` / `queueCount` 推算**：`queueCount` 是当前**已知**章节数，
目录分页加载未完成时（实测出现过 `queue=239/1560`）会把中间章判成末章，
于是「下一章」在整本书大部分位置都是灰的。现在与 `skipToNextChapter()` /
`skipToPreviousChapter()` 读同一个跳章目标解析，「按钮可用」与「点了真的会跳」不可能发散。

目录未加载完时「下一章」会短暂置灰、补齐后自动恢复 —— 可用性每次写播放信息时重算
（即每句一次），不需要额外刷新时机。

### 修复：菜单手势吞掉 dock 上的点击

dock 内的点击此前会穿到菜单遮罩上，把菜单整个收起。三处都受影响：书封（点了本该什么都不做）、
进度环与关闭按钮（它们是带 tap 手势的普通 `UIView`，不是 `UIControl`，
既有的 `touchedView is UIControl` 排除条件兜不住，于是点暂停会顺带收起菜单）。
现在按视图层级整块排除。

### 新增：`ReaderSpeechController.chapterProgress`

当前章节的朗读进度（0...1），口径是「已读字符数 / 本章全文长度」，即当前句**句首**在本章
全文里的偏移除以全文长度。刻意不用时间比例 —— 时长本身是按字符数估算的，
拿它算进度等于绕一圈还是字符比例，中间还多一层误差。因此该值**按句跳变**而非连续增长。

### 主题

`ReaderThemeColors` 新增 `fillSpeechDock` / `textSpeechDock`，均带协议默认实现
（接入方零改动）。默认值是**固定深色 + 近白图标**，不从主题色派生：dock 浮在菜单遮罩之上，
遮罩已经把正文压暗，dock 再跟着主题变浅会糊进遮罩里。设计稿六套主题下也是同一块深色。

## 1.9.0

朗读发声路径从 `AVSpeechSynthesizer.speak()` 直出改为「先把句子合成为音频文件，
再用 `AVPlayer` 播放」。这是 1.8.3 结论的落地：`AVPlayer` 的播放状态系统能直接观测，
不需要 app 写 `nowPlayingInfo` 去通知，**从阅读页操作暂停/继续时锁屏与控制中心随之同步**。

该问题此前用九个版本从配置、时序、字段完整性各个角度试过，全部失败，
根因在架构而不在参数，见 `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。

### 破坏性变更（三项）

1. `ReaderSpeechController.init` 的 `synthesizer:` 参数改名为 `renderer:`，类型由
   `ReaderSpeechSynthesizing` 改为 `ReaderSpeechAudioRendering`。
2. `ReaderSpeechActivity` 新增 `.preparing`（合成中）。用 `if activity != .idle`
   这类判断的接入方不受影响；对该枚举做穷尽 `switch` 的需要补一个分支。
   **UI 侧无需改动** —— `ReaderSpeechActionState` 没有新增 case，`.preparing` 映射到
   `.playing`，胶囊照常显示暂停按钮（用户点了播放、意图已生效，不算假状态）。
3. 删除 `ReaderImages.speechStop` 与 `ReaderStrings.speechStop`。这两个注入点没有任何
   消费方 —— 库内胶囊只有「开始 / 暂停 / 继续 / 回到朗读位置」四个动作，
   停止由退出阅读器触发。保留一个没人用的注入点会让接入方以为自己漏接了。

### 新增

- `ReaderSpeechAudioRendering` 协议与 `ReaderSpeechAudioRenderer` 实现：基于
  `AVSpeechSynthesizer.write(_:toBufferCallback:)` 离线渲染，**不出声**。
  三种 PCM 格式（int16 / float32 / int32）归一后补 44 字节 RIFF/WAVE 头 ——
  裸 PCM 没有容器信息，`AVPlayer` 读不出时长，锁屏时间轴与播放结束判断都会失效。
- `ReaderSpeechAudioCache`：`Library/Caches/ReaderKitSpeech/`，键为
  `sha256(text + voiceIdentifier + rateMultiplier)`，200MB LRU 上限、超限删到 80%。
- `ReaderSpeechPlayer`：复用单个 `AVPlayer` + `replaceCurrentItem`。时长由
  `item.status` KVO 就绪后经 `speechPlayerDidLoadDuration` 上报（协议带默认空实现，
  接入方不必实现）。

旧的 `ReaderSpeechSynthesizing`（直接出声）整套原样保留，作为渲染持续失败时的降级路径。

### 修复

- **朗读对齐不再重排分页**。`ReaderReadRecordModel.modify(chapterID:location:)` 新增
  `anchorsParagraphToPageTop: Bool = true`；传 `false` 时跳过 `adoptBookmarkPaging(at:)`。
  该重排是书签定位专用（把书签段落顶到页首，代价是整章切开重新分页），
  朗读对齐复用同一入口后，表现为「左右翻页模式下锁屏切章、解锁回前台，正在读的句子被顶到
  页首、分页错位；朗读句在章首时排出一页只有标题、正文空白」。
  默认值不变，书签跳转行为不受影响。详见
  `.kiro/learnings/bugs/2026-09-16_bookmark-repaging-leaked-into-speech-align.md`。
- **修复连续朗读一段时间后崩溃**（`EXC_BAD_ACCESS`，栈在系统 `TextToSpeech.framework`）。
  渲染器原先每句新建一个 `AVSpeechSynthesizer`、函数返回即释放，连续听书会在短时间内
  创建销毁成百上千个系统对象，而系统侧仍可能持有回调。改为复用实例属性；
  超时放弃时补 `stopSpeaking(at: .immediate)` 中断在途的 `write`，
  避免下一句的 `write` 撞在同一实例的未结束渲染上（会产出截断音频并被缓存长期复用）。
- **修复雪崩式跨章**。`proceed` 原先用 `ReaderChapterModel.isExist()` 判断章节可读，
  而它只判归档文件存在；目录加载会建出只有标题的空壳章节，分句只得 1 句 →
  读完立刻结束本章 → 连锁跨章。改为新增 `hasReadableBody`（判 `content` 非空），
  空壳走网络加载，章节准备失败时停止朗读。
- **修复换章后重播上一句**。`renderer.cancelAll()` 拦不住已派发到主线程的 completion，
  改为在 `proceed()` 开头统一更新 `sessionID` 作废在途结果 ——
  跨章有两条路径都必经此处，在各调用点分别处理会漏。

### 移除

删掉为绕开 `AVSpeechSynthesizer` 异步往返而堆积的整套机制：`PendingIntent`（未决意图）、
`awaitsPauseSettle`（防迟到回调顶回状态）、`resumeOffsetInSentence`（记录已读字符数）。
`AVPlayer` 允许随时替换正在播放的内容，`pause()` 同步且幂等，这些都不再需要 ——
暂停/播放可以放心快速连点。

## 1.8.3

把本库与一个**已知能正常工作的参考实现**（FM，同机 iOS 26.6.1 上从 App 内暂停时锁屏与
控制中心状态完全同步）之间所有可枚举的非架构差异消除掉。两项改动本身是净改进，
但**没有**解决锁屏状态同步问题 —— 它们的价值在于把排除范围钉死，见下方结论。

### 变更：恢复 `.allowAirPlay` 与 `.allowBluetoothA2DP`

1.6.1 曾把这两个 option 删掉，理由是「`AVSpeechSynthesizer` 配 `MPNowPlayingInfoCenter`
时，`.playback` 上带**任何** option 都可能让系统不把朗读当作主播放源」。
**那个理由不成立** —— 参考实现带着这两个 option，锁屏状态完全正常。
删掉它们既没解决问题，又让我们与一个已知可用的配置无谓地产生差异。

`.duckOthers` 仍默认关闭。这一个是真的会让播放卡片整个消失（1.6.0 已验证），
与上面两个不是一回事。

### 新增：写入播放队列信息

补上 `MPNowPlayingInfoPropertyPlaybackQueueCount` 与 `...QueueIndex`（参考实现有，
我们此前完全没写）。**一项 = 一章**，与锁屏「上一曲 / 下一曲」映射为上一章 / 下一章
的语义一致，数据取自 `ReaderBookModel.chapterListModels`。
目录未加载完时给的是当前已知章节数，会随补目录变大 —— 与用户在目录里看到的一致。

`ReaderSpeechContext` 随之新增 `queueCount` / `queueIndex`（带默认值，
既有构造点不受影响）。日志增加 `queue=i/N` 一栏。

### 结论：锁屏状态不同步的原因已定位到架构，排除范围钉死

**现象要说准确**（此前描述得过头了，导致排查方向错）：

- 从**锁屏 / 控制中心**操作播放暂停 → 三处状态完全一致，**是对的**
- 从**阅读页**操作播放暂停 → 只有阅读页状态对，锁屏与控制中心不跟着变

所以不是「系统不采信我们写的 `rate`」，而是**系统只在自己发起命令并收到成功响应时才刷新
Now Playing UI，单纯的 `nowPlayingInfo` 写入驱动不了它**。

至此与参考实现的差异只剩一项：它用 `AVPlayer` 播放预先合成好的音频文件，
而我们用 `AVSpeechSynthesizer` 直接出声。`AVPlayer` 的状态变化系统能**直接观测**，
无需 app 通知；`AVSpeechSynthesizer` 只能靠 app 写 `nowPlayingInfo` 通知，而这条路
不触发 UI 刷新。

**已排除的路，不要再试**（每一条都做过真机验证）：

| 方向 | 结果 |
|---|---|
| category options（`.duckOthers` / `.allowAirPlay` / `.allowBluetoothA2DP`） | 无效；`.duckOthers` 另有其害 |
| `mode`（已是 `.spokenAudio`，与参考实现相同） | 无差异 |
| `usesApplicationAudioSession = false` | 更糟：锁屏无信息且声音出一下就停 |
| 弃用 `continueSpeaking()`、改重提交剩余句 | 状态变真了，图标照旧 |
| 补时间轴（时长 + 已播时间） | 无效，且把原本正常的锁屏页弄坏了 |
| 已播时间改为连续值（实际出声时长） | 无效 |
| 暂停时**不写**时间轴 | 无效，且暂停时进度条消失 |
| 远程命令 token 改进程级静态 | 无效 |
| 命令可用性跟随播放状态 | 无效 |
| 补 `PlaybackQueueCount` / `QueueIndex` | 无效 |
| `MPNowPlayingInfoCenter.playbackState` | **iOS 不可用**，Apple 官方确认是 macOS API，所需 entitlement 为 Apple 保留 |

根治只有一条路：改成「合成音频 + `AVPlayer`」。完整排查过程与方法论教训见
`.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。

## 1.8.2

本版是锁屏播放状态问题的**封版**：该问题在当前架构下确认无解，不要再在这条路上加补丁。
同时把排查过程中确认有效的两项改进落下来。

### 改进：锁屏已播时间改为**实际出声时长**

原先用「当前句句首的字符位置折算秒数」，那个值在整句朗读期间纹丝不动，
锁屏进度条会一顿一顿地跳。现在按实际经过的出声时间累计
（`didStart` 开始计时、暂停时结算、换章归零），连续且单调不减，
也自动包含了语速倍率与音色差异的影响。

### 修复：总时长不再被高估

排查中一度改为按「实测速率」外推总时长，结果刚起播时把一章算成三倍多
（`spokenLength` 取的是当前句**句首**位置，是离散值，读了 5 秒时它还很小，
据此算出的速率极低）。现在改回按字符数与语言平均语速估算 —— 绝对值不准但稳定，
只在「实际读得比估算慢、已播时间超过了估算总长」时才按已读比例外推，
避免出现「已播时间 > 总时长」这种自相矛盾的组合。

### 封版结论：锁屏 / 控制中心显示的播放状态不可信，当前架构下无解

现象：暂停后声音确实停了、库内状态也正确，那两处的按钮仍显示为播放中。

**九个版本的尝试全部失败**，逐一记录以免重走：

| # | 版本 | 假设 | 结果 |
|---|---|---|---|
| 1 | 1.6.1 | category 上的 option 干扰主播放源判定 | 无效 |
| 2 | 1.6.2 | `resume()` 里多余的 `activate()` 弄僵了引擎 | 修的是另一个真 bug，本问题无效 |
| 3 | 1.7.0 | `continueSpeaking()` 不可靠导致状态失真 | 状态变真了，图标照旧 |
| 4 | 1.7.1 | 缺时间轴，系统复核不到锚点就弹回 | 无效，且把原本正常的锁屏页也弄坏了 |
| 5 | 1.8.0 | 旧会话残留的远程命令 handler 抢答 | 无效 |
| 6 | — | `usesApplicationAudioSession = false`，让合成器用独立会话 | 更糟：锁屏完全无信息且声音出一下就停，已回退 |
| 7 | 1.8.1 | 命令可用性没跟随状态（参考项目是跟随的） | 无效 |
| 8 | — | 已播时间不连续导致系统判定信息矛盾 | 无效：`rate=0.0 elapsed=5/1110s`，图标照旧 |
| 9 | — | 症结在「暂停时存在时间锚点」 | 无效：`rate=0.0 timeline=omitted`，图标照旧，且进度条消失 |

决定性证据是真机日志：暂停时写出 `rate=0.0`（连写三次无人覆盖），而锁屏上显示的秒数
与日志里的已播时间**完全对得上** —— 系统读到了我们写的信息，标题、封面、时间轴全部采纳，
**唯独 `rate` 不采信**。第九版更进一步：连时间轴都不写，图标依然错。

根因：`playbackRate` 属于**声明**，而系统要的是**事实**。有真实播放器时事实来自 player
自己的 rate；`AVSpeechSynthesizer.speak()` 直接出声不是系统认账的 Now Playing 源
（同写法的三方阅读器在同机 iOS 26.6.1 上连播放信息都不显示；参考项目 FM 正常，
是因为它先把语音合成成音频文件再交 `AVPlayer` 播放）。

根治只有一条路：改成「合成音频 + `AVPlayer`」，已另行排期。
完整排查过程与教训见 `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。

**当前可用范围**：锁屏与控制中心能显示书名、章节名、封面、进度条，按钮**能真的控制声音**
（点暂停真的停、点播放真的继续），耳机线控正常，上一章 / 下一章正常。
只有播放 / 暂停的**图标显示**不可信。阅读器内的胶囊状态始终正确。

## 1.8.1

### 修复：频繁点暂停 / 播放之后朗读彻底没声音

**暂停不再用 `pauseSpeaking` / `continueSpeaking`，改为「停止 + 记住读到哪」。**

这一对 API 不可靠，而且它们的不可靠会互相放大。`continueSpeaking()` 可能不出声也
不投递任何回调（1.7.0 已经因此改掉了恢复路径，不再用它续读）。但**恢复路径仍然绕不开它**：
恢复要重新提交剩余文本，而 `speak` 只接受 `.idle` 状态，所以必须先 `stop()`；
而暂停态下直接 `stopSpeaking` 在部分系统版本上不投递取消回调，为了让回调可靠到达，
`stop()` 内部又不得不先调一次 `continueSpeaking()`。

于是「暂停 → 继续」这条路上藏着一次**可能永不返回的往返**。一旦命中，引擎永久停在
`.stopping`，此后所有提交都被 `speak` 拒掉，朗读彻底哑掉且无法自愈 ——
`stop()` 自己的 `guard state == .speaking || .paused` 也救不回来。
频繁点击只是提高命中概率，不是另一个独立缺陷。

改法是让引擎在暂停期间保持 `.idle`：

- `pause()` 走 `stop()`，同时把 `spokenPrefixLength` 累加进恢复偏移
- 新增 `PendingIntent.pause`，让取消回调**不要**走 `finishStop()`
  （那会清掉朗读位置并释放音频会话，暂停就变成了停止）
- `resume()` 因此可以**同步提交、立即出声**，不再有「先 stop 再等取消回调」的窗口

`activity` 在 `pause()` 里同步置位而不等回调 —— `stopSpeaking(.immediate)` 是同步停声的，
界面必须跟声音一起变。

**顺带修掉窗口期内的点击丢失。** 取消回调还在路上时（用户在极短时间内连点），
未决意图可以被反向覆盖：正在为「继续」而停止时点暂停会把 `.restart` 改回 `.pause`，
反之 `resume()` 会覆盖成 `.restart`。此前那种点击会被 `guard` 静默丢弃，
表现为「点了没反应」，用户于是继续点，反而更容易撞上上面那个死锁。

### 变更：远程命令的可用性跟随播放状态

播放时只有 `pauseCommand` 可用，暂停时只有 `playCommand` 可用
（`togglePlayPauseCommand` 始终可用，否则耳机线控与部分车机会完全失效）。
此前两个命令注册后就一直常开。

**这一改动没有解决锁屏按钮图标的问题**（见下方「未修」），保留它是因为按状态开关本身
更正确，参考项目也是这么做的。

### 修复：每次恢复朗读都把远程命令全表摘除重注册

1.8.0 为了摘掉旧会话的残留 token，去掉了「已注册就跳过」的短路 —— 但那样做过了头：
`resume()` 会走一遍 `activate()`，于是每次恢复朗读都全表重注册一次
（日志里表现为恢复时出现「摘除远程命令 target，共 5 个」）。
现在记住那套 handler 属于哪个实例，只有**不是自己那套**时才摘除重注册，
既保留跨会话清理残留的能力，又不再无谓抖动。

### 修复：迟到的 `didStart` 会把状态顶回「播放中」

改成「暂停 = 停止」之后暴露的时序问题：`stop()` 发出到取消回调到达之间，**上一次提交的
`didStart` 仍会到达**（回调是异步派发的，引擎侧的过滤只看 utterance 身份，
而 `clearCurrent()` 要到取消回调里才执行）。那一条会把 `activity` 顶成 `.playing`，
于是声音已停、界面与锁屏却都显示播放中，且不会自愈 —— 取消回调只负责收尾，不再纠正状态。

两道防守，各挡一段：

- `pendingIntent != nil` 时丢弃 `didStart`，覆盖「意图还没收尾」的那一段
- 新增 `awaitsPauseSettle` 标记跨越收尾，覆盖「迟到的 `didStart` 比取消回调更晚到」
  的那一段（取消回调会清空 `pendingIntent`，光靠它挡不住）

暂停的收尾分支也改为**重新确认** `activity = .paused`，而不是假设 `pause()` 里那次置位
仍然成立，并显式再写一次锁屏信息 —— `activity` 的 didSet 只在值变化时触发，
值没变时锁屏会停在上一次的 rate=1 上，表现为「阅读器内已暂停、锁屏还显示播放中」。

### 修复：提交与出声之间点暂停会丢失

`resume()` 现在是同步提交，从 `speak()` 到 `didStart` 之间 `activity` 仍是 `.paused`，
这期间点暂停会被 `guard activity == .playing` 丢掉，而引擎其实已经在出声 ——
用户看到「点了暂停没反应，声音还在读」。现在这种过渡态会直接执行停止。

### 变更：提交被引擎拒绝时退回暂停态，不再停掉朗读

`engineRejected` 此前的处理是弹提示 + `stop()`，那会把朗读位置一并清掉，用户想接着听
得重新翻回原处点一次。而被拒基本都是暂时的（上一次的取消回调还在路上），
现在改为保留位置、高亮与音频会话，退回暂停态等用户再点一次「继续」，且不再弹提示。

### 未修：锁屏 / 控制中心显示的播放状态不可信

与上面几条是两件事，且**在当前架构下修不了**，别再在这条路上加补丁。

现象：暂停后（无论从阅读器内还是从锁屏操作）声音确实停了、库内状态也正确，
锁屏与控制中心的按钮却仍显示为播放中。

真机日志（iOS 26.6.1）的决定性证据：

```
activity playing → paused
写锁屏信息 activity=paused rate=0.0 elapsed=1/291s artwork=true   ← 连写三次，无人覆盖
```

而同一时刻锁屏上显示的 `0:01` / `-4:51` **与日志里的 `elapsed=1/291s` 完全对得上**。
也就是说系统读到了我们写的信息，标题、封面、时间轴全部采纳，**唯独 `rate` 字段不采信**。

结论：`playbackRate` 与命令可用性都属于「声明」，而系统要的是「事实」——
`AVSpeechSynthesizer.speak()` 直接出声不是它认账的 Now Playing 源
（同写法的三方阅读器在同机上连播放信息都不显示，参考项目 FM 正常是因为它先把语音合成成
音频文件再交 `AVPlayer` 播放，给的是事实）。

为这一条改过六版都失败（去冗余 category option、修 `resume` 里多余的 `activate`、
弃用 `continueSpeaking`、补时间轴、远程命令 token 改进程级静态、命令可用性跟随状态），
排查记录见 `.kiro/learnings/decisions/2026-09-16_tts-nowplaying-needs-real-player.md`。
根治需要改成「合成音频 + `AVPlayer`」的架构，已另行排期。

## 1.8.0

### 修复：远程命令 target 会跨会话残留，导致控制中心按钮状态弹回

`registeredCommands`（远程命令的 target token 表）原先是**实例属性**。而
`MPRemoteCommandCenter` 是进程级单例，token 也只能通过它摘除 —— 曾经存在过的会话若没能
走完 `deinit` / `deactivate()`（阅读器被销毁但朗读没进 idle、异常退出路径等），
它的 handler 就永久留在响应链上，而新实例**摘不掉别人的 token**。

此后点锁屏 / 控制中心按钮，系统会同时收到「已处理」（活跃会话）与
「无可操作项」（僵尸会话）两种结果，可能据此判定命令失败并把按钮弹回原状 ——
现象是「声音确实停了、图标却马上变回播放中」，而且**随进出阅读器的次数累积而变严重**
（所以有时在锁屏页测不出来：那一轮的响应链还干净）。

改为进程级静态保存，并且**去掉「已注册就跳过」的短路** —— 需要保证的是
「全局只有一套活跃 handler」，而不是「本实例只注册一次」。每次注册前先把上一套摘干净。

### 新增：`ReaderEnvironment.log` 诊断日志出口

默认丢弃，接入方可接到自己的日志设施。朗读与远程控制这类路径**只能靠现象推断**，
没有日志时每轮排查都靠猜 —— 锁屏与控制中心的状态问题已反复多轮，代价很高。

已在这些位置打点：远程命令到达（play / pause / toggle）、命令因会话不可响应而回报
`noActionableNowPlayingItem`、远程命令 target 的摘除数量、`pause()` / `resume()` 进入时的
引擎与会话状态、`activity` 状态迁移、每次写入锁屏信息的 rate 与时间轴。

## 1.7.1

### 修复：控制中心点暂停后图标立刻弹回「播放中」

声音确实停了、App 内状态也对，只有控制中心的图标不对 —— 这是纯显示问题。

原因是**只改 `playbackRate` 不足以让系统确认状态变更**。控制中心会先乐观地把按钮改掉，
再读 `nowPlayingInfo` 复核，复核不到时间锚点就把按钮弹回原状。锁屏时 App 在后台，
系统更多靠「有没有真的输出音频」判断，所以那边看不出问题 —— 这也是为什么同一个缺陷
在锁屏页测不出来。

现在一并写入时间轴：

- `MPMediaItemPropertyPlaybackDuration`
- `MPNowPlayingInfoPropertyElapsedPlaybackTime`

值是按字符数折算的**估算**（CJK 约 5.5 字/秒，其余约 15 字符/秒），
只保证比例正确，绝对秒数不准。

这**推翻了此前「刻意不写时长与已播时间」的决定**。那个决定的理由是
「`AVSpeechSynthesizer` 拿不到真实时长，估算值与听感对不上」，但代价是播放状态显示错误。
两者取舍很清楚：进度条秒数不准可以接受，播放状态显示错误不能接受。
文件头与相关注释已同步更正，避免以后有人照旧结论把时间轴删回去。

拖动进度仍不开放（`changePlaybackPositionCommand` 保持禁用）—— 估算值不足以支撑精确落点。

`ReaderSpeechContext` 新增 `estimatedDuration` / `estimatedElapsed`
（带默认值，既有构造点不受影响），供自行接管锁屏的接入方复用同一套估算。

## 1.7.0

### 修复：从锁屏恢复朗读后不出声，且 App 与锁屏的状态彻底相反

**换了策略：不再用 `AVSpeechSynthesizer.continueSpeaking()` 恢复朗读。**

那个方法从锁屏 / 后台恢复时不可靠 —— 可能不出声，而且**不投递任何回调**。于是引擎僵死，
编排层却已把 `activity` 置成 `.playing`（界面显示「播放中」），而系统那侧按「有没有真的
输出音频」自己判断，锁屏按钮显示「已暂停」，两边完全相反。

1.6.1 与 1.6.2 试过两版修补（去掉 category options、按引擎状态兜底 + 只在会话非激活时
重配），都没能根治。本版不再在那条路上加补丁，改为**把当前句尚未读完的部分重新提交一次**：

- 每次恢复都是全新的 `speak`，有 `didStart` 回调确认
- `activity` 只在**确认出声后**才变 —— 状态必然真实，不会再出现假的「播放中」
- 恢复失败会走既有的失败回调，而不是静默僵死

为了让「从原处继续」而不是重读整句，新增逐词进度记录：

- `ReaderSpeechSynthesizing.spokenPrefixLength`：当前片段内已开始朗读的字符数。
  拿不到逐词进度的实现返回 0 即可，那样恢复时重读整句，功能正确、只是听感有重复。
- `ReaderSystemSpeechSynthesizer` 接上 `willSpeakRangeOfSpeechString` 维护它。
  **只做一次整数赋值、不触发任何重绘** —— 当初拒绝「词级高亮」是因为要重算矩形并重绘
  CoreText，与这里不是一回事。

代价：恢复时会重读当前词开头的几个字符，听感上几乎无感。

提交给引擎的文本是句子剩余部分，但 `ReaderSpeechFragment.range` 仍是**整句**范围 ——
高亮与翻页跟随都靠它，不能跟着截断。

`ReaderSpeechSynthesizing.resume()` 保留在协议里，供能保证 `resume` 可靠的自定义实现使用。

## 1.6.2

### 修复：从锁屏恢复朗读后出声约一秒即停，界面仍显示「播放中」

`resume()` 里无条件调了 `audioSession.activate()`，那会重新 `setCategory`。
**对处于暂停态的 `AVSpeechSynthesizer` 重新配置音频会话，它会丢掉当前 utterance
且不投递任何回调** —— 引擎从此僵死，而编排层已经把 `activity` 置为 `.playing`，
于是界面显示「播放中」却没有声音。

那次 `activate()` 本来也是多余的：唯一需要重新激活的场景是中断结束，
而那条路径（`handleInterruption(.ended)`）自己已经激活过了。

三处改动：

- `ReaderSpeechAudioSession` 自己记账 `isActive`（`AVAudioSession` 没有可查询的
  「是否已激活」）。`resume()` 改为**只在会话确实非激活时**才重新配置。
- `resume()` 增加防僵死兜底：若引擎已不在暂停态（utterance 已被系统丢弃），
  不再把 `activity` 置为 `.playing`，而是从当前句重新读 —— 宁可重复半句，
  也不要出现「显示播放中但没声音」的假状态。
- `ReaderSystemSpeechSynthesizer` 接上 `didPause` / `didContinue` 回调校正自身 `state`。
  在此之前 `pause()` / `resume()` 里的状态赋值只是**预期**，而上面那条兜底要靠 `state`
  判断，建立在预期值上没有意义。

## 1.6.1

### 修复：锁屏 / 控制中心的播放暂停按钮状态与 App 内不一致

1.6.0 去掉了 `.duckOthers`，锁屏信息因此显示出来了，但 `.playback` 上仍留着
`.allowBluetoothA2DP` 与 `.allowAirPlay`。`AVSpeechSynthesizer` 配
`MPNowPlayingInfoCenter` 时，category 上带**任何** option 都可能让系统不把朗读当作
「主播放源」，后果之一就是播放/暂停按钮的状态不跟着 App 变 —— 在锁屏点了暂停，
App 内确实暂停了（胶囊显示「继续」），锁屏按钮却仍是暂停图标。

这两个 option 对 `.playback` 本就是隐含行为，传了是冗余，现已去掉，
蓝牙耳机与 AirPlay 出声不受影响。`.duckOthers` 仍保留为可配置
（`ReaderSpeechCoordinating.speechDucksOtherAudio`），默认关。

后台播放不受这些选项影响（只依赖 `.playback` 与 `UIBackgroundModes: audio`），
所以这类问题的现象往往是「后台播放正常、锁屏却不对」，容易被误判成锁屏功能没做。

### 修复：上下滚动模式下刚松手时自动滚动介入会卡顿

用户手指或惯性还在滚动时，朗读的自动滚动会与之同时进行，两个滚动打架，
表现为明显卡顿甚至跳变，「刚松手、惯性还没停」那一小段最容易撞上。

现在自动跟随在 `isUserScrolling`（tracking / dragging / decelerating 任一为真）时
直接跳过本次 —— 跟随每句判两次，下一次会再来，跳过没有后果。
用户主动按返回箭头对齐的路径不受此限制，仍然立即执行。

新增 `ReaderScrollController.isUserScrolling`。

## 1.6.0

### 修复：锁屏 / 控制中心不显示播放信息

`.duckOthers` 与锁屏播放信息互斥。带上它之后音频会话的性质变成「与其它音频共存」，
系统就不再把朗读当作主播放源，`MPNowPlayingInfoCenter` 填了也不会在锁屏、控制中心、
灵动岛呈现。而后台播放只依赖 `.playback` 与 `UIBackgroundModes: audio`，不受这个选项
影响 —— 所以现象是「后台播放正常，但锁屏没有播放信息」，一个好一个坏。

`.duckOthers` 改为可配置，**默认关闭**（锁屏信息属硬需求，压低共存属偏好）：

- 新增 `ReaderSpeechCoordinating.speechDucksOtherAudio`，默认 `false`
- 置 `true` 可恢复「压低其它 App 音频而不是打断」，代价是失去锁屏卡片

### 修复：后台跨章重新分页用了不可信的安全区，回前台后正文排版错乱

`ReaderScreenMetrics.safeAreaInsets` 原先在取不到窗口时返回 `.zero`。而朗读跨章会在
**后台**触发 `ReaderChapterModel.reviseFont()` 重新分页，分页尺寸直接依赖安全区 ——
后台算出的尺寸与前台不一致，回到前台后正文就按那份错误分页渲染。实际表现为页数在
8 页 / 7 页之间来回变、首页大片空白、章节标题重复出现。

现在只认**前台激活场景**的安全区并缓存，后台（含锁屏）一律沿用缓存值，
保证「后台分的页」与「前台渲染用的尺寸」一致。顶部安全区取到 0 也视为不可信
（全面屏设备上它恒大于 0，取到 0 说明窗口还没布局好）。

### 新增：`ReaderSpeechController.refreshNowPlaying()`

供接入方在**异步资源就绪后**主动刷新锁屏信息。典型场景是封面图下载完成：
`nowPlayingArtwork()` 是同步接口、首次通常返回 nil（不能在那里同步等网络，会卡住朗读
推进），不主动刷新的话封面要等到下一次状态变化才出现 —— 表现为「锁屏上要切一次章，
封面才显示」。

## 1.5.4

### 修复：朗读中切主题 / 字号 / 行距，高亮消失要等下一句才回来

这些操作都会**重建正文视图**，而朗读高亮是写在具体某个 `ReaderPageView` 上的属性，
新建的视图身上没有它。左右翻页模式尤其明显：整个页控制器都是新建的，没有类似滚动模式
`willDisplay` 那样的钩子来补。

新增 `ReaderViewController.notifyBodyViewRebuilt()`，接入方在这些操作之后调一次即可
（本项目挂在 `creatPageController` 末尾，它是切主题 / 字号 / 行距 / 间距 / 阅读方向的
共同出口）。上下滚动模式的换肤路径在库内，已自行接好。

**这个入口刻意与 `notifyDisplayedPositionAlter()` 分开**：后者会参与「这次变更是不是
用户手动挪的」判定，而换肤换字号并没有挪动位置，走那条会被误判成手动操作、
把朗读跟随挂起。

## 1.5.3

### 修复：左右翻页模式下正文末行落到阅读区域之外

1.5.2 曾用「给正文视图套一层裁剪容器」来处理这个问题，那是错的 —— 它把末行**藏起来**
而不是修布局，结果末行直接看不到了。本版撤销裁剪，改掉真正的根因。

**根因是分页与渲染用了两个不同的尺寸。**

- 分页 `ReaderTypesetter.pageing` 按**阅读区域**切页，靠 `CTFrameGetVisibleStringRange`
  判定每页装得下哪些行
- 渲染时 `ReaderPageView` 却按 `pageModel.contentSize` 排版，而这个值是
  `attributedStringHeight` 在**无高度约束**（1000pt 的框）下量出来的，会把末行的完整行高
  与段后间距都算进去，因而高出阅读区域一截

CoreText 从版面顶部往下排，box 高一截就意味着末行落到阅读区域之外，压在页脚那条带上。
页脚自身 0.6 透明，所以早期只是看着发虚；叠上不透明的朗读胶囊后就成了明显遮挡。

现在左右翻页模式改为按**阅读区域**排版，与分页所用尺寸严格一致；上下滚动模式仍按
`contentSize`（那里一页就是一个 cell、cell 高度本就取 `contentSize`，内容流式衔接不会看不到）。
`ReaderLongPressController` 的 `readView` 高度同步改为阅读区域高度
（它原先取 `contentSize.height`，注释理由是「长按拖拽需要内容高度」）。

同尺寸不会丢行：同一段文字、同一个尺寸，CoreText 纳入的行数必然与分页时判定的可见行一致。

## 1.5.2

### 修复：上下滚动模式自动滚动后胶囊状态错误，要等下一句才恢复

`setContentOffset(_:animated: true)` 与 `scrollToRow(at:at:animated: true)` 结束时走
`scrollViewDidEndScrollingAnimation`，**不会**触发 `scrollViewDidEndDragging` /
`didEndDecelerating`（那两个只对手指拖动生效）。而容器只接了后两个，于是朗读驱动的
自动滚动落定后没有任何位置变更通报：胶囊不刷新，「朗读位置是否看得见」的判断停留在
滚动之前，界面上表现为自动滚动后错误显示「从这里开始读」。

同一个漏接还导致**自动滚过去的那段阅读进度没有保存**。

现已实现 `scrollViewDidEndScrollingAnimation`。

## 1.5.1

### 修复：上下滚动模式下胶囊状态与正文高亮互相矛盾

高亮明明画在屏幕中间，胶囊却显示「从这里开始读」。两个原因：

1. 句可见性只看「句首所在页」那一个 cell。句子跨页时句首在上一页，那一页滚出屏幕后
   `cellForRow` 取不到，于是判定「不可见」—— 而它的后半段正高亮在屏幕中间。
   现在取**所有可见页**上该句范围的并集。
2. 判定读的是「已经写进页面的高亮」，而跟随判定发生在高亮落笔**之前**
   （`alignPage(to:)` 早于 `reviseSpeechPresentation(for:)`），于是拿到的是上一句的结果。
   现在每页的范围都用 `highlightRange(inPage:chapterID:)` 现算。

算法与绘制走同一条链（`highlightRange` → `rangeRects`），所以这类自相矛盾不会再出现。

新增 `ReaderPageView.rect(forRange:)`：指定页内范围的外接矩形，不依赖高亮是否已写入。

### 修复：朗读胶囊与页脚页码没有对齐在同一条水平中线上

页脚带高 46，但里面那行内容是 y=16、高 22（`ReaderStatusBottomView.contentTopInset`
/ `.contentHeight`），行中心在带顶 +27 处。胶囊原先按**带**的垂直中心（+23）摆，
比页码高 4pt。现在按**内容行**的中心摆。

## 1.5.0

### 新增：胶囊挂载 API

1.4.0 只给出了胶囊控件本身，挂载、刷新、换肤全要接入方自己写一遍。本版把这套
样板代码收进引擎，接入方装一次即可，状态刷新由引擎自动驱动。

- `ReaderViewController.speechActionButton`：懒创建的胶囊实例
- `installSpeechActionButton()`：装到 `contentView` 并接好两个动作。
  层级刻意选在「正文与页脚之上、菜单遮罩之下」——正文容器与页脚都是插到
  `contentView` 底部的，菜单是后续 append 的，所以**要在菜单初始化之前调用**
- `reviseSpeechActionButton(animated:)`：按当前朗读状态刷新。朗读自身的状态变化
  （开始 / 暂停 / 继续 / 推进到下一句 / 位置对齐）引擎已自动调，接入方只需在
  **自己的翻页链路**里补一次（左右翻页模式的翻页在接入方那侧，引擎感知不到）
- `reviseSpeechActionButtonAnchor()`：重算锚点。取值来自 `READER_RECT`，
  不依赖布局时机，`viewDidLoad` 里就能算准
- `isSpeechActionButtonHidden`：显隐。读写都不触发创建，供接入方把胶囊的可见性
  挂到页脚那条信息带上（书末页、菜单展开等页脚让位的场景一起收起）
- `adoptSpeechActionButtonTheme(_:)`：换肤

主区域的点击语义也一并收进引擎：`.idle` / `.offPage` 从当前页开始读、
`.playing` 暂停、`.paused` 继续；返回箭头走 `returnToSpeakingPosition()`。

### 修复：左右翻页模式下自动翻页停摆、高亮消失

三个独立缺陷叠在一起，症状是「读到下一页却不翻页」「翻几页后高亮不见了」：

1. **跟随条件过严**。原条件是「句首所在页 == 当前页 + 1」。**大字号下单个长句能横跨两三页**，
   读完这种句子后下一句的句首直接落在两页之外，条件永远不成立 → 跟随彻底停摆，
   而且句子不在当前页上，高亮也就无处可画。现在相差一页仍走 `advanceToNextPageHandler`
   保留原生动画，相差超过一页改走 `presentPositionHandler` 一步跳过去。
2. **可见性判定用页码**。句子跨页时句首在上一页、句尾在本页，按句首页码比会判成
   「不在当前页」，于是胶囊切「从这里开始读」并触发多余翻页。改为复用
   `highlightRange(inPage:chapterID:)` —— 与高亮实际画不画同源，不会再出现
   「胶囊说在读当前页、正文里却没高亮」这种自相矛盾。
3. **换页后不补画高亮**。高亮是写在具体某个 `ReaderPageView` 上的属性，手动翻页后
   新页视图身上没有它，要等下一句开口才恢复。

两种模式的**触发条件现已统一**为「当前朗读句看不见了」，只有移动手段因模式而异
（翻页 / 滚动）。

手动挪动视图后的行为**两种模式现已完全一致**：跟随挂起，朗读照常推进，视图停在用户
挪到的位置。挂起有三条解除路径，第一条不需要用户操作：

1. **朗读自然推进到用户眼前这一页 / 这一屏** → 自动恢复跟随。往后翻去看后文时，
   等朗读读到那里就自动接上，不必点任何按钮。
2. 按返回箭头 → 立即对齐到朗读位置
3. 按「从这里开始读」→ 从眼前内容重新开始

挂起期间朗读句不可见，胶囊呈现「从这里开始读」，所以这个状态**对用户可见**，不是静默失效。

「用户是否手动挪过视图」的检测都建立在事实而非推断上：上下滚动用
`scrollViewWillBeginDragging`（明确的用户信号）；左右翻页没有等价信号，改用**一次性令牌**
—— 引擎发起位置变更时置令牌，收到下一次通报时消耗，未持令牌而收到通报即判为用户操作。

令牌刻意**不是**同步窗口：接入方的位置变更有同步的（普通翻页）也有异步的（章末需联网
加载下一章），同步窗口会把异步那条误判成用户操作，表现为每次跨章都错误挂起一次跟随。
令牌泄漏（请求发出但接入方最终没动，如下一章被锁）的退化方向是「少挂起一次」而非
「永久挂起」。

跟随每句判定**两次**：提交给引擎前（让翻页早于声音）与真正出声时（补判收敛）。
提交那一刻上一句的翻页动画可能还在飞、阅读记录也可能还没落定，单点判定失准就要等整句
才有下次机会。

另外补了一处：新页控制器刚被 `setViewControllers` 接进容器时视图加载是延后的，
此刻取不到正文视图，高亮会被静默跳过（表现为「翻过去这一整句都没高亮」）。
现在写高亮前会 `loadViewIfNeeded()`。

### 新增：位置变更通报

- `ReaderViewController.notifyDisplayedPositionAlter()`：接入方**必须**在自己的位置变更
  收口处调一次（翻页、跳章、解锁后续读）。引擎感知不到接入方的翻页动作，少调这一次
  会导致新页无高亮、且胶囊状态滞后。上下滚动模式无需接入方操心，容器在库内已接好。
- `ReaderSpeechController.reviseHighlightForDisplayedPage()`：把当前句在新展示页上重画。

### 修复：上下滚动模式下朗读位置与正文严重脱节

滚动模式的页码口径是「屏幕最顶端那一行像素所属的页」，屏幕上通常同时显示上一页的尾与
下一页的头 —— 也就是说**一页不等于一屏**，「当前页」的大半内容往往在可视区上方。
1.3.0 的朗读跟随全按页粒度做，在这个前提下三处同时错：

- **起点错**：「从这里开始读」取当前页页首，而页首早已滚到屏幕外，一开口读的是看不见的内容
- **不跟随**：跟随只在「目标页 == 当前页 + 1」时触发，整个页内推进期间一次都不滚，正文永远追不上
- **状态误报**：控制胶囊按「句在当前页」判定，于是显示「暂停」但正文里找不到高亮

改为按**句的实际矩形**处理。左右翻页模式行为完全不变（那里一页确实等于一屏）。

新增 API（均在 `ReaderScrollController`，供编排层使用）：

- `visibleStartPosition()` → 可视区顶端那一行的首字符，返回 `(章节模型, 章内坐标)`
- `isSpeechSentenceVisible` → 朗读句是否真的在可视区里
- `followSpeechSentence(animated:)` → 朗读推进时自动跟随，**尊重用户的手动滚动**
- `revealSpeechSentence(animated:)` → 用户主动要求对齐，无条件滚过去并解除挂起
- `resumeSpeechFollow()` / `containsSpeechChapter(_:)`

以及 `ReaderPageView`：

- `speechHighlightRectInView` → 高亮的外接矩形，已从 CoreText 坐标翻回 UIKit
- `characterIndex(atViewPoint:)` → 视图内某点落在第几个字符

两处刻意的行为设计：

1. **句子已在可视区内就不滚**（上下各留 24pt 余量）。逐句都滚会让正文持续微抖，比不跟随更难受。
2. **用户手动拖动后挂起自动跟随**，由控制胶囊的返回箭头解除。滚动模式分不清一次滚动是
   朗读驱动还是手指拖的，不挂起的话用户想往回看两段就会被下一句拽回来。挂起期间胶囊
   自动切到「从这里开始读」态。

`scrollToSpeechPage(chapterID:page:)` 保留但不再用于朗读跟随。

### 修复：左右翻页模式下朗读高亮从未显示

1.3.0 起朗读高亮在左右翻页模式下一次都没生效过。原因是 `ReaderLongPressView`
（`openLongPress` 默认开启，它才是实际渲染正文的视图）整个重写了 `draw(_:)`，
自己做坐标翻转 + `CTFrameDraw`，父类 `ReaderPageView.draw` 里那段高亮绘制根本不会执行。
上下滚动模式用的是 `ReaderPageView` 本体，所以不受影响。

修法是把绘制拆成模板方法：`ReaderPageView.draw(_:)` 负责坐标翻转、朗读高亮与正文，
子类改为重写新增的 `drawUnderlay(in:)` / `drawOverlay(in:)` 叠加自己的图形。
`ReaderLongPressView` 的选区色块已迁到 `drawUnderlay(in:)`。

**给子类的约定**：不要重写 `ReaderPageView.draw(_:)`。这类丢失编译期查不出来，
子类看起来只是「自己画自己的」。

### 修复：滚动模式下胶囊状态滞后

上下滚动模式的阅读记录更新（`ReaderScrollController`）此前不通知胶囊，
用户滚离朗读位置后胶囊仍显示「暂停」，点下去停的是别处的朗读。现已在
记录更新的收口处补上刷新。

## 1.4.0

### 新增：朗读控制胶囊

`ReaderSpeechActionButton` —— 一个四态复用的悬浮控件，供接入方放在正文页脚上方居中处。

| 状态 | 内容 |
|---|---|
| `.idle` 未朗读 | 🎧 从这里开始读 |
| `.playing` 当页播放中 | ⏸ 暂停 |
| `.paused` 当页已暂停 | ▶ 继续 |
| `.offPage` 朗读中但已翻到别页 | ↩ │ 🎧 从这里开始读 |

`.offPage` 状态有**两个独立点击区**：左侧箭头回到朗读位置（`onReturnAction`），
右侧从当前页重新开始读（`onPrimaryAction`）。其余状态只有主区域一个点击区。

状态切换带动画：图标与文字交叉溶解，返回段的淡入淡出与胶囊宽度变化同时进行，
时长与曲线复用 `READER_MENU_MOTION_TIME` / `READER_MENU_MOTION_OPTIONS`，与阅读菜单同步。

宽度由内容撑出，切换时**中心保持不动** —— 持有方只需设一次 `anchorCenter`。

### 新增 API

- `ReaderSpeechActionState`：胶囊的四个状态
- `ReaderSpeechController.actionState`：把「活动状态」与「朗读位置是否在当前展示页」
  收敛成上述枚举，界面直接照它渲染，不必自己判断位置关系
- `ReaderSpeechController.returnToSpeakingPosition()`：把正文跳回朗读位置。
  与内部的翻页跟随不同，本方法任意距离、任意方向都跳，供返回箭头调用
- `ReaderImages.speechReturnToPlaying`：返回箭头图标，默认 SF Symbol `arrow.uturn.left`
- `ReaderThemeColors` 增加三个色槽：`speechCapsuleFill` / `speechCapsuleText` /
  `speechCapsuleDivider`。**三者都有协议默认实现**，既有 conformer 无需改动：
  底色由 `textT1` 降透明度得到、图文取 `page`（与底色成反色关系），
  因此六套主题各自自动得到一组协调配色，无需逐套指定

### 接入方需要做的事

胶囊本身不自动挂载 —— 显隐时机与挂载位置属接入方的交互决策，需自行 `addSubview`
并在朗读状态变化时调 `apply(_:animated:)`。

## 1.3.0

### 新增：语音朗读（TTS）

设备端语音朗读，逐句朗读并在正文高亮当前句，支持后台播放与锁屏控制。
朗读能力开箱可用 —— 不实现任何新注入点也能完整工作。

新增源码集中在 `Sources/ReaderKit/Speech/`（8 个文件）与
`Sources/ReaderKit/Contracts/ReaderSpeechCoordinating.swift`：

- 分句走 `NLTokenizer(unit: .sentence)` 并按正文判定语言，多语种下不靠标点切分
- 合成引擎抽象为 `ReaderSpeechSynthesizing`，设备端实现 `ReaderSystemSpeechSynthesizer`
  用显式状态机规避 `AVSpeechSynthesizer` 在 iOS 15 的引擎死锁
- 音频会话含来电中断、拔耳机、媒体服务重置三类处理
- 锁屏 / 控制中心 / 灵动岛的播放信息与远程控制（play / pause / 上一章 / 下一章）
- 编排层负责翻页跟随、章节自动续读、高亮驱动

朗读入口与播放控件的 UI 尚未包含在本次变更内。

### 新增注入点（全部可选）

| 注入点 | 挂载位置 | 不注入会怎样 |
|---|---|---|
| `ReaderSpeechCoordinating` | `reader.speechCoordinator` | 朗读走库内默认行为（自管音频会话与锁屏）；锁屏无封面 |
| `advanceToNextPageHandler` | `reader.advanceToNextPageHandler` | 左右翻页模式下朗读不自动翻页（朗读本身照常推进） |
| `presentPositionHandler` | `reader.presentPositionHandler` | 后台听完回到前台时正文不对齐到朗读位置 |

### 其它新增

- `ReaderThemeColors` 增加 `speechHighlightFill` / `speechHighlightText` 两个色槽。
  **两者都有协议默认实现**（由 `accent` 派生），既有 conformer 无需改动；
  `ReaderTintAssign` 的初始化器末尾新增两个带默认值的可选参数供覆盖。
- `ReaderEnvironment.speechHighlightStyle` 选择高亮样式（背景色块 / 文字变色 / 下划线），
  默认背景色块。这是接入方的设计取向而非用户设置，故不入 `ReaderConfiguration`。
- `ReaderStrings` 增加 7 个朗读文案字段，`ReaderImages` 增加 4 个朗读图标，均带默认值。
- `ReaderPageContentController` / `ReaderLongPressController` / `ReaderPageCell`
  新增 `renderingPageView` 转发入口，供高亮等能力取到正在渲染的页视图。

### 接入方需要做的事

- **`Info.plist` 声明 `UIBackgroundModes` 含 `audio`**，否则没有后台播放。
  这是唯一的必做项，其余注入点不接也能用。

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
