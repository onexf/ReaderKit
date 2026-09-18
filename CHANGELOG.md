# Changelog

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
