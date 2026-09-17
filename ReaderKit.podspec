#
# ReaderKit —— 小说阅读器引擎（CocoaPods 接入清单）
#
# 与 Package.swift 指向同一份源码，二者并存的原因见 Package.swift 顶部说明：
# 部分工程的自研 Tuist DSL 只支持 .framework 依赖、不支持 SPM package，
# 而 CocoaPods 已在该工程的生成流程里（tuist generate 之后固定跑 pod install），
# 这类工程走本地 pod，其余走 SPM。
#
# 本地引入方式（Podfile）：
#   pod 'ReaderKit', :path => 'Modules/ReaderKit'
#
# 纯 Swift 单 target。原先进度条使用的 Objective-C 三方组件已用 Swift 重写，
# 故不再需要 OC 源码、伞形头文件与 public_header_files 配置。
#
Pod::Spec.new do |s|
  s.name             = 'ReaderKit'
  s.version          = '1.6.0'
  s.summary          = '小说阅读器引擎：排版分页、翻页与滚动、阅读菜单、目录书签、主题换肤'
  s.description      = <<-DESC
                       小说阅读器内核，库内零业务代码。
                       内容来源、章节解锁、书架收藏、埋点、页面跳转等均经注入点
                       由接入方提供，注入点定义见 Contracts/ 目录。
                       DESC
  s.homepage         = 'https://github.com/onexf/ReaderKit'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }
  s.author           = 'onexf'
  s.source           = { :git => 'https://github.com/onexf/ReaderKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.1'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/ReaderKit/**/*.swift'

  # AVFoundation / MediaPlayer / NaturalLanguage 为语音朗读所需：
  # 分别用于语音合成与音频会话、锁屏播放信息与远程控制、按句切分。
  s.frameworks       = 'UIKit', 'CryptoKit', 'AVFoundation', 'MediaPlayer', 'NaturalLanguage'
end
