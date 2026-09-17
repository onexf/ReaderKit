//
//  ReaderSentenceTokenizer.swift
//  ReaderKit — Speech
//
//  把章节文本切成「句」，句是朗读与高亮的基本单元。
//
//  为什么按句切，而不是整章一条 utterance：
//  - 句级高亮需要一个明确的范围，整章方案只能靠引擎回调反推，粒度不受控
//  - 章节边界、朗读起点、锁章拦截都需要一个稳定的停止点
//
//  为什么用 NLTokenizer 而不是按标点自行切分：
//  本库支持多语言接入，阿拉伯语、泰语、日语的句读规则与中英不同，
//  按标点切会切错（泰语甚至不用空格分词）。NLTokenizer 按语言处理这些差异。
//

import Foundation
import NaturalLanguage

/// 一个朗读单元。
public struct ReaderSentence {

    /// 句在**章内绝对坐标**中的范围。
    ///
    /// 坐标基准是 `ReaderChapterModel.fullContent`（章节标题 + 正文），
    /// 与 `ReaderPageModel.range`、`ReaderChapterModel.page(location:)` 同一基准，
    /// 因此无需换算即可反查页码与求交集。
    public let range: NSRange

    /// 句文本（已去除首尾空白）。
    public let text: String

    public init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// 分句与语言判定。
public enum ReaderSentenceTokenizer {

    // MARK: - 语言判定

    /// 从**正文**判定内容语言，返回 BCP-47 语言标签（如 `zh-Hans`、`en`、`ja`）。
    ///
    /// 取样只用正文（`ReaderChapterModel.content`），**不要传 `fullContent`**：
    /// 章节标题往往很短且含数字编号（「第 12 章」），会把识别结果带偏。
    ///
    /// - Note: 切句用的是 `fullContent`，判定语言用的是 `content`，两者用途不同，不要混。
    /// - Returns: 判定失败（文本过短、混排无主导语言）时返回 nil，调用方应走各自的默认行为。
    public static func detectLanguage(inBody body: String) -> String? {

        let sample = String(body.prefix(languageSampleLength)).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sample.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()

        recognizer.processString(sample)

        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else { return nil }

        return dominant.rawValue
    }

    /// 语言判定的取样长度。
    ///
    /// 取够识别精度即可，整章几千字全喂进去只是白耗 CPU。
    private static let languageSampleLength: Int = 600

    // MARK: - 切句

    /// 把章节全文切成句。
    ///
    /// - Parameters:
    ///   - fullText: **必须**传 `ReaderChapterModel.fullContent.string`（标题 + 正文）。
    ///     传 `content` 会让所有句的坐标整体偏移一个标题长度，表现为高亮错位与翻页跳错。
    ///   - language: `detectLanguage(inBody:)` 的结果。为 nil 时让 `NLTokenizer` 自行判断。
    /// - Returns: 按位置升序、互不重叠的句数组。去除首尾空白后为空的片段会被丢弃。
    public static func sentences(inFullText fullText: String, language: String?) -> [ReaderSentence] {

        guard !fullText.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)

        tokenizer.string = fullText

        // 显式指定语言。不指定时 NLTokenizer 会自行推断，但正文里夹杂英文引文、
        // 数字、标点时推断结果不稳定，切出来的句长会忽长忽短。
        if let language, !language.isEmpty {

            tokenizer.setLanguage(NLLanguage(rawValue: language))
        }

        var result: [ReaderSentence] = []

        let source = fullText as NSString

        tokenizer.enumerateTokens(in: fullText.startIndex ..< fullText.endIndex) { tokenRange, _ in

            let nsRange = NSRange(tokenRange, in: fullText)

            let raw = source.substring(with: nsRange)

            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // 纯空白片段（段落间的空行、缩进空格）不值得朗读，也不该占一个高亮单元
            if !trimmed.isEmpty {

                result.append(ReaderSentence(range: nsRange, text: trimmed))
            }

            return true
        }

        return result
    }

    // MARK: - 定位

    /// 查找包含指定章内坐标的句下标。
    ///
    /// 判定口径与 `ReaderChapterModel.page(location:)` 保持一致：取第一个满足
    /// `location < NSMaxRange(range)` 的句。这样两种情形都能得到合理结果：
    /// - 坐标落在某个句内 → 返回该句
    /// - 坐标落在被丢弃的空白间隙里 → 返回其后的那个句
    ///
    /// - Returns: 坐标越过最后一个句时返回 nil。
    public static func sentenceIndex(forLocation location: NSInteger, in sentences: [ReaderSentence]) -> Int? {

        guard !sentences.isEmpty else { return nil }

        // 句数组按位置升序且互不重叠，可以二分。长章节几千句，线性扫描在
        // 每次句推进时都要跑一遍，累积起来不划算。
        var low = 0

        var high = sentences.count - 1

        var candidate: Int?

        while low <= high {

            let mid = (low + high) / 2

            if location < NSMaxRange(sentences[mid].range) {

                candidate = mid

                high = mid - 1

            } else {

                low = mid + 1
            }
        }

        return candidate
    }
}
