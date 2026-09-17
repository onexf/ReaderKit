//
//  ReaderSpeechVoice.swift
//  ReaderKit — Speech
//
//  朗读音色的中立模型。
//
//  为什么不直接用 `AVSpeechSynthesisVoice`：
//  编排层与将来的音色选择 UI 都只需要「标识、名字、语言、音质排序」这四样，
//  暴露 `AVSpeechSynthesisVoice` 会把编排层与设备端合成绑死，
//  二期换云端音色时整条链路都要改。
//

import Foundation

/// 一个可用于朗读的音色。
public struct ReaderSpeechVoice: Equatable {

    /// 音色标识。
    ///
    /// **不要持久化后无条件复用**：系统音色的 identifier 随设备型号、系统版本、
    /// 用户是否下载增强音色而变，同一个标识在另一台机器上可能不存在。
    /// 取用前必须校验，失效时按语言重新选取。
    public let identifier: String

    /// 音色展示名（系统提供，已本地化）。
    public let name: String

    /// 音色语言标签（如 `zh-CN`、`en-US`）。
    public let language: String

    /// 音质排序值，越大越好。
    ///
    /// 存序数而不存 `AVSpeechSynthesisVoice.Quality`：`.premium` 是 iOS 16 才有的
    /// 枚举成员，本库最低支持 iOS 15.1，直接引用会编译不过。比较序数则不受影响。
    public let qualityRank: Int

    public init(identifier: String, name: String, language: String, qualityRank: Int) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.qualityRank = qualityRank
    }
}
