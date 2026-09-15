//
//  ReaderChapterRetryThrottle.swift
//  ReaderKit
//
//  Created by Kiro on 2026/05/25.
//

import Foundation

/// Throttle mechanism for chapter download retries.
/// Prevents high-frequency repeated requests when a chapter download fails
/// (e.g., due to network issues), which would otherwise flood analytics with
/// duplicate `book_download_failed` events.
///
/// Strategy:
/// - Cooldown: After a failure, the same chapter cannot be retried within `cooldownInterval` seconds.
/// - Max retries: After `maxRetryCount` consecutive failures, automatic retries are blocked
///   until the user performs a manual action (chapter switch, re-enter reader, etc.).
final public class ReaderChapterRetryThrottle {

    /// 库外需要直接实例化（宿主阅读器持有一个节流器实例），
    /// 而隐式生成的 init 是 internal，跨模块不可见，故显式提供。
    public init() {}

    // MARK: - Configuration
    
    /// Minimum interval (seconds) between retry attempts for the same chapter
    private let cooldownInterval: TimeInterval = 10.0
    
    /// Maximum number of automatic retries allowed per chapter
    private let maxRetryCount: Int = 3
    
    // MARK: - State
    
    /// Tracks failure info per chapter ID
    private var failureRecords: [Int: ReaderChapterFailureEntry] = [:]
    
    /// Serial queue to protect failureRecords from concurrent access
    private let queue = DispatchQueue(label: "com.readerkit.chapterRetryQueue")
    
    private struct ReaderChapterFailureEntry {
        var failureCount: Int
        var lastFailureTime: Date
    }
    
    // MARK: - Public API
    
    /// Check whether a retry is allowed for the given chapter.
    /// - Parameter chapterId: The chapter ID to check.
    /// - Returns: `true` if the request should proceed, `false` if throttled.
    public func shouldPermitReattempt(chapterId: Int) -> Bool {
        return queue.sync {
            guard let record = failureRecords[chapterId] else {
                // No previous failure, allow
                return true
            }
            
            // Exceeded max retry count → block until manual reset
            if record.failureCount >= maxRetryCount {
                return false
            }
            
            // Within cooldown period → block
            let elapsed = Date().timeIntervalSince(record.lastFailureTime)
            if elapsed < cooldownInterval {
                return false
            }
            
            return true
        }
    }
    
    /// Record a failure for the given chapter.
    /// Call this after a download/request failure occurs.
    /// - Parameter chapterId: The chapter ID that failed.
    public func entryFailure(chapterId: Int) {
        queue.sync {
            if var record = failureRecords[chapterId] {
                record.failureCount += 1
                record.lastFailureTime = Date()
                failureRecords[chapterId] = record
            } else {
                failureRecords[chapterId] = ReaderChapterFailureEntry(failureCount: 1, lastFailureTime: Date())
            }
        }
    }
    
    /// Reset throttle state for a specific chapter.
    /// Call this when the user manually triggers a retry (e.g., taps retry button,
    /// selects chapter from catalog, or re-enters the reader).
    /// - Parameter chapterId: The chapter ID to reset.
    public func reset(chapterId: Int) {
        queue.sync {
            _ = failureRecords.removeValue(forKey: chapterId)
        }
    }
    
    /// Reset all throttle state.
    /// Call this when the reader is re-initialized or the user switches books.
    public func resetAll() {
        queue.sync {
            failureRecords.removeAll()
        }
    }
}
