//
//  ReaderSpeechAudioCache.swift
//  ReaderKit — Speech
//
//  合成音频的磁盘缓存。
//
//  ---------------------------------------------------------------------------
//  这是 ReaderKit **唯一**会往磁盘写东西的地方。
//
//  库的既有约束是「零资源、零落盘」，这里打破了后半条，所以边界必须写死：
//
//  1. 只写 `Library/Caches/ReaderKitSpeech/`，不碰沙盒里任何其它位置。
//     选 `Caches` 而不是 `Documents`：音频随时可以重新合成，不该占用户的 iCloud
//     备份额度；代价是系统在磁盘紧张时会回收它，用户重听需要重新等待合成，
//     这个取舍见 spec 的决策记录第 4 项。
//  2. 有容量上限，超限自行淘汰，不指望系统回收。
//  3. 接入方可以随时全部清空（宿主的「清除缓存」入口）。
//
//  为什么需要缓存：出声路径是「先合成音频文件、再交 `AVPlayer` 播放」，
//  单句合成在真机上约两秒。没有缓存的话，用户每次回听同一段都要重新等。
//  ---------------------------------------------------------------------------
//

import CryptoKit
import Foundation

/// 合成音频的磁盘缓存。
///
/// 线程约定：`url(for:)` 可在主线程同步调用（只做一次文件存在判断，很轻），
/// 写入与淘汰在内部串行队列上执行。
final class ReaderSpeechAudioCache {

    // MARK: - 配置

    /// 默认容量上限：200MB。
    ///
    /// 参考实现用的是 500MB，但它按「段」（一段含多句，最长 200 字）切分；
    /// 我们按**句**切，文件更碎、单个更小，200MB 已能存下相当多章节。
    static let defaultSizeLimit = 200 * 1024 * 1024

    /// 容量上限（字节）。超限时按最近最少使用淘汰。
    var sizeLimit: Int

    // MARK: - 内部持有

    /// 缓存目录。创建失败时为 nil，此时整个缓存降级为「永不命中」，
    /// 朗读仍然可用（每句现合成），只是失去复用。
    private let directory: URL?

    /// 文件操作串行队列。
    ///
    /// 写入与淘汰必须串行：淘汰要先扫目录再删，与并发写入交错会算错总量、
    /// 甚至删掉刚写进去的文件。
    private let ioQueue = DispatchQueue(label: "com.readerkit.speech.audio-cache")

    private let fileManager = FileManager.default

    // MARK: - 构造

    init(sizeLimit: Int = ReaderSpeechAudioCache.defaultSizeLimit) {

        self.sizeLimit = sizeLimit

        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {

            directory = nil

            ReaderEnvironment.log("[Speech] 取不到 Caches 目录，音频缓存不可用")

            return
        }

        let target = caches.appendingPathComponent("ReaderKitSpeech", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

            directory = target

        } catch {

            directory = nil

            ReaderEnvironment.log("[Speech] 音频缓存目录创建失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 读写

    /// 查询片段对应的音频文件。命中时返回文件位置，否则返回 nil。
    ///
    /// 命中会刷新文件的修改时间（异步），让淘汰顺序反映真实使用频次而不是写入时间。
    func url(for fragment: ReaderSpeechFragment) -> URL? {

        guard let url = fileURL(for: fragment) else { return nil }

        guard fileManager.fileExists(atPath: url.path) else { return nil }

        touch(url)

        return url
    }

    /// 写入片段的音频数据，返回落盘位置。
    ///
    /// 写入后异步检查总量并按需淘汰。写入失败返回 nil —— 调用方应当仍然能播放
    /// （直接用内存里的数据），只是这次没被缓存下来。
    @discardableResult
    func store(_ data: Data, for fragment: ReaderSpeechFragment) -> URL? {

        guard let url = fileURL(for: fragment) else { return nil }

        do {
            // .atomic：写一半被杀掉会留下截断的音频文件，而它的文件名（哈希）看起来是有效的，
            // 下次会被当成命中直接播放 —— 那种坏数据比没有缓存更难查
            try data.write(to: url, options: .atomic)

        } catch {

            ReaderEnvironment.log("[Speech] 音频写入失败：\(error.localizedDescription)")

            return nil
        }

        evictIfNeeded()

        return url
    }

    /// 删除某个片段的缓存音频。
    ///
    /// 用于播放失败时剔除坏数据：截断或损坏的音频文件，其文件名（内容哈希）看起来
    /// 完全有效，不删掉的话下次还会命中它，陷入「每次读到这句就失败」的循环。
    func remove(for fragment: ReaderSpeechFragment) {

        guard let url = fileURL(for: fragment) else { return }

        ioQueue.async { [weak self] in

            try? self?.fileManager.removeItem(at: url)

            ReaderEnvironment.log("[Speech] 剔除损坏的缓存音频 \(url.lastPathComponent)")
        }
    }

    // MARK: - 容量管理

    /// 当前占用字节数。
    ///
    /// ⚠️ 需要遍历目录，文件多时不快，**不要在主线程调用**。
    /// 供宿主的「清除缓存」界面显示用。
    func currentSize() -> Int {

        ioQueue.sync { totalSize(of: contents()) }
    }

    /// 清空全部缓存。
    ///
    /// 供宿主的「清除缓存」入口调用。正在播放的音频文件已被 `AVPlayer` 打开，
    /// 删除不影响当前播放（Unix 语义：已打开的 inode 不会真正消失）。
    func removeAll() {

        ioQueue.async { [weak self] in

            guard let self, let directory = self.directory else { return }

            let entries = self.contents()

            for entry in entries {

                try? self.fileManager.removeItem(at: entry.url)
            }

            ReaderEnvironment.log("[Speech] 音频缓存已清空，删除 \(entries.count) 个文件")

            // 目录本身可能被一起删掉（`contents()` 只列文件，但保险起见重建一次）
            try? self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// 超限则按最近最少使用淘汰到水位线。
    private func evictIfNeeded() {

        ioQueue.async { [weak self] in

            guard let self else { return }

            let entries = self.contents()

            var total = self.totalSize(of: entries)

            guard total > self.sizeLimit else { return }

            // 删到上限的 80% 而不是刚好压到上限：贴着上限会导致之后几乎每次写入
            // 都触发一次全目录扫描
            let target = Int(Double(self.sizeLimit) * 0.8)

            // 最久未使用的先删
            let ordered = entries.sorted { $0.modified < $1.modified }

            var removed = 0

            for entry in ordered {

                guard total > target else { break }

                do {
                    try self.fileManager.removeItem(at: entry.url)

                    total -= entry.size

                    removed += 1

                } catch {

                    // 单个文件删不掉（正在被播放器持有等）不该中断整轮淘汰
                    continue
                }
            }

            ReaderEnvironment.log("[Speech] 音频缓存淘汰 \(removed) 个文件，剩余 \(total / 1024 / 1024)MB")
        }
    }

    // MARK: - 辅助

    /// 目录内的文件清单，带体积与修改时间。
    ///
    /// 调用方须保证在 `ioQueue` 上，或明确知道自己不与写入并发。
    private func contents() -> [(url: URL, size: Int, modified: Date)] {

        guard let directory else { return [] }

        guard let urls = try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: [.fileSizeKey,
                                                                                          .contentModificationDateKey],
                                                             options: [.skipsHiddenFiles]) else { return [] }

        return urls.compactMap { url in

            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }

            return (url, size, modified)
        }
    }

    private func totalSize(of entries: [(url: URL, size: Int, modified: Date)]) -> Int {

        entries.reduce(0) { $0 + $1.size }
    }

    /// 片段对应的文件位置。
    private func fileURL(for fragment: ReaderSpeechFragment) -> URL? {

        guard let directory else { return nil }

        return directory.appendingPathComponent(cacheKey(for: fragment) + ".wav")
    }

    /// 缓存键。
    ///
    /// **必须覆盖影响音频内容的全部因素**：文本、音色、语速。漏掉任何一项，
    /// 用户换了音色或语速后会听到旧音频，而且无从察觉哪里不对。
    ///
    /// 刻意**不含** `fragment.range` —— 同一句文本在不同章节位置应当命中同一份音频。
    private func cacheKey(for fragment: ReaderSpeechFragment) -> String {

        let source = [fragment.text,
                      fragment.voiceIdentifier ?? "",
                      String(format: "%.2f", fragment.rateMultiplier)].joined(separator: "\u{1}")

        let digest = SHA256.hash(data: Data(source.utf8))

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 刷新修改时间，供 LRU 排序。
    private func touch(_ url: URL) {

        ioQueue.async { [weak self] in

            try? self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
    }
}
