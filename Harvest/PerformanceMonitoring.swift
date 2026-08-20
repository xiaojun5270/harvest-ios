import Foundation
import MetricKit
import os

enum HarvestPerformanceOperation: String, Sendable {
    case appLaunch = "APP 首屏启动"
    case apiRequest = "API 请求"
    case dashboardLoad = "仪表盘加载"
    case sitesLoad = "站点加载"
    case mediaSearch = "影视搜索"
    case resourceSearch = "资源搜索"
    case tmdbLoad = "TMDB 加载"
    case doubanLoad = "豆瓣加载"

    fileprivate var slowThreshold: TimeInterval {
        switch self {
        case .appLaunch: 2.0
        case .apiRequest: 2.5
        case .dashboardLoad, .sitesLoad: 2.0
        case .mediaSearch, .resourceSearch, .tmdbLoad, .doubanLoad: 3.0
        }
    }
}

final class HarvestPerformanceInterval: @unchecked Sendable {
    private let operation: HarvestPerformanceOperation
    private let context: String?
    private let startedAt: TimeInterval
    private let lock = NSLock()
    private var completion: (() -> Void)?

    fileprivate init(
        operation: HarvestPerformanceOperation,
        context: String?,
        completion: @escaping () -> Void
    ) {
        self.operation = operation
        self.context = context
        startedAt = ProcessInfo.processInfo.systemUptime
        self.completion = completion
    }

    func end() {
        let finish: (() -> Void)?
        lock.lock()
        finish = completion
        completion = nil
        lock.unlock()
        guard let finish else { return }

        finish()
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if elapsed >= operation.slowThreshold {
            let label = [operation.rawValue, context]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            recordAppLog(.warning, "性能监控：\(label) 耗时 \(Self.durationText(elapsed))")
        }
    }

    deinit {
        end()
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        if duration < 1 { return "\(Int((duration * 1_000).rounded()))ms" }
        return String(format: "%.2fs", duration)
    }
}

final class HarvestPerformanceMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = HarvestPerformanceMonitor()

    private let signposter: OSSignposter
    private let stateLock = NSLock()
    private var isStarted = false
    private var launchInterval: HarvestPerformanceInterval?

    private override init() {
        let metricLogHandle = MXMetricManager.makeLogHandle(category: "Performance")
        signposter = OSSignposter(logHandle: metricLogHandle)
        super.init()
    }

    func start() {
        stateLock.lock()
        guard !isStarted else {
            stateLock.unlock()
            return
        }
        isStarted = true
        stateLock.unlock()

        MXMetricManager.shared.add(self)
        launchInterval = begin(.appLaunch)
        recordAppLog(.info, "原生性能监控已启用（OSSignposter + MetricKit）")
    }

    func finishLaunch() {
        stateLock.lock()
        let interval = launchInterval
        launchInterval = nil
        stateLock.unlock()
        interval?.end()
    }

    func begin(
        _ operation: HarvestPerformanceOperation,
        context: String? = nil
    ) -> HarvestPerformanceInterval {
        let signposter = self.signposter
        switch operation {
        case .appLaunch:
            let state = signposter.beginInterval("App Launch", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("App Launch", state)
            }
        case .apiRequest:
            let state = signposter.beginInterval("API Request", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("API Request", state)
            }
        case .dashboardLoad:
            let state = signposter.beginInterval("Dashboard Load", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("Dashboard Load", state)
            }
        case .sitesLoad:
            let state = signposter.beginInterval("Sites Load", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("Sites Load", state)
            }
        case .mediaSearch:
            let state = signposter.beginInterval("Media Search", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("Media Search", state)
            }
        case .resourceSearch:
            let state = signposter.beginInterval("Resource Search", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("Resource Search", state)
            }
        case .tmdbLoad:
            let state = signposter.beginInterval("TMDB Load", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("TMDB Load", state)
            }
        case .doubanLoad:
            let state = signposter.beginInterval("Douban Load", id: signposter.makeSignpostID())
            return HarvestPerformanceInterval(operation: operation, context: context) { [signposter] in
                signposter.endInterval("Douban Load", state)
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let categories = Self.metricCategories(in: payload.jsonRepresentation())
            let range = Self.dateRange(from: payload.timeStampBegin, to: payload.timeStampEnd)
            let categoryText = categories.isEmpty ? "系统性能数据" : categories.joined(separator: "、")
            recordAppLog(.info, "MetricKit 性能摘要：\(categoryText)；\(range)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let categories = Self.diagnosticCategories(in: payload.jsonRepresentation())
            let range = Self.dateRange(from: payload.timeStampBegin, to: payload.timeStampEnd)
            let categoryText = categories.isEmpty ? "系统诊断" : categories.joined(separator: "、")
            recordAppLog(.warning, "MetricKit 诊断摘要：\(categoryText)；\(range)")
        }
    }

    private static func metricCategories(in data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let keys = flattenedKeys(in: object)
        let definitions: [(String, [String])] = [
            ("CPU", ["cpumetric", "cputime"]),
            ("内存", ["memorymetric", "peakmemory"]),
            ("启动", ["launchmetric", "launchtime"]),
            ("卡顿", ["responsivenessmetric", "hangtime"]),
            ("磁盘 I/O", ["diskiometric"]),
            ("网络", ["networktransfermetric"]),
            ("自定义区间", ["signpostmetric"])
        ]
        return definitions.compactMap { label, needles in
            keys.contains(where: { key in
                needles.contains(where: { needle in key.contains(needle) })
            }) ? label : nil
        }
    }

    private static func diagnosticCategories(in data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries = flattenedCollections(in: object)
        let definitions: [(String, [String])] = [
            ("崩溃", ["crashdiagnostic"]),
            ("卡顿", ["hangdiagnostic"]),
            ("CPU 异常", ["cpuexceptiondiagnostic"]),
            ("磁盘写入异常", ["diskwriteexceptiondiagnostic"]),
            ("启动异常", ["launchdiagnostic"])
        ]
        return definitions.compactMap { label, needles in
            let count = entries.reduce(0) { partial, entry in
                needles.contains(where: { needle in entry.key.contains(needle) })
                    ? partial + entry.count
                    : partial
            }
            return count > 0 ? "\(label) \(count) 条" : nil
        }
    }

    private static func flattenedKeys(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                [normalizedKey(key)] + flattenedKeys(in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenedKeys)
        }
        return []
    }

    private static func flattenedCollections(in value: Any) -> [(key: String, count: Int)] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child -> [(key: String, count: Int)] in
                let ownCount = (child as? [Any])?.count ?? 0
                return [(normalizedKey(key), ownCount)] + flattenedCollections(in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenedCollections)
        }
        return []
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter }
    }

    private static func dateRange(from start: Date, to end: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "范围 \(formatter.string(from: start)) 至 \(formatter.string(from: end))"
    }
}
