# Engine 注入点协议

本目录存放阅读器引擎对外部能力的**抽象契约**。引擎只依赖这些协议，
具体实现由接入方提供并注入。

## 命名约定

库内一律用中立命名，不带任何接入方的专属类型前缀 —— 本库供多个项目引用，
带某个 App 前缀的名字在其它项目里会显得突兀，也会把库与特定项目绑在一起。

协议命名用 `-ing` / `-able` 形式表达能力（`ReaderTerminalPageProviding`、
`ReaderContentSourcing`），避免与数据类型混淆。

## 硬约束

- **库内不得出现对业务模块的引用**。需要接入方能力时在本目录定义协议。
- 协议只用 UIKit / Foundation / Combine 的类型，不引用任何业务模型。
- 协议应可选实现（提供默认实现或允许 nil），以便其他项目按需接入。

## 当前协议清单

| 协议 | 替代的业务依赖 | 状态 |
|---|---|---|
| `ReaderTerminalPageProviding` | 书末页控制器 | 已接线 |
| `ReaderLocalizing` | 文案本地化 | 待做 |
| `ReaderTelemetry` | 埋点上报 | 待做 |
| `ReaderContentSourcing` | 内容接口、目录分页与合并、CDN 调度 | 待做 |
| `ReaderPreferencesStoring` | 远程开关与用户配置存储 | 待做 |
| `ReaderProgressStoring` | 进度与书签持久化 | 待做 |
| `ReaderAccessPolicy` | 锁章判定与解锁回调 | 待做 |
| `ReaderSupplementaryUI` | 空态、推荐、反馈入口等宿主视图 | 待做 |
