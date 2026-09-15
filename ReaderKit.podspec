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
# 与 SPM 的一处差异：CocoaPods 原生支持单 target 混编 Swift 与 Objective-C，
# 故这里不必像 SPM 那样把 OC 拆成独立 target，source_files 直接全收。
# 引擎内的 canImport shim 在 pod 下条件不成立、自动为空段，不影响编译。
#
Pod::Spec.new do |s|
  s.name             = 'ReaderKit'
  s.version          = '1.0.0'
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

  s.source_files     = 'Sources/ReaderKit/**/*.{swift,h,m}', 'Sources/ReaderKitOC/**/*.{h,m}'
  s.public_header_files = 'Sources/ReaderKitOC/**/*.h'

  s.frameworks       = 'UIKit', 'CryptoKit'
end
