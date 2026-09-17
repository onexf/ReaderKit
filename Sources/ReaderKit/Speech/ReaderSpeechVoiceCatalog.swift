//
//  ReaderSpeechVoiceCatalog.swift
//  ReaderKit — Speech
//
//  系统音色的枚举、筛选与默认音色选取。
//
//  筛选规则不是凭空定的，每一条都对应一个会被用户看见的问题：
//  不过滤老式音色，列表里会混进大量机器音效；不过滤 iOS 17 的趣味音色与个人音色，
//  读小说会突然冒出卡通腔或用户自己的克隆嗓音。
//
//  ⚠️ 刻意不用 `gender` 做任何筛选或分组。实测多数音色把 `gender` 报为
//  `.unspecified`（中文尤其明显），按性别筛会把大部分正常音色误排除。
//

import AVFoundation
import Foundation

/// 系统音色目录。
public enum ReaderSpeechVoiceCatalog {

    // MARK: - 对外查询

    /// 列出匹配指定语言的可用音色，按音质从高到低排序。
    ///
    /// - Parameter language: `ReaderSentenceTokenizer.detectLanguage(inBody:)` 的结果。
    ///   为 nil 时返回全部通过筛选的音色（不按语言过滤）。
    public static func voices(matchingLanguage language: String?) -> [ReaderSpeechVoice] {

        let installed = AVSpeechSynthesisVoice.speechVoices().filter { isSuitable($0) }

        let matched = filterByLanguage(installed, language: language)

        return matched
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .map { makeVoice(from: $0) }
    }

    /// 取指定语言的默认音色。
    ///
    /// 三级回落，顺序有讲究：
    /// 1. `AVSpeechSynthesisVoice(language:)` —— 系统为该语言选定的标准音色，
    ///    也会跟随用户在「设置 - 辅助功能 - 朗读内容」里的选择，最贴近用户预期
    /// 2. 同上，但改用主语言子标签重试 —— 语言识别给出的可能是 `zh-Hans` 这类
    ///    带文字系统的标签，而音色语言是 `zh-CN` / `zh-TW`，直接传进去取不到
    /// 3. 筛选后候选中音质最高者
    ///
    /// **不从候选里任意挑**：候选中含 Grandma、Rocko 一类音色（它们在 iOS 17 以下
    /// 没有 trait 可判别，过滤不掉），随便挑中拿来读小说非常突兀，所以只在前两级
    /// 都落空时才退到「音质最高」这个有序规则上。
    ///
    /// - Returns: 无任何可用音色时返回 nil，调用方应停止朗读并提示用户。
    public static func defaultVoice(forLanguage language: String?) -> ReaderSpeechVoice? {

        if let language, !language.isEmpty {

            if let standard = AVSpeechSynthesisVoice(language: language), isSuitable(standard) {

                return makeVoice(from: standard)
            }

            let primary = primarySubtag(of: language)

            if primary != language.lowercased(),
               let fallback = AVSpeechSynthesisVoice(language: primary),
               isSuitable(fallback) {

                return makeVoice(from: fallback)
            }
        }

        return voices(matchingLanguage: language).first
    }

    /// 按标识取回系统音色对象，供合成实现使用。
    ///
    /// - Returns: 标识在当前设备上不存在时返回 nil，调用方应回落到按语言选取。
    static func systemVoice(identifier: String) -> AVSpeechSynthesisVoice? {

        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    // MARK: - 筛选

    /// 老式语音合成音色的 identifier 前缀。
    ///
    /// 这批是 Mac OS 时代留下的音色，音质与断句都不适合长文朗读。
    private static let legacyVoiceIdentifierPrefix: String = "com.apple.speech.synthesis.voice."

    /// Eloquence 系列音色的 identifier 片段。
    ///
    /// 这一系列是高度机械的合成音，iOS 16 起随系统提供，出现在列表里会显得像故障。
    private static let eloquenceIdentifierFragment: String = ".eloquence."

    /// 判断音色是否适合用于小说朗读。
    private static func isSuitable(_ voice: AVSpeechSynthesisVoice) -> Bool {

        if voice.identifier.contains(eloquenceIdentifierFragment) { return false }

        if voice.identifier.hasPrefix(legacyVoiceIdentifierPrefix) { return false }

        if #available(iOS 17.0, *) {

            // 趣味音色（Bubbles、Jester 等）：卡通音效，读小说不合适
            if voice.voiceTraits.contains(.isNoveltyVoice) { return false }

            // 个人音色：用户为辅助功能录制的自己的嗓音，不该被小说朗读挪用，
            // 且取用它需要单独的授权流程
            if voice.voiceTraits.contains(.isPersonalVoice) { return false }
        }

        return true
    }

    /// 按语言筛选，精确匹配不到时放宽到同语种。
    private static func filterByLanguage(_ voices: [AVSpeechSynthesisVoice], language: String?) -> [AVSpeechSynthesisVoice] {

        guard let language, !language.isEmpty else { return voices }

        let exact = voices.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }

        if !exact.isEmpty { return exact }

        // 放宽到主语言子标签：识别结果 `zh-Hans` 匹配不到任何音色语言，
        // 但设备上装着 `zh-CN` / `zh-TW` / `zh-HK`，按 `zh` 前缀就能命中
        let primary = primarySubtag(of: language)

        let loose = voices.filter { primarySubtag(of: $0.language) == primary }

        return loose
    }

    /// 取 BCP-47 标签的主语言子标签（`zh-Hans` → `zh`），统一小写便于比较。
    private static func primarySubtag(of language: String) -> String {

        return language.split(separator: "-").first.map(String.init)?.lowercased() ?? language.lowercased()
    }

    // MARK: - 转换

    private static func makeVoice(from voice: AVSpeechSynthesisVoice) -> ReaderSpeechVoice {

        return ReaderSpeechVoice(identifier: voice.identifier,
                                 name: voice.name,
                                 language: voice.language,
                                 qualityRank: voice.quality.rawValue)
    }
}
