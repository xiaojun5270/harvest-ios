import CryptoKit
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct NoticeItem: Identifiable, Hashable {
    let serverID: Int
    var title: String
    var content: String
    var category: String
    var createdAt: String
    var url: String
    var read: Bool
    var id: String {
        serverID > 0
            ? "server-\(serverID)"
            : "fallback-\(stableIdentifier(title, category, createdAt, url, content))"
    }

    init(_ json: [String: Any]) {
        serverID = json.int("id") ?? 0
        title = json.string("title", "subject", "name") ?? "系统消息"
        content = json.string("content", "message", "text", "body") ?? ""
        category = json.string("category", "type", "level") ?? "通知"
        createdAt = json.string("created_at", "create_time", "created", "updated_at", "update_time", "updated", "time", "date") ?? ""
        url = json.string("url", "link") ?? ""
        read = json.bool("is_read", "isRead", "read", "readed", "has_read") ?? (json.string("read_at", "readAt", "read_time", "readTime") != nil)
    }
}

struct NoticeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [NoticeItem] = []
    @State private var isLoading = true
    @State private var selectedNotice: NoticeItem?
    @State private var confirmDeleteAll = false
    @State private var cachedAt: Date?
    @State private var usingCachedData = false
    @State private var restoredCache = false
    private let sessionCacheKey = "notices.snapshot.v1"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { LoadingState() }
                else if notices.isEmpty { EmptyState(icon: "bell.slash", title: "没有消息", detail: "站点公告、任务结果和系统提醒会出现在这里") }
                else {
                    List {
                        if usingCachedData {
                            SessionCacheBanner(cachedAt: cachedAt)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                        ForEach(notices) { notice in
                            Button { selectedNotice = notice } label: { NoticeRow(item: notice) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    if !notice.read {
                                        Button { Task { await markRead(notice) } } label: { Label("已读", systemImage: "checkmark") }.tint(HarvestTheme.green)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { Task { await delete(notice) } } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("消息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !notices.isEmpty {
                        Menu {
                            if notices.contains(where: { !$0.read }) {
                                Button {
                                    Task {
                                        if await appState.perform(APIPath.noticesRead) {
                                            notices = notices.map {
                                                var item = $0
                                                item.read = true
                                                return item
                                            }
                                            appState.clearDeliveredNotices()
                                            await syncUnreadCount()
                                            await persistCache()
                                        }
                                    }
                                } label: { Label("全部已读", systemImage: "checkmark.circle") }
                            }
                            Button(role: .destructive) { confirmDeleteAll = true } label: { Label("删除全部", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("消息操作")
                    }
                }
            }
            .task { if isLoading { await load() } }
            .sheet(item: $selectedNotice) { notice in
                NoticeDetailSheet(
                    notice: notice,
                    onRead: { await markRead(notice) },
                    onDelete: { await delete(notice) }
                )
                .presentationDetents([.large])
            }
            .confirmationDialog("确定删除全部消息？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("删除全部", role: .destructive) { Task { await deleteAll() } }
            }
        }
    }

    private func load() async {
        if !restoredCache {
            restoredCache = true
            if let cached = await appState.readSessionCache(sessionCacheKey) {
                let restored = jsonRows(cached.value).map(NoticeItem.init)
                if !restored.isEmpty {
                    notices = restored
                    cachedAt = cached.cachedAt
                    usingCachedData = true
                    isLoading = false
                    await syncUnreadCount()
                }
            }
        }
        isLoading = notices.isEmpty
        defer { isLoading = false }
        do {
            notices = jsonRows(try await appState.api(APIPath.notices)).map(NoticeItem.init)
            usingCachedData = false
            cachedAt = nil
            await persistCache()
            await syncUnreadCount()
        }
        catch {
            if notices.isEmpty { appState.presentedError = error.localizedDescription }
            else { recordAppLog(.warning, "消息刷新失败，继续显示缓存：\(error.localizedDescription)") }
        }
    }

    private func markRead(_ notice: NoticeItem) async -> Bool {
        guard notice.serverID > 0 else { return false }
        if await appState.perform("\(APIPath.notices)/\(notice.serverID)/read", method: .put) {
            if let index = notices.firstIndex(where: { $0.serverID == notice.serverID }) { notices[index].read = true }
            appState.clearDeliveredNotice(id: notice.serverID)
            await syncUnreadCount()
            await persistCache()
            return true
        }
        return false
    }

    private func delete(_ notice: NoticeItem) async -> Bool {
        guard notice.serverID > 0 else { return false }
        if await appState.perform("\(APIPath.notices)/\(notice.serverID)", method: .delete) {
            notices.removeAll { $0.serverID == notice.serverID }
            appState.clearDeliveredNotice(id: notice.serverID)
            await syncUnreadCount()
            await persistCache()
            return true
        }
        return false
    }

    private func deleteAll() async {
        if await appState.perform(APIPath.notices, method: .delete) {
            notices = []
            appState.clearDeliveredNotices()
            await syncUnreadCount()
            await appState.removeSessionCache(sessionCacheKey)
        }
    }

    private func persistCache() async {
        let rows: [[String: Any]] = notices.map { notice in
            [
                "id": notice.serverID,
                "title": notice.title,
                "category": notice.category,
                "created_at": notice.createdAt,
                "url": notice.url,
                "is_read": notice.read
            ]
        }
        if rows.isEmpty { await appState.removeSessionCache(sessionCacheKey) }
        else { await appState.writeSessionCache(rows, name: sessionCacheKey) }
    }

    private func syncUnreadCount() async {
        await appState.updateUnreadNoticeCount(notices.lazy.filter { !$0.read }.count)
    }
}

struct NoticeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notice: NoticeItem
    let onRead: () async -> Bool
    let onDelete: () async -> Bool
    @State private var isRead: Bool
    @State private var confirmDelete = false

    init(notice: NoticeItem, onRead: @escaping () async -> Bool, onDelete: @escaping () async -> Bool) {
        self.notice = notice
        self.onRead = onRead
        self.onDelete = onDelete
        _isRead = State(initialValue: notice.read)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    noticeHeader

                    if let report = noticeDailyDataReport(notice.content) {
                        NoticeDailyDataReportView(report: report)
                    } else if let report = noticeTaskReport(notice.content) {
                        NoticeTaskReportView(report: report)
                    } else {
                        noticeContent
                    }

                    if let url = URL(string: notice.url), !notice.url.isEmpty {
                        NavigationLink {
                            NativeBrowserView(urlString: url.absoluteString, title: notice.title)
                                .navigationTitle(notice.title)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "safari.fill")
                                    .foregroundStyle(HarvestTheme.blue)
                                Text("打开相关链接")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.primary)
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("消息详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    if !isRead {
                        Button {
                            Task {
                                if await onRead() { isRead = true }
                            }
                        } label: {
                            Label("标记已读", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(HarvestTheme.blue)
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除消息", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(HarvestTheme.coral)
                }
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .confirmationDialog("确定删除这条消息？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除消息", role: .destructive) { Task { if await onDelete() { dismiss() } } }
            }
        }
    }

    private var noticeHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isRead ? "bell" : "bell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isRead ? Color.secondary : HarvestTheme.coral)
                .frame(width: 34, height: 34)
                .background(
                    (isRead ? Color.secondary : HarvestTheme.coral).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    Text(notice.category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HarvestTheme.blue)
                    Label(notice.createdAt, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var noticeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("消息内容", systemImage: "text.alignleft")
                .font(.headline)
            Text(markdownAttributedString(formattedNoticeContent(notice.content)))
                .font(.body)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NoticeTaskReport {
    let siteCount: String
    let duration: String
    let successCount: String
    let failureCount: String
    let failures: [String]
    let successes: [String]
}

private struct NoticeTaskReportView: View {
    let report: NoticeTaskReport
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 7) {
                metric("站点", report.siteCount, icon: "globe", color: HarvestTheme.blue)
                metric("成功", report.successCount, icon: "checkmark.circle.fill", color: HarvestTheme.green)
                metric("失败", report.failureCount, icon: "xmark.circle.fill", color: HarvestTheme.coral)
                metric("耗时", report.duration, icon: "timer", color: HarvestTheme.amber)
            }

            if !report.failures.isEmpty {
                NoticeResultGroup(
                    title: "失败站点",
                    entries: report.failures,
                    icon: "xmark.circle.fill",
                    color: HarvestTheme.coral
                )
            }

            if !report.successes.isEmpty {
                NoticeResultGroup(
                    title: "成功站点",
                    entries: report.successes,
                    icon: "checkmark.circle.fill",
                    color: HarvestTheme.green
                )
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 8)
        .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct NoticeDailyDataEntry: Identifiable {
    let site: String
    let direction: String
    let amount: String
    var id: String { "\(site)|\(direction)|\(amount)" }
}

private struct NoticeDailyDataReport {
    let totalUpload: String
    let totalDownload: String
    let entries: [NoticeDailyDataEntry]
}

private struct NoticeDailyDataReportView: View {
    let report: NoticeDailyDataReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                trafficMetric(
                    title: "总上传",
                    value: report.totalUpload,
                    icon: "arrow.up",
                    color: HarvestTheme.green
                )
                trafficMetric(
                    title: "总下载",
                    value: report.totalDownload,
                    icon: "arrow.down",
                    color: HarvestTheme.blue
                )
            }

            if !report.entries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("站点数据")
                        Spacer()
                        Text("\(report.entries.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HarvestTheme.blue)
                    .padding(.bottom, 8)

                    ForEach(Array(report.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.direction == "下载" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(entry.direction == "下载" ? HarvestTheme.blue : HarvestTheme.green)
                            Text(entry.site)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(entry.amount)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text(entry.direction)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 9)
                        if index < report.entries.count - 1 {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(HarvestTheme.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HarvestTheme.blue.opacity(0.12), lineWidth: 0.8)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func trafficMetric(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "-" : value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 10)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct NoticeResultGroup: View {
    let title: String
    let entries: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.bottom, 8)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                let parts = noticeResultParts(entry)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(parts.title)
                            .font(.subheadline.weight(.semibold))
                        if !parts.detail.isEmpty {
                            Text(parts.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 9)
                if index < entries.count - 1 {
                    Divider().padding(.leading, 23)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 0.8)
        }
    }
}

private func noticeDailyDataReport(_ rawContent: String) -> NoticeDailyDataReport? {
    let content = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
    guard content.contains("今日数据"),
          content.contains("总上传") || content.contains("总下载") else { return nil }

    let listContent: String
    if let marker = content.range(of: "数据列表") {
        listContent = String(content[marker.upperBound...])
    } else {
        listContent = content
    }

    let pattern = "([^:：]+?)\\s*[:：]\\s*(上传|下载)\\s*([0-9]+(?:\\.[0-9]+)?\\s*(?:[KMGTPE]?i?B|B))"
    let entries = noticeReportMatches(pattern, in: listContent).compactMap { values -> NoticeDailyDataEntry? in
        guard values.count == 3 else { return nil }
        let site = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let direction = values[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = values[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty, !amount.isEmpty else { return nil }
        return NoticeDailyDataEntry(site: site, direction: direction, amount: amount)
    }

    return NoticeDailyDataReport(
        totalUpload: noticeReportCapture("总上传\\s*[:：]\\s*([0-9]+(?:\\.[0-9]+)?\\s*(?:[KMGTPE]?i?B|B))", in: content),
        totalDownload: noticeReportCapture("总下载\\s*[:：]\\s*([0-9]+(?:\\.[0-9]+)?\\s*(?:[KMGTPE]?i?B|B))", in: content),
        entries: entries
    )
}

private func noticeTaskReport(_ rawContent: String) -> NoticeTaskReport? {
    let content = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
    guard content.contains("失败站点") || content.contains("成功站点") else { return nil }

    let failureRange = content.range(of: "失败站点")
    let successRange = content.range(of: "成功站点")
    let sectionStarts = [failureRange?.lowerBound, successRange?.lowerBound].compactMap { $0 }
    let summaryEnd = sectionStarts.min() ?? content.endIndex
    let summary = String(content[..<summaryEnd])

    let failures = noticeReportEntries(
        noticeReportSection(content, marker: failureRange, nextMarker: successRange)
    )
    let successes = noticeReportEntries(
        noticeReportSection(content, marker: successRange, nextMarker: failureRange)
    )

    return NoticeTaskReport(
        siteCount: noticeReportCapture("站点数\\s*[:：]\\s*(\\d+)", in: summary),
        duration: noticeReportCapture("耗时\\s*[:：]\\s*([0-9.]+\\s*秒)", in: summary),
        successCount: noticeReportCapture("成功\\s*[:：]\\s*(\\d+)", in: summary),
        failureCount: noticeReportCapture("失败\\s*[:：]\\s*(\\d+)", in: summary),
        failures: failures,
        successes: successes
    )
}

private func noticeReportSection(
    _ content: String,
    marker: Range<String.Index>?,
    nextMarker: Range<String.Index>?
) -> String {
    guard let marker else { return "" }
    let end: String.Index
    if let nextMarker, nextMarker.lowerBound > marker.upperBound {
        end = nextMarker.lowerBound
    } else {
        end = content.endIndex
    }
    return String(content[marker.upperBound..<end])
}

private func noticeReportEntries(_ rawSection: String) -> [String] {
    let separators = ["🥀", "🌹", "🌷", "🌸", "🌺", "💐"]
    let trimCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    var separated = separators.reduce(rawSection) {
        $0.replacingOccurrences(of: $1, with: "\n")
    }
    separated = noticeReplacingMatches(
        "([A-Za-z0-9\\p{Han}_·-]+(?:\\s+[A-Za-z0-9\\p{Han}_·-]+)?)\\s*[:：]?\\s*(解析站点信息失败|获取站点信息失败|获取站点信息成功|签到失败|签到成功|已签到|未开启或不支持签到)",
        in: separated,
        template: "\n$1 $2"
    )
    separated = noticeReplacingMatches(
        "([（(]已重试\\s*\\d+\\s*次[）)])",
        in: separated,
        template: "$1\n"
    )
    separated = noticeReplacingMatches(
        "(耗时\\s*[:：]?\\s*[0-9]+(?:\\.[0-9]+)?\\s*秒)",
        in: separated,
        template: "$1\n"
    )
    return separated
        .components(separatedBy: .newlines)
        .map {
            $0.trimmingCharacters(in: trimCharacters)
        }
        .filter { !$0.isEmpty }
}

private func noticeResultParts(_ entry: String) -> (title: String, detail: String) {
    let titleTrimCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let resultMarkers = [
        "解析站点信息失败", "获取站点信息失败", "获取站点信息成功",
        "签到失败", "签到成功", "已签到", "未开启或不支持签到"
    ]
    for marker in resultMarkers {
        guard let markerRange = entry.range(of: marker) else { continue }
        let title = String(entry[..<markerRange.lowerBound])
            .trimmingCharacters(in: titleTrimCharacters)
        let detail = String(entry[markerRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return (title, detail) }
    }
    guard let separator = entry.firstIndex(where: { $0.isWhitespace }) else {
        return (entry, "")
    }
    let title = String(entry[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = String(entry[separator...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? (entry, "") : (title, detail)
}

private func noticeReportCapture(_ pattern: String, in text: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
              in: text,
              range: NSRange(text.startIndex..., in: text)
          ),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return "" }
    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func noticeReportMatches(_ pattern: String, in text: String) -> [[String]] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
        guard match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index -> String? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private func noticeReplacingMatches(_ pattern: String, in text: String, template: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return text
    }
    return expression.stringByReplacingMatches(
        in: text,
        range: NSRange(text.startIndex..., in: text),
        withTemplate: template
    )
}

private func formattedNoticeContent(_ rawContent: String) -> String {
    let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return "暂无内容" }
    var formatted = ["🥀", "🌹", "🌷", "🌸", "🌺", "💐"].reduce(content) {
        $0.replacingOccurrences(of: $1, with: "\n\n")
    }
    formatted = noticeReplacingMatches(
        "(失败站点|成功站点|数据列表)",
        in: formatted,
        template: "\n\n$1\n"
    )
    formatted = noticeReplacingMatches(
        "([。！？])\\s*",
        in: formatted,
        template: "$1\n\n"
    )
    formatted = noticeReplacingMatches(
        "([（(]已重试\\s*\\d+\\s*次[）)])",
        in: formatted,
        template: "$1\n"
    )
    return noticeReplacingMatches("\\n{3,}", in: formatted, template: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct NoticeRow: View {
    let item: NoticeItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.read ? Color.secondary.opacity(0.10) : HarvestTheme.coral.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: item.read ? "bell" : "bell.fill")
                        .foregroundStyle(item.read ? .secondary : HarvestTheme.coral)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title).font(.subheadline.weight(item.read ? .regular : .semibold))
                    Spacer()
                    Text(item.category).font(.caption2).foregroundStyle(.secondary)
                }
                Text(markdownAttributedString(item.content, inlineOnly: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(item.createdAt).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLogout = false
    @State private var confirmingRestart = false
    @State private var showingInvite = false
    @State private var selectedBrandMarkItem: PhotosPickerItem?
    @State private var brandMarkStatus = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) {
                        BrandMark(size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(privacyMaskedText(appState.profile?.username ?? "Harvest 用户", enabled: appState.privacyMode)).font(.headline)
                            Text(appState.profile?.email.isEmpty == false
                                ? privacyMaskedText(appState.profile!.email, enabled: appState.privacyMode)
                                : appState.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }.padding(.vertical, 5)
                }

                Section("品牌图标") {
                    HStack(spacing: 14) {
                        BrandMark(size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BrandMarkStore.hasCustomImage ? "自定义图标" : "默认黄金图标")
                                .font(.subheadline.weight(.semibold))
                            Text("用于页面左上角、登录页和应用内启动页")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    PhotosPicker(selection: $selectedBrandMarkItem, matching: .images) {
                        Label("选择自定义图标", systemImage: "photo.badge.plus")
                    }
                    if BrandMarkStore.hasCustomImage {
                        Button(role: .destructive) {
                            BrandMarkStore.restoreDefault()
                            brandMarkStatus = "已恢复默认黄金图标"
                        } label: {
                            Label("恢复默认图标", systemImage: "arrow.counterclockwise")
                        }
                    }
                    if !brandMarkStatus.isEmpty {
                        Text(brandMarkStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("外观与隐私") {
                    Picker("显示模式", selection: Binding(get: { appState.appearance }, set: appState.setAppearance)) { ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("强调色", selection: Binding(get: { appState.accent }, set: appState.setAccent)) {
                        ForEach(AppAccent.allCases) { accent in
                            Label {
                                Text(accent.title)
                            } icon: {
                                Circle().fill(accent.color).frame(width: 12, height: 12)
                            }
                            .tag(accent)
                        }
                    }
                    Picker("界面密度", selection: Binding(get: { appState.interfaceDensity }, set: appState.setInterfaceDensity)) {
                        ForEach(AppInterfaceDensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("界面字号", selection: Binding(get: { appState.interfaceScale }, set: appState.setInterfaceScale)) {
                        ForEach(AppInterfaceScale.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle(isOn: Binding(get: { appState.privacyMode }, set: appState.setPrivacyMode)) {
                        Label("隐藏站点名称、用户名和邮箱", systemImage: "eye.slash")
                    }
                    Button { appState.resetAppearanceSettings() } label: {
                        Label("恢复默认外观", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("账号") {
                    NavigationLink {
                        AccountSwitcherView().environmentObject(appState)
                    } label: {
                        Label("切换账号", systemImage: "person.2.circle")
                    }
                    if appState.profile?.isSuperuser == true {
                        Button { showingInvite = true } label: {
                            Label("邀请用户", systemImage: "envelope.badge.person.crop")
                        }
                    }
                }

                Section("资讯页内容") {
                    Toggle("显示 TMDB", isOn: Binding(get: { appState.mediaTMDBEnabled }, set: appState.setMediaTMDBEnabled))
                    Toggle("显示豆瓣", isOn: Binding(get: { appState.mediaDoubanEnabled }, set: appState.setMediaDoubanEnabled))
                }

                Section("自动刷新") {
                    Stepper(
                        value: Binding(get: { appState.autoRefreshMinutes }, set: appState.setAutoRefreshMinutes),
                        in: 1...1_440
                    ) {
                        LabeledContent("刷新间隔", value: "\(appState.autoRefreshMinutes) 分钟")
                    }
                    Menu("常用间隔") {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Button("\(minutes) 分钟") { appState.setAutoRefreshMinutes(minutes) }
                        }
                    }
                }

                Section("管理") {
                    if appState.profile?.isSuperuser == true {
                        NavigationLink { TasksView().environmentObject(appState) } label: {
                            Label("任务中心", systemImage: "checklist")
                        }
                    }
                    NavigationLink { BackendOptionsView().environmentObject(appState) } label: { Label("后端配置", systemImage: "slider.horizontal.3") }
                    NavigationLink { NotificationToolsView().environmentObject(appState) } label: { Label("通知与机器人", systemImage: "bell.and.waves.left.and.right") }
                    NavigationLink { UserManagementView().environmentObject(appState) } label: { Label("用户中心", systemImage: "person.2") }
                    if appState.profile?.isSuperuser == true && appState.canOpenAdminUsers {
                        NavigationLink { AdminView().environmentObject(appState) } label: { Label("授权管理", systemImage: "person.badge.key") }
                    }
                    NavigationLink { LogView().environmentObject(appState) } label: { Label("日志中心", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink {
                        NativeBrowserView(urlString: appState.baseURL, title: "服务页面")
                            .navigationTitle("服务页面")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: { Label("服务页面", systemImage: "safari") }
                }

                Section("维护") {
                    NavigationLink { DataMaintenanceView().environmentObject(appState) } label: { Label("备份与迁移", systemImage: "externaldrive.badge.timemachine") }
                    NavigationLink { UpdateMaintenanceView().environmentObject(appState) } label: { Label("更新与网络", systemImage: "arrow.triangle.2.circlepath") }
                    Button { Task { _ = await appState.perform(APIPath.cacheClear, method: .get); } } label: { Label("清理站点缓存", systemImage: "trash.slash") }
                    Button { Task { _ = await appState.perform(APIPath.notifyTest, method: .get, query: ["title": "Harvest", "content": "原生客户端通知测试", "push_type": ""]); } } label: { Label("发送测试通知", systemImage: "bell.badge") }
                    if appState.profile?.isSuperuser == true { Button(role: .destructive) { confirmingRestart = true } label: { Label("重启服务", systemImage: "arrow.clockwise.circle") } }
                }

                Section("关于") {
                    LabeledContent("客户端", value: "iOS 原生版")
                    LabeledContent("版本", value: appVersionLabel)
                    LabeledContent("系统要求", value: "iOS 17+")
                }

                Section { Button(role: .destructive) { confirmingLogout = true } label: { Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity) } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showingInvite) {
                InviteSheet(notify: true) { }
                    .environmentObject(appState)
            }
            .onChange(of: selectedBrandMarkItem) { _, item in
                guard let item else { return }
                Task { await importBrandMark(item) }
            }
            .confirmationDialog("确定退出当前账号？", isPresented: $confirmingLogout, titleVisibility: .visible) { Button("退出登录", role: .destructive) { dismiss(); appState.logout() } }
            .confirmationDialog("确定重启 Harvest 服务？", isPresented: $confirmingRestart, titleVisibility: .visible) { Button("重启服务", role: .destructive) { Task { _ = await appState.perform(APIPath.serverRestart, method: .get) } } }
        }
    }

    @MainActor
    private func importBrandMark(_ item: PhotosPickerItem) async {
        defer { selectedBrandMarkItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), BrandMarkStore.save(data) else {
                brandMarkStatus = "图片无效或文件过大，请重新选择"
                return
            }
            brandMarkStatus = "自定义图标已应用"
        } catch {
            brandMarkStatus = "读取图片失败：\(error.localizedDescription)"
        }
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "--"
        let build = (info["CFBundleVersion"] as? String) ?? "--"
        return "\(version) (\(build))"
    }
}

private struct NoticeChannel: Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct NotificationToolsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var title = "Harvest"
    @State private var content = "原生客户端通知测试"
    @State private var channel = ""
    @State private var telegramHost = ""
    @State private var qrURL = ""
    @State private var qrStatus = ""
    @State private var tokenSiteURL = "https://www.invites.fun"
    @State private var tokenUsername = ""
    @State private var tokenPassword = ""
    @State private var fetchedToken = ""
    @State private var fetchedUID = ""
    @State private var tokenStatus = ""
    @State private var confirmTokenUpdate = false
    @State private var isWorking = false
    @State private var pollingTask: Task<Void, Never>?

    private let channels = [
        NoticeChannel(value: "", label: "默认通道"),
        NoticeChannel(value: "wechat_work_push", label: "企业微信"),
        NoticeChannel(value: "wechat_bot_push", label: "微信机器人"),
        NoticeChannel(value: "wxpusher_push", label: "WxPusher"),
        NoticeChannel(value: "pushdeer_push", label: "PushDeer"),
        NoticeChannel(value: "server_chan_push", label: "Server 酱"),
        NoticeChannel(value: "bark_push", label: "Bark"),
        NoticeChannel(value: "iyuu_push", label: "爱语飞飞"),
        NoticeChannel(value: "telegram_push", label: "Telegram"),
        NoticeChannel(value: "qqbot_push", label: "QQ 机器人"),
        NoticeChannel(value: "pushplus_push", label: "PushPlus"),
        NoticeChannel(value: "meow_push", label: "喵呜通知")
    ]

    var body: some View {
        Form {
            Section("通知测试") {
                Picker("通知通道", selection: $channel) { ForEach(channels) { Text($0.label).tag($0.value) } }
                TextField("标题", text: $title)
                TextField("内容", text: $content, axis: .vertical).lineLimit(2...5)
                Button { Task { await sendTest() } } label: { Label("发送测试通知", systemImage: "paperplane") }
                    .disabled(title.isEmpty || content.isEmpty || isWorking)
            }
            Section("Telegram Webhook") {
                TextField("外网回调地址", text: $telegramHost).textInputAutocapitalization(.never).keyboardType(.URL)
                Button { Task { await saveWebhook() } } label: { Label("设置 Webhook", systemImage: "link.badge.plus") }
                    .disabled(telegramHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
            Section("药丸 / 蜂巢 Token") {
                Picker("站点", selection: $tokenSiteURL) {
                    Text("药丸").tag("https://www.invites.fun")
                    Text("蜂巢").tag("https://pting.club")
                }
                TextField("站点用户名", text: $tokenUsername).textInputAutocapitalization(.never)
                SecureField("站点密码", text: $tokenPassword)
                Button { Task { await fetchInviteToken() } } label: {
                    Label("获取 Token", systemImage: "key.horizontal")
                }
                .disabled(tokenUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tokenPassword.isEmpty || isWorking)
                if !fetchedToken.isEmpty {
                    tokenValueRow("Token", value: fetchedToken)
                    Button { confirmTokenUpdate = true } label: {
                        Label("写入匹配站点", systemImage: "square.and.arrow.down")
                    }
                }
                if !fetchedUID.isEmpty { tokenValueRow("UID", value: fetchedUID) }
                if !tokenStatus.isEmpty { Text(tokenStatus).font(.caption).foregroundStyle(.secondary) }
            }
            Section("微信机器人登录") {
                if !qrURL.isEmpty, ["wait", "scaned"].contains(qrStatus) {
                    NativeBrowserView(urlString: qrURL, title: "微信机器人登录")
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
                }
                if !qrStatus.isEmpty {
                    Label(qrStatusText, systemImage: qrStatus == "confirmed" ? "checkmark.circle.fill" : qrStatus == "expired" ? "clock" : "qrcode.viewfinder")
                        .foregroundStyle(qrStatus == "confirmed" ? HarvestTheme.green : qrStatus == "expired" ? HarvestTheme.amber : .secondary)
                }
                Button { Task { await fetchQRCode() } } label: { Label(qrURL.isEmpty ? "获取二维码" : "刷新二维码", systemImage: "qrcode") }
                    .disabled(isWorking)
            }
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .navigationTitle("通知与机器人")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { pollingTask?.cancel() }
        .confirmationDialog("将 Token 写入匹配的站点配置？", isPresented: $confirmTokenUpdate, titleVisibility: .visible) {
            Button("更新站点") { Task { await updateMatchingSites() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将更新 authkey\(fetchedUID.isEmpty ? "" : " 和 UID")。")
        }
    }

    @ViewBuilder private func tokenValueRow(_ label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
            }
            Spacer()
            Button {
                copyPrivateText(value)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制 \(label)")
        }
    }

    private var qrStatusText: String {
        switch qrStatus {
        case "wait": "等待扫码"
        case "scaned": "已扫码，请在手机上确认"
        case "confirmed": "登录成功"
        case "expired": "二维码已过期"
        default: qrStatus
        }
    }

    @MainActor private func sendTest() async {
        isWorking = true
        defer { isWorking = false }
        _ = await appState.perform(APIPath.notifyTest, method: .get, query: ["title": title, "content": content, "push_type": channel])
    }

    @MainActor private func saveWebhook() async {
        isWorking = true
        defer { isWorking = false }
        _ = await appState.perform(APIPath.telegramWebhook, body: ["host": telegramHost.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    @MainActor private func fetchInviteToken() async {
        isWorking = true
        fetchedToken = ""
        fetchedUID = ""
        tokenStatus = ""
        defer { isWorking = false }
        do {
            let raw = try await APIClient.shared.request(
                baseURL: tokenSiteURL,
                path: "/api/token",
                method: .post,
                body: [
                    "identification": tokenUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": tokenPassword,
                    "remember": 1
                ]
            )
            fetchedToken = nestedString(raw, keys: ["token", "access_token", "api_token"]) ?? ""
            fetchedUID = nestedString(raw, keys: ["uid", "userid", "user_id", "id"]) ?? ""
            guard !fetchedToken.isEmpty || !fetchedUID.isEmpty else {
                throw APIError(statusCode: 0, message: "请求成功，但未识别到 Token 或 UID")
            }
            tokenStatus = "Token 获取成功"
            if !fetchedToken.isEmpty { confirmTokenUpdate = true }
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func updateMatchingSites() async {
        guard !fetchedToken.isEmpty,
              let rawHost = URL(string: tokenSiteURL)?.host?.lowercased() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let sites = jsonRows(try await appState.api(APIPath.sites)).map(SiteItem.init)
            let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
            let matches = sites.filter { site in
                let values = [site.siteKey, site.url, site.torrentsURL, site.rss].map { $0.lowercased() }
                return values.contains { $0.contains(rawHost) || $0.contains(host) }
            }
            guard !matches.isEmpty else {
                tokenStatus = "未找到匹配站点，Token 已保留供复制"
                return
            }
            var updated = 0
            for site in matches {
                var body = site.raw
                body["authkey"] = fetchedToken
                if !fetchedUID.isEmpty { body["user_id"] = fetchedUID }
                if await appState.perform("\(APIPath.sites)/\(site.id)", method: .put, body: body) { updated += 1 }
            }
            tokenStatus = "已更新 \(updated) 个站点"
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    private func nestedString(_ value: Any, keys: Set<String>) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary where keys.contains(key.lowercased()) {
                if let text = nested as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                if let number = nested as? NSNumber { return number.stringValue }
            }
            for nested in dictionary.values {
                if let found = nestedString(nested, keys: keys) { return found }
            }
        } else if let values = value as? [Any] {
            for nested in values {
                if let found = nestedString(nested, keys: keys) { return found }
            }
        }
        return nil
    }

    @MainActor private func fetchQRCode() async {
        pollingTask?.cancel()
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await appState.api(APIPath.wechatQRCode)
            guard let url = (jsonPayloadDictionary(raw) ?? [:]).string("qrcode_url", "qrcodeUrl", "url"), !url.isEmpty else {
                throw APIError(statusCode: 0, message: "二维码响应缺少地址")
            }
            qrURL = url
            qrStatus = "wait"
            pollingTask = Task { await pollQRCodeStatus() }
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func pollQRCodeStatus() async {
        var lastErrorMessage = ""
        for _ in 0..<40 where !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            do {
                let status = jsonPayloadDictionary(try await appState.api(APIPath.wechatQRCodeStatus)) ?? [:]
                qrStatus = status.string("status") ?? qrStatus
                if ["confirmed", "expired"].contains(qrStatus) { return }
                lastErrorMessage = ""
            } catch {
                let message = error.localizedDescription
                if message != lastErrorMessage {
                    recordAppLog(.warning, "微信二维码状态轮询失败：\(message)")
                    lastErrorMessage = message
                }
            }
        }
        if !Task.isCancelled { qrStatus = "expired" }
    }
}

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .archive, .data] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private enum MaintenanceImport: String {
    case backup
    case sqlite
}

private struct PendingMaintenanceImport: Identifiable {
    let id = UUID()
    let kind: MaintenanceImport
    let fileName: String
    let data: Data
}

struct DataMaintenanceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var exportDocument: BackupDocument?
    @State private var exportFileName = "harvest_backup.zip"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importKind: MaintenanceImport = .backup
    @State private var legacyURL = ""
    @State private var legacyToken = ""
    @State private var isWorking = false
    @State private var confirmClean = false
    @State private var pendingImport: PendingMaintenanceImport?
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("完整备份") {
                Button { Task { await exportBackup() } } label: { Label("导出完整备份", systemImage: "square.and.arrow.up") }
                    .disabled(isWorking)
                Button { importKind = .backup; showImporter = true } label: { Label("恢复完整备份", systemImage: "square.and.arrow.down") }
                    .disabled(isWorking)
            }
            Section("旧版 Harvest") {
                TextField("旧服务器地址", text: $legacyURL).textInputAutocapitalization(.never).keyboardType(.URL)
                SecureField("旧版令牌", text: $legacyToken)
                Button { Task { await importLegacyServer() } } label: { Label("从旧服务导入", systemImage: "server.rack") }
                    .disabled(legacyURL.isEmpty || legacyToken.isEmpty || isWorking)
            }
            Section("旧版 SQLite") {
                Button { importKind = .sqlite; showImporter = true } label: { Label("选择数据库文件", systemImage: "cylinder.split.1x2") }
                    .disabled(isWorking)
            }
            Section("本机数据") {
                Button(role: .destructive) { confirmClean = true } label: { Label("清理网页缓存和 Cookie", systemImage: "trash") }
            }
            if !statusMessage.isEmpty {
                Section("结果") { Text(statusMessage).font(.caption).textSelection(.enabled) }
            }
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .navigationTitle("备份与迁移")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result { appState.presentedError = error.localizedDescription }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importKind == .backup ? [.zip] : [UTType(filenameExtension: "sqlite3") ?? .data], allowsMultipleSelection: false) { result in
            Task { await importFile(result) }
        }
        .confirmationDialog("确定清理内置浏览器缓存和 Cookie？", isPresented: $confirmClean, titleVisibility: .visible) {
            Button("清理", role: .destructive) { Task { await cleanWebData() } }
        }
        .confirmationDialog(
            "确定导入旧版数据库「\(pendingImport?.fileName ?? "")」？",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认导入") {
                guard let file = pendingImport else { return }
                pendingImport = nil
                Task { await submitImport(file) }
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        }
    }

    @MainActor private func exportBackup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await appState.download(APIPath.setupBackup)
            exportDocument = BackupDocument(data: result.data)
            exportFileName = normalizedBackupName(result.fileName)
            showExporter = true
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func importFile(_ result: Result<[URL], Error>) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let extensionName = url.pathExtension.lowercased()
            if importKind == .backup, extensionName != "zip" {
                throw APIError(statusCode: 0, message: "请选择 .zip 完整备份文件")
            }
            if importKind == .sqlite, extensionName != "sqlite3" {
                throw APIError(statusCode: 0, message: "请选择 .sqlite3 旧版数据库文件")
            }
            let file = PendingMaintenanceImport(kind: importKind, fileName: url.lastPathComponent, data: data)
            if importKind == .sqlite {
                pendingImport = file
            } else {
                await submitImport(file)
            }
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func submitImport(_ file: PendingMaintenanceImport) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let path = file.kind == .backup ? APIPath.setupBackup : APIPath.setupSQLite
            let raw = try await appState.upload(
                path,
                parts: [MultipartPart(fieldName: "file", fileName: file.fileName, mimeType: "application/octet-stream", data: file.data)]
            )
            statusMessage = jsonMessage(raw) ?? (file.kind == .backup ? "数据备份导入任务已提交" : "旧版数据库导入任务已提交")
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func importLegacyServer() async {
        isWorking = true
        defer { isWorking = false }
        _ = await appState.perform(APIPath.setupImport, body: ["base_url": legacyURL.trimmingCharacters(in: .whitespacesAndNewlines), "legacy_token": legacyToken])
    }

    @MainActor private func cleanWebData() async {
        URLCache.shared.removeAllCachedResponses()
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, modifiedSince: .distantPast) { continuation.resume() }
        }
        statusMessage = "内置浏览器缓存和 Cookie 已清理"
    }

    private func normalizedBackupName(_ value: String?) -> String {
        let name = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.lowercased().hasSuffix(".zip") { return name }
        if name.lowercased().hasSuffix(".gz") { return String(name.dropLast(3)) + ".zip" }
        if !name.isEmpty { return name + ".zip" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "harvest_backup_\(formatter.string(from: Date())).zip"
    }
}

struct IOSDownloadLink: Identifiable, Hashable {
    let label: String
    let url: URL
    let sha256: String?
    var id: String { url.absoluteString }
}

private let appUpdateServiceURL = "https://repeat.ptools.fun"
private let appUpdateDownloadPageURL = URL(string: appUpdateServiceURL)!
private let appUpdateTestFlightURL = URL(string: "https://testflight.apple.com/join/kwLil5xf")!
private let appUpdateIgnoredVersionKey = "app_upgrade_ignore_version"
private let appUpdateUseGithubProxyKey = "app_upgrade_use_github_proxy"
private let appUpdateGithubProxyKey = "app_upgrade_github_proxy"
private let appUpdateGithubProxyResultsKey = "app_upgrade_github_proxy_results"
private let appUpdateGithubProxyCandidates = [
    "https://gh-proxy.net/",
    "https://github.cnxiaobai.com/",
    "https://hub.gitmirror.com/",
    "https://www.5555.cab/",
    "https://ghproxy.xiaopa.cc/",
    "https://ghproxy.cfd/",
    "https://ghproxy.cc/",
    "https://ghproxy.monkeyray.net/",
    "https://cf.ghproxy.cc/",
    "https://gitproxy.mrhjx.cn/",
    "https://ghproxy.1888866.xyz/",
    "https://github.mlmle.cn/",
    "https://fastgit.cc/",
    "https://gh.1k.ink/",
    "https://ghproxy.net/",
    "https://github.boringhex.top/",
    "https://ghfast.top/",
    "https://ghproxy.imciel.com/",
    "https://gh.monlor.com/",
    "https://gh.con.sh/"
]

struct GithubProxyResult: Codable, Identifiable, Hashable {
    let url: String
    let milliseconds: Int
    let statusCode: Int
    var id: String { url }
    var isAvailable: Bool { (200..<500).contains(statusCode) }
}

struct DownloadedAppPackage: Identifiable {
    let url: URL
    var id: String { url.path }
}

private final class AppUpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let expectedSHA256: String?
    private let progress: (Int64, Int64) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var result: Result<URL, Error>?

    init(
        destination: URL,
        expectedSHA256: String?,
        progress: @escaping (Int64, Int64) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.destination = destination
        self.expectedSHA256 = expectedSHA256
        self.progress = progress
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            result = .failure(APIError(statusCode: response.statusCode, message: "下载安装包失败（\(response.statusCode)）"))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            guard try isZIPArchive(destination) else {
                try? FileManager.default.removeItem(at: destination)
                result = .failure(APIError(statusCode: 0, message: "安装包格式无效"))
                return
            }
            if let expectedSHA256 {
                let actualSHA256 = try fileSHA256(destination)
                guard actualSHA256 == expectedSHA256 else {
                    try? FileManager.default.removeItem(at: destination)
                    result = .failure(APIError(statusCode: 0, message: "安装包 SHA-256 校验失败"))
                    return
                }
            }
            result = .success(destination)
        } catch {
            result = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let finalResult: Result<URL, Error>
        if let error {
            finalResult = .failure(error)
        } else {
            finalResult = result ?? .failure(APIError(statusCode: 0, message: "下载安装包失败"))
        }
        DispatchQueue.main.async { [completion] in completion(finalResult) }
    }
}

@MainActor
final class AppUpdateViewModel: ObservableObject {
    @Published var latest: [String: Any] = [:]
    @Published var versions: [[String: Any]] = []
    @Published var isLoading = false
    @Published var isTestingProxy = false
    @Published var isDownloading = false
    @Published var downloadProgress = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var expectedDownloadBytes: Int64 = 0
    @Published var completedPackage: DownloadedAppPackage?
    @Published var statusMessage = ""
    @Published var errorMessage = ""
    @Published var proxyResults: [GithubProxyResult]
    @Published var useGithubProxy: Bool {
        didSet { UserDefaults.standard.set(useGithubProxy, forKey: appUpdateUseGithubProxyKey) }
    }
    @Published var selectedProxy: String {
        didSet { UserDefaults.standard.set(selectedProxy, forKey: appUpdateGithubProxyKey) }
    }

    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: AppUpdateDownloadDelegate?
    private var cancelRequested = false

    init() {
        let defaults = UserDefaults.standard
        useGithubProxy = defaults.bool(forKey: appUpdateUseGithubProxyKey)
        selectedProxy = defaults.string(forKey: appUpdateGithubProxyKey) ?? ""
        if let data = defaults.data(forKey: appUpdateGithubProxyResultsKey),
           let stored = try? JSONDecoder().decode([GithubProxyResult].self, from: data) {
            proxyResults = stored.filter(\.isAvailable)
        } else {
            proxyResults = []
        }
    }

    deinit {
        downloadTask?.cancel()
        downloadSession?.invalidateAndCancel()
    }

    var currentVersion: String { appUpdateCurrentVersion() }
    var latestVersion: String { latest.string("version", "tag", "version_name", "name") ?? "" }
    var latestLinks: [IOSDownloadLink] { iosDownloadLinks(latest) }
    var hasNewVersion: Bool {
        !latestVersion.isEmpty && hasIOSAppPackage(latest) && compareAppVersions(latestVersion, currentVersion) > 0
    }
    var isLatestIgnored: Bool {
        isAppUpdateVersionIgnored(latestVersion)
    }

    func load(_ appState: AppState, includeHistory: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            latest = jsonPayloadDictionary(try await appUpdateRequest(APIPath.appVersionLatest, appState: appState)) ?? [:]
        } catch {
            errorMessage = "获取 APP 最新版本失败：\(error.localizedDescription)"
        }
        guard includeHistory else { return }
        do {
            versions = jsonRows(try await appUpdateRequest(APIPath.appVersionList, appState: appState))
        } catch {
            let message = "获取 APP 版本历史失败：\(error.localizedDescription)"
            errorMessage = errorMessage.isEmpty ? message : errorMessage + "\n" + message
        }
    }

    func setLatestIgnored(_ ignored: Bool) {
        guard !latestVersion.isEmpty else { return }
        setAppUpdateVersionIgnored(latestVersion, ignored: ignored)
        objectWillChange.send()
    }

    func testGithubProxies() async {
        guard !isTestingProxy else { return }
        isTestingProxy = true
        errorMessage = ""
        statusMessage = "正在测试 GitHub 加速地址"
        defer { isTestingProxy = false }

        let candidates = Array(appUpdateGithubProxyCandidates.shuffled().prefix(20))
        let tested = await withTaskGroup(of: GithubProxyResult.self, returning: [GithubProxyResult].self) { group in
            for proxy in candidates {
                group.addTask { await Self.probeGithubProxy(proxy) }
            }
            var values: [GithubProxyResult] = []
            for await value in group { values.append(value) }
            return values
        }
        let available = tested.filter(\.isAvailable).sorted { $0.milliseconds < $1.milliseconds }
        proxyResults = Array(available.prefix(10))
        if let data = try? JSONEncoder().encode(proxyResults) {
            UserDefaults.standard.set(data, forKey: appUpdateGithubProxyResultsKey)
        }
        if let fastest = proxyResults.first {
            selectedProxy = fastest.url
            statusMessage = "已选择最快加速地址，响应 \(fastest.milliseconds) ms"
        } else {
            selectedProxy = ""
            statusMessage = ""
            errorMessage = "未找到可用的 GitHub 加速地址"
        }
    }

    func copyDownloadURL(_ link: IOSDownloadLink) {
        copyPrivateText(effectiveURL(for: link, verifiedSHA256: link.sha256).absoluteString)
        statusMessage = "下载链接已复制"
    }

    func download(_ link: IOSDownloadLink, release: [String: Any]) async {
        guard !isDownloading else { return }
        downloadProgress = 0
        downloadedBytes = 0
        expectedDownloadBytes = 0
        completedPackage = nil
        cancelRequested = false
        errorMessage = ""
        statusMessage = "正在校验下载地址"
        isDownloading = true

        let expectedSHA256: String?
        if let providedSHA256 = link.sha256 {
            expectedSHA256 = providedSHA256
        } else {
            expectedSHA256 = await Self.fetchCompanionSHA256(for: link.url)
        }
        if cancelRequested || Task.isCancelled {
            finishCancelledPreparation()
            return
        }
        if expectedSHA256 == nil {
            recordAppLog(.warning, "APP 安装包未提供 SHA-256，将使用 HTTPS 直连并校验 ZIP 格式")
        }
        let sourceURL = effectiveURL(for: link, verifiedSHA256: expectedSHA256)
        let version = release.string("version", "tag", "version_name", "name") ?? latestVersion
        let fileName = appUpdateFileName(link: link, version: version)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("harvest_app_upgrade", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "无法创建安装包临时目录：\(error.localizedDescription)"
            isDownloading = false
            return
        }
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)

        statusMessage = "正在下载 \(fileName)"

        let delegate = AppUpdateDownloadDelegate(
            destination: destination,
            expectedSHA256: expectedSHA256,
            progress: { [weak self] received, expected in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.downloadedBytes = received
                    self.expectedDownloadBytes = max(0, expected)
                    self.downloadProgress = expected > 0 ? min(max(Double(received) / Double(expected), 0), 1) : 0
                }
            },
            completion: { [weak self] result in self?.finishDownload(result) }
        )
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: sourceURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        downloadDelegate = delegate
        downloadSession = session
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        guard isDownloading else { return }
        cancelRequested = true
        if let downloadTask { downloadTask.cancel() }
        else { statusMessage = "正在取消下载准备" }
    }

    private func effectiveURL(for link: IOSDownloadLink, verifiedSHA256: String?) -> URL {
        let original = link.url
        guard useGithubProxy,
              verifiedSHA256 != nil,
              !selectedProxy.isEmpty,
              isGithubDownloadURL(original),
              let proxyURL = URL(string: selectedProxy),
              proxyURL.scheme?.lowercased() == "https",
              proxyURL.host != nil else { return original }
        let normalized = selectedProxy.hasSuffix("/") ? selectedProxy : selectedProxy + "/"
        return URL(string: normalized + original.absoluteString) ?? original
    }

    private func finishCancelledPreparation() {
        isDownloading = false
        cancelRequested = false
        statusMessage = "已取消下载"
        downloadProgress = 0
        downloadedBytes = 0
        expectedDownloadBytes = 0
    }

    private func finishDownload(_ result: Result<URL, Error>) {
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        downloadTask = nil
        downloadDelegate = nil
        isDownloading = false
        downloadProgress = 0
        downloadedBytes = 0
        expectedDownloadBytes = 0

        switch result {
        case .success(let url):
            statusMessage = "安装包已下载，可通过系统分享保存或传输"
            completedPackage = DownloadedAppPackage(url: url)
        case .failure(let error):
            if cancelRequested || (error as NSError).code == NSURLErrorCancelled {
                statusMessage = "已取消下载"
            } else {
                statusMessage = ""
                errorMessage = "下载安装包失败：\(error.localizedDescription)"
            }
        }
        cancelRequested = false
    }

    nonisolated private static func probeGithubProxy(_ proxy: String) async -> GithubProxyResult {
        let normalized = proxy.hasSuffix("/") ? proxy : proxy + "/"
        guard let url = URL(string: normalized + "https://github.com/favicon.ico") else {
            return GithubProxyResult(url: normalized, milliseconds: 0, statusCode: 0)
        }
        let start = Date()
        var statusCode = 0
        do {
            var request = URLRequest(url: url, timeoutInterval: 1.8)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            do {
                var request = URLRequest(url: url, timeoutInterval: 1.8)
                request.httpMethod = "GET"
                let (_, response) = try await URLSession.shared.data(for: request)
                statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch { statusCode = 0 }
        }
        let milliseconds = max(1, Int(Date().timeIntervalSince(start) * 1_000))
        return GithubProxyResult(url: normalized, milliseconds: milliseconds, statusCode: statusCode)
    }

    nonisolated private static func fetchCompanionSHA256(for sourceURL: URL) async -> String? {
        guard sourceURL.scheme?.lowercased() == "https", isGithubDownloadURL(sourceURL),
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += ".sha256"
        guard let checksumURL = components.url else { return nil }
        do {
            var request = URLRequest(url: checksumURL, timeoutInterval: 10)
            request.setValue("text/plain", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return normalizedSHA256(text)
        } catch {
            return nil
        }
    }
}

@MainActor
func appUpdateRequest(_ path: String, appState: AppState) async throws -> Any {
    do {
        return try await APIClient.shared.request(baseURL: appUpdateServiceURL, path: path)
    } catch {
        recordAppLog(.warning, "公共 APP 版本服务不可用，回退当前 Harvest 服务：\(error.localizedDescription)")
        return try await appState.api(path)
    }
}

func appUpdateCurrentVersion() -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let build = (info["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if version.isEmpty { return build.isEmpty ? "-" : build }
    return build.isEmpty ? version : "\(version)+\(build)"
}

func compareAppVersions(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    let right = rhs.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    for index in 0..<max(left.count, right.count) {
        let lvalue = index < left.count ? left[index] : 0
        let rvalue = index < right.count ? right[index] : 0
        if lvalue != rvalue { return lvalue < rvalue ? -1 : 1 }
    }
    return 0
}

func isAppUpdateVersionIgnored(_ version: String) -> Bool {
    guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    return UserDefaults.standard.string(forKey: appUpdateIgnoredVersionKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        == version.trimmingCharacters(in: .whitespacesAndNewlines)
}

func setAppUpdateVersionIgnored(_ version: String, ignored: Bool) {
    guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if ignored {
        UserDefaults.standard.set(version, forKey: appUpdateIgnoredVersionKey)
    } else {
        UserDefaults.standard.removeObject(forKey: appUpdateIgnoredVersionKey)
    }
}

@MainActor
func availableAppUpdateVersion(_ appState: AppState) async -> String? {
    do {
        guard let release = jsonPayloadDictionary(try await appUpdateRequest(APIPath.appVersionLatest, appState: appState)) else { return nil }
        let version = release.string("version", "tag", "version_name", "name") ?? ""
        guard !version.isEmpty, hasIOSAppPackage(release),
              compareAppVersions(version, appUpdateCurrentVersion()) > 0 else { return nil }
        return version
    } catch {
        recordAppLog(.warning, "自动检查 APP 更新失败：\(error.localizedDescription)")
        return nil
    }
}

func iosDownloadLinks(_ version: [String: Any]) -> [IOSDownloadLink] {
    var links: [IOSDownloadLink] = []
    var seen = Set<String>()
    let releaseVersion = version.string("version", "tag", "version_name", "name") ?? ""

    func append(label: String, value: Any?, requireIOSMarker: Bool = true) {
        let resolvedLabel: String
        let resolvedValue: Any?
        let resolvedSHA256: String?
        if let dictionary = value as? [String: Any] {
            resolvedLabel = dictionary.string("name", "file", "filename", "label", "platform") ?? label
            resolvedValue = dictionary["url"] ?? dictionary["download_url"] ?? dictionary["downloadUrl"] ?? dictionary["link"]
            resolvedSHA256 = normalizedSHA256(
                dictionary.string("sha256", "sha_256", "checksum", "digest", "file_hash", "fileHash")
            )
        } else {
            resolvedLabel = label
            resolvedValue = value
            resolvedSHA256 = nil
        }
        let raw = (resolvedValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directURL = URL(string: raw)
        let url: URL?
        if let directURL, directURL.scheme?.lowercased() == "https" {
            url = directURL
        } else if !releaseVersion.isEmpty {
            let rawFileName = URL(string: raw)?.lastPathComponent ?? ""
            let fallbackFileName = rawFileName.isEmpty ? resolvedLabel : rawFileName
            var components = URLComponents()
            components.scheme = "https"
            components.host = "github.com"
            components.path = "/xiaojun5270/harvest-ios/releases/download/\(releaseVersion)/\(fallbackFileName)"
            url = components.url
        } else {
            url = nil
        }
        guard let url else { return }
        let marker = "\(resolvedLabel) \(raw) \(url.absoluteString)".lowercased()
        let isIOS = marker.contains("ios") || marker.contains("iphone")
            || marker.contains("ipad") || marker.contains("ipa") || marker.contains("testflight")
        guard !requireIOSMarker || isIOS else { return }
        guard seen.insert(url.absoluteString).inserted else { return }
        links.append(
            IOSDownloadLink(
                label: resolvedLabel.isEmpty ? "iOS 下载" : resolvedLabel,
                url: url,
                sha256: resolvedSHA256
            )
        )
    }

    for key in ["downloadLinks", "download_links", "downloads", "assets"] {
        if let dictionary = version[key] as? [String: Any] {
            for (label, value) in dictionary { append(label: label, value: value) }
        } else if let values = version[key] as? [Any] {
            for (index, value) in values.enumerated() { append(label: "下载 \(index + 1)", value: value) }
        }
    }

    for key in ["url", "download_url", "downloadUrl", "link"] {
        append(label: "下载地址", value: version[key])
    }
    if links.isEmpty {
        for key in ["url", "download_url", "downloadUrl", "link"] {
            append(label: "版本下载页面", value: version[key], requireIOSMarker: false)
        }
    }
    return links.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
}

private func normalizedSHA256(_ value: String?) -> String? {
    (value ?? "")
        .lowercased()
        .split(whereSeparator: { !$0.isHexDigit })
        .map(String.init)
        .first { $0.count == 64 }
}

private func isZIPArchive(_ url: URL) throws -> Bool {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let header = try handle.read(upToCount: 4), header.count == 4 else { return false }
    return Array(header) == [0x50, 0x4B, 0x03, 0x04]
}

private func fileSHA256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func hasIOSAppPackage(_ version: [String: Any]) -> Bool {
    iosDownloadLinks(version).contains { link in
        let marker = "\(link.label) \(link.url.absoluteString)".lowercased()
        return marker.contains("ios") || marker.contains("iphone") || marker.contains("ipad")
            || marker.contains("ipa") || marker.contains("testflight")
    }
}

private func isGithubDownloadURL(_ url: URL) -> Bool {
    let host = url.host?.lowercased() ?? ""
    return host == "github.com" || host == "raw.githubusercontent.com"
        || host == "objects.githubusercontent.com" || host.hasSuffix(".githubusercontent.com")
}

private func appUpdateFileName(link: IOSDownloadLink, version: String) -> String {
    let candidates = [link.label, link.url.lastPathComponent.removingPercentEncoding ?? link.url.lastPathComponent]
    for candidate in candidates {
        let safe = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|"))
            .joined(separator: "_")
        if !safe.isEmpty, !URL(fileURLWithPath: safe).pathExtension.isEmpty { return safe }
    }
    let safeVersion = version.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    return "Harvest-\(safeVersion.isEmpty ? "latest" : safeVersion).ipa"
}

private struct AppUpdateLinkRow: View {
    @ObservedObject var model: AppUpdateViewModel
    let release: [String: Any]
    let link: IOSDownloadLink

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.label).font(.subheadline)
                Text(link.url.lastPathComponent.removingPercentEncoding ?? link.url.host ?? link.url.absoluteString)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { Task { await model.download(link, release: release) } } label: { Image(systemName: "arrow.down.circle") }
                .disabled(model.isDownloading)
                .accessibilityLabel("下载并分享 \(link.label)")
            Menu {
                Button { model.copyDownloadURL(link) } label: { Label("复制下载链接", systemImage: "doc.on.doc") }
                Link(destination: link.url) { Label("在浏览器中打开", systemImage: "safari") }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("下载链接操作")
        }
    }
}

private struct AppUpdateLatestSection: View {
    @ObservedObject var model: AppUpdateViewModel

    var body: some View {
        Section("APP 最新版本") {
            LabeledContent("当前版本", value: model.currentVersion)
            if model.isLoading && model.latest.isEmpty {
                HStack { ProgressView(); Text("正在检查新版本").foregroundStyle(.secondary) }
            } else if model.latest.isEmpty {
                Text("暂未获取到版本信息").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    LabeledContent("最新版本", value: model.latestVersion.isEmpty ? "未知" : model.latestVersion)
                    if model.hasNewVersion { Text("可更新").font(.caption2.weight(.semibold)).foregroundStyle(HarvestTheme.coral) }
                }
                if let notes = model.latest.string("changelog", "changeLog", "description", "notes", "body"), !notes.isEmpty {
                    Text(markdownAttributedString(notes)).font(.caption).textSelection(.enabled)
                }
                ForEach(model.latestLinks) { link in
                    AppUpdateLinkRow(model: model, release: model.latest, link: link)
                }
                if model.latestLinks.isEmpty {
                    Text("当前版本未提供可识别的 iOS/IPA 下载地址").font(.caption).foregroundStyle(.secondary)
                }
            }
            Link(destination: appUpdateDownloadPageURL) { Label("打开下载页", systemImage: "arrow.up.right.square") }
            Link(destination: appUpdateTestFlightURL) { Label("通过 TestFlight 安装", systemImage: "apple.logo") }
        }
    }
}

private struct AppUpdateOptionsSection: View {
    @ObservedObject var model: AppUpdateViewModel

    var body: some View {
        Section("下载选项") {
            Toggle("不再提醒当前版本", isOn: Binding(
                get: { model.isLatestIgnored },
                set: model.setLatestIgnored
            ))
            .disabled(model.latestVersion.isEmpty)
            Toggle("GitHub 下载加速", isOn: $model.useGithubProxy)
            if model.useGithubProxy {
                if !model.proxyResults.isEmpty {
                    Picker("加速地址", selection: $model.selectedProxy) {
                        Text("使用原始地址").tag("")
                        ForEach(model.proxyResults) { result in
                            Text("\(result.url) · \(result.milliseconds) ms").tag(result.url)
                        }
                    }
                }
                Button { Task { await model.testGithubProxies() } } label: {
                    if model.isTestingProxy {
                        HStack { ProgressView(); Text("正在测速") }
                    } else {
                        Label("测试并选择最快地址", systemImage: "gauge.with.dots.needle.67percent")
                    }
                }
                .disabled(model.isTestingProxy || model.isDownloading)
            }
            if model.isDownloading {
                if model.expectedDownloadBytes > 0 {
                    ProgressView(value: model.downloadProgress) {
                        Text("正在下载安装包")
                    } currentValueLabel: {
                        Text(model.downloadProgress.formatted(.percent.precision(.fractionLength(1))))
                    }
                } else {
                    HStack { ProgressView(); Text("正在下载安装包") }
                }
                if model.downloadedBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: model.downloadedBytes, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(role: .destructive) { model.cancelDownload() } label: { Label("取消下载", systemImage: "xmark.circle") }
            }
            if !model.statusMessage.isEmpty { Text(model.statusMessage).font(.caption).foregroundStyle(.secondary) }
            if !model.errorMessage.isEmpty { Text(model.errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
    }
}

private struct AppUpdateHistorySection: View {
    @ObservedObject var model: AppUpdateViewModel

    var body: some View {
        if !model.versions.isEmpty {
            Section("APP 版本历史") {
                ForEach(Array(model.versions.enumerated()), id: \.offset) { _, version in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(version.string("version", "tag", "version_name", "name") ?? "未知版本")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let created = version.string("created_at", "published_at", "date"), !created.isEmpty {
                                Text(created).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let notes = version.string("changelog", "changeLog", "description", "notes", "body"), !notes.isEmpty {
                            Text(markdownAttributedString(notes)).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                        }
                        ForEach(iosDownloadLinks(version)) { link in
                            AppUpdateLinkRow(model: model, release: version, link: link)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

struct AppUpdatePromptView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppUpdateViewModel()
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("版本视图", selection: $selectedTab) {
                        Text("最新版本").tag(0)
                        Text("历史版本").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                if selectedTab == 0 {
                    AppUpdateLatestSection(model: model)
                    AppUpdateOptionsSection(model: model)
                } else {
                    AppUpdateHistorySection(model: model)
                    if !model.isLoading && model.versions.isEmpty {
                        Section { Text("暂无 APP 版本历史").foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle(model.hasNewVersion ? "发现新版本" : "APP 更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refreshAppUpdates() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.isLoading)
                        .accessibilityLabel("检查更新")
                }
            }
        }
        .task { await model.load(appState) }
        .onDisappear { model.cancelDownload() }
        .sheet(item: $model.completedPackage) { package in ActivityShareSheet(items: [package.url]) }
    }

    @MainActor private func refreshAppUpdates() async {
        await appState.runManualRefresh(title: "正在检查 APP 更新", successMessage: "更新检查完成") {
            await model.load(appState)
            if !model.errorMessage.isEmpty { appState.presentedError = model.errorMessage }
        }
    }
}

private enum ServerUpdateTarget: String, CaseIterable, Identifiable {
    case backend
    case sites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backend: "后端代码"
        case .sites: "站点配置"
        }
    }

    var endpoint: String {
        switch self {
        case .backend: APIPath.updateLog
        case .sites: APIPath.updateSites
        }
    }

    var icon: String {
        switch self {
        case .backend: "shippingbox"
        case .sites: "doc.text"
        }
    }

    var action: ServerUpgradeAction {
        switch self {
        case .backend: .backend
        case .sites: .sites
        }
    }
}

private enum ServerUpgradeAction: String, Identifiable {
    case backend = "upgrade_django"
    case sites = "upgrade_sites"
    case webUI = "upgrade_webui"
    case all = "upgrade_all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .backend: "更新后端代码"
        case .sites: "更新站点配置"
        case .webUI: "更新 WEBUI"
        case .all: "更新所有"
        }
    }
}

private struct ServerUpdateCommit {
    var hash: String?
    var message: String
    var author: String?
    var date: String?
    var raw: String

    init(_ json: [String: Any]) {
        hash = serverUpdateFirstString(json, keys: ["hash", "hex", "commit", "commit_id", "sha", "id", "revision"])
        let rawValue = serverUpdateFirstString(json, keys: ["raw", "text", "line", "data"]) ?? prettyJSON(json)
        let parsedMessage = serverUpdateFirstString(json, keys: ["message", "msg", "subject", "title", "summary", "name", "data"])
        message = parsedMessage?.isEmpty == false ? parsedMessage! : rawValue
        author = serverUpdateFirstString(json, keys: ["author", "committer", "user", "username"])
        date = serverUpdateFirstString(json, keys: ["date", "time", "datetime", "created_at", "commit_time", "timestamp"])
        raw = rawValue
    }

    init(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        hash = serverUpdateFirstMatch(in: trimmed, pattern: #"\b[0-9a-f]{7,40}\b"#)
        var parsedMessage = trimmed
        if let hash, let range = parsedMessage.range(of: hash, options: .caseInsensitive) {
            parsedMessage.removeSubrange(range)
            parsedMessage = parsedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if parsedMessage.hasPrefix("-") {
                parsedMessage.removeFirst()
                parsedMessage = parsedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        message = parsedMessage.isEmpty ? trimmed : parsedMessage
        author = nil
        date = nil
        raw = trimmed
    }

    var shortHash: String {
        guard let hash else { return "" }
        return hash.count > 8 ? String(hash.prefix(8)) : hash
    }
}

private struct ServerUpdateLogInfo {
    let target: ServerUpdateTarget
    var hasUpdate: Bool?
    var behindCount: Int?
    var branch: String?
    var localVersion: String?
    var remoteVersion: String?
    var message: String?
    var rawText: String?
    var localLog: ServerUpdateCommit?
    var commits: [ServerUpdateCommit]
    var checkedAt: Date

    init(target: ServerUpdateTarget, response: Any) {
        self.target = target
        hasUpdate = nil
        behindCount = nil
        branch = nil
        localVersion = nil
        remoteVersion = nil
        message = nil
        rawText = nil
        localLog = nil
        commits = []
        checkedAt = Date()

        guard let payload = serverUpdatePayload(response) else {
            message = "暂无返回数据"
            return
        }
        if let values = payload as? [Any] {
            commits = serverUpdateParseCommitList(values)
            hasUpdate = !commits.isEmpty
            return
        }
        if let text = payload as? String {
            commits = serverUpdateParseCommits(text)
            hasUpdate = serverUpdateInferAvailability(text, commits: commits)
            rawText = text
            return
        }
        guard let json = payload as? [String: Any] else {
            let text = String(describing: payload)
            commits = serverUpdateParseCommits(text)
            hasUpdate = serverUpdateInferAvailability(text, commits: commits)
            rawText = text
            return
        }

        localLog = serverUpdateParseSingleCommit(serverUpdateFirstValue(json, keys: ["local_logs", "localLog", "local_log"]))
        rawText = serverUpdateFirstString(json, keys: ["raw", "text", "log_text", "output", "stdout", "result"])
        let listValue = serverUpdateFirstValue(
            json,
            keys: ["update_notes", "updateNotes", "logs", "log", "commits", "commit_logs", "updates", "changes", "items", "results"]
        )
        commits = serverUpdateParseCommitValue(listValue)
        if commits.isEmpty, let rawText { commits = serverUpdateParseCommits(rawText) }

        let explicit = serverUpdateFirstBool(
            json,
            keys: ["has_update", "hasUpdate", "need_update", "needUpdate", "can_update", "canUpdate", "update", "updated"]
        )
        let behind = serverUpdateFirstInt(json, keys: ["behind", "behind_count", "behindCount", "count", "total"])
        message = serverUpdateFirstString(json, keys: ["message", "msg", "detail", "summary", "status"])
        hasUpdate = explicit ?? (behind.map { $0 > 0 } ?? serverUpdateInferAvailability(rawText ?? message, commits: commits))
        behindCount = behind ?? (commits.isEmpty ? nil : commits.count)
        branch = serverUpdateFirstString(json, keys: ["branch", "current_branch"])
        localVersion = serverUpdateFirstString(
            json,
            keys: ["local", "local_version", "localVersion", "current", "current_version"]
        ) ?? localLog?.hash
        remoteVersion = serverUpdateFirstString(
            json,
            keys: ["remote", "remote_version", "remoteVersion", "latest", "latest_version"]
        )
    }

    var currentCommitIndex: Int? {
        guard let version = effectiveLocalVersion else { return nil }
        return commits.firstIndex { $0.hash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == version.lowercased() }
    }

    var pendingUpdateCount: Int {
        if let currentCommitIndex { return currentCommitIndex }
        if let behindCount { return max(0, behindCount) }
        if hasUpdate == false { return 0 }
        return commits.count
    }

    var needsUpdate: Bool {
        if pendingUpdateCount > 0 { return true }
        return hasUpdate == true && commits.isEmpty && behindCount == nil
    }

    var statusText: String {
        if needsUpdate { return pendingUpdateCount > 0 ? "发现 \(pendingUpdateCount) 个更新" : "发现更新" }
        if hasUpdate == false || currentCommitIndex != nil { return "已是最新" }
        return "状态未知"
    }

    var detailText: String {
        var values: [String] = []
        if let branch, !branch.isEmpty { values.append(branch) }
        if let effectiveLocalVersion { values.append("本地 \(effectiveLocalVersion)") }
        if let remoteVersion, !remoteVersion.isEmpty { values.append("远端 \(remoteVersion)") }
        if !values.isEmpty { return values.joined(separator: " · ") }
        if let message, !message.isEmpty { return message }
        if let rawText, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, commits.isEmpty { return rawText }
        return "最近检查 \(checkedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var effectiveLocalVersion: String? {
        let local = localVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !local.isEmpty { return local }
        let fallback = localLog?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }
}

private struct ServerUpdateFetchResult {
    let target: ServerUpdateTarget
    let info: ServerUpdateLogInfo?
    let error: String?
}

@MainActor
private final class ServerUpdateViewModel: ObservableObject {
    @Published private(set) var backend: ServerUpdateLogInfo?
    @Published private(set) var sites: ServerUpdateLogInfo?
    @Published private(set) var loadingTargets = Set<ServerUpdateTarget>()
    @Published private(set) var updatingAction: ServerUpgradeAction?
    @Published var errorMessage = ""
    @Published var resultMessage = ""

    var isLoading: Bool { !loadingTargets.isEmpty }
    var hasAnyUpdate: Bool { [backend, sites].compactMap { $0 }.contains(where: \.needsUpdate) }
    var updateCount: Int { [backend, sites].compactMap { $0 }.reduce(0) { $0 + $1.pendingUpdateCount } }
    var allLatest: Bool {
        guard let backend, let sites else { return false }
        return !backend.needsUpdate && !sites.needsUpdate && backend.hasUpdate == false && sites.hasUpdate == false
    }

    func info(for target: ServerUpdateTarget) -> ServerUpdateLogInfo? {
        switch target {
        case .backend: backend
        case .sites: sites
        }
    }

    func load(_ appState: AppState) async {
        loadingTargets = Set(ServerUpdateTarget.allCases)
        errorMessage = ""
        async let backendResult = fetch(.backend, appState: appState)
        async let sitesResult = fetch(.sites, appState: appState)
        let fetched = await (backendResult, sitesResult)
        let results = [fetched.0, fetched.1]
        loadingTargets.removeAll()
        for result in results { apply(result) }
        errorMessage = results.compactMap(\.error).joined(separator: "\n")
    }

    func refresh(_ target: ServerUpdateTarget, appState: AppState) async {
        loadingTargets.insert(target)
        let result = await fetch(target, appState: appState)
        loadingTargets.remove(target)
        apply(result)
        if let error = result.error { errorMessage = error }
        else { errorMessage = "" }
    }

    func run(_ action: ServerUpgradeAction, appState: AppState) async -> Bool {
        guard updatingAction == nil else { return false }
        updatingAction = action
        errorMessage = ""
        resultMessage = ""
        defer { updatingAction = nil }
        do {
            let raw = try await appState.api(APIPath.programUpdate, query: ["upgrade_tag": action.rawValue])
            resultMessage = serverUpdateCommandMessage(raw)
            switch action {
            case .backend:
                await refresh(.backend, appState: appState)
            case .sites:
                await refresh(.sites, appState: appState)
            case .webUI, .all:
                await load(appState)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            appState.presentedError = error.localizedDescription
            return false
        }
    }

    private func fetch(_ target: ServerUpdateTarget, appState: AppState) async -> ServerUpdateFetchResult {
        do {
            let raw = try await appState.api(target.endpoint)
            return ServerUpdateFetchResult(target: target, info: ServerUpdateLogInfo(target: target, response: raw), error: nil)
        } catch {
            recordAppLog(.warning, "读取\(target.title)更新日志失败：\(error.localizedDescription)")
            return ServerUpdateFetchResult(target: target, info: nil, error: "\(target.title)更新日志获取失败")
        }
    }

    private func apply(_ result: ServerUpdateFetchResult) {
        guard let info = result.info else { return }
        switch result.target {
        case .backend: backend = info
        case .sites: sites = info
        }
    }
}

private struct ServerUpdateTargetRows: View {
    let target: ServerUpdateTarget
    let info: ServerUpdateLogInfo?
    let isLoading: Bool
    let anyUpdating: Bool
    let isUpdating: Bool
    let onRefresh: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        if let info {
            HStack(spacing: 10) {
                Label(target.title, systemImage: target.icon)
                Spacer()
                StatusPill(
                    label: info.statusText,
                    color: info.needsUpdate ? HarvestTheme.coral : info.hasUpdate == false ? HarvestTheme.green : .secondary
                )
            }
            Text(info.detailText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !info.commits.isEmpty {
                let visible = Array(info.commits.prefix(12))
                ForEach(Array(visible.enumerated()), id: \.offset) { index, commit in
                    ServerUpdateCommitRow(
                        commit: commit,
                        pending: info.currentCommitIndex.map { index < $0 } ?? info.needsUpdate,
                        current: info.currentCommitIndex == index
                    )
                }
                if info.commits.count > visible.count {
                    Text("还有 \(info.commits.count - visible.count) 条远端记录")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if let rawText = info.rawText, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("原始更新日志") {
                    Text(rawText).font(.caption.monospaced()).textSelection(.enabled)
                }
            } else {
                Text("暂无更新记录").font(.caption).foregroundStyle(.secondary)
            }
        } else if isLoading {
            HStack { ProgressView(); Text("正在获取\(target.title)更新日志").foregroundStyle(.secondary) }
        } else {
            ContentUnavailableView("未获取更新状态", systemImage: target.icon)
        }

        HStack(spacing: 12) {
            Button(action: onRefresh) { Label("检查", systemImage: "arrow.clockwise") }
                .disabled(isLoading || anyUpdating)
            Spacer()
            Button(action: onUpdate) {
                if isUpdating { ProgressView() }
                else { Label(info?.needsUpdate == true ? "更新" : "重装", systemImage: "arrow.down.circle") }
            }
            .disabled(info == nil || isLoading || anyUpdating)
        }
    }
}

private struct ServerUpdateCommitRow: View {
    let commit: ServerUpdateCommit
    let pending: Bool
    let current: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: current ? "checkmark.circle.fill" : pending ? "arrow.down.circle.fill" : "circle.fill")
                .font(.caption)
                .foregroundStyle(current ? HarvestTheme.green : pending ? HarvestTheme.coral : Color.secondary.opacity(0.45))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if current { Text("当前").font(.caption2.weight(.semibold)).foregroundStyle(HarvestTheme.green) }
                    if !commit.shortHash.isEmpty { Text(commit.shortHash).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    if let date = commit.date, !date.isEmpty { Text(date).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
                Text(markdownAttributedString(commit.message))
                    .font(.caption)
                    .lineLimit(4)
                    .textSelection(.enabled)
                if let author = commit.author, !author.isEmpty {
                    Text(author).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct UpdateMaintenanceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var serverUpdater = ServerUpdateViewModel()
    @StateObject private var appUpdater = AppUpdateViewModel()
    @State private var selectedUpgrade: ServerUpgradeAction?
    @State private var networkMessage = ""
    @State private var isSpeedTesting = false

    var body: some View {
        Form {
            Section("程序更新") {
                HStack {
                    Label("更新状态", systemImage: serverUpdater.hasAnyUpdate ? "exclamationmark.circle.fill" : "checkmark.circle")
                    Spacer()
                    Text(serverUpdateSummary).font(.caption).foregroundStyle(.secondary)
                }
                if !serverUpdater.errorMessage.isEmpty {
                    Label(serverUpdater.errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(HarvestTheme.coral)
                }
                if !serverUpdater.resultMessage.isEmpty {
                    Text(markdownAttributedString(serverUpdater.resultMessage)).font(.caption).textSelection(.enabled)
                }
            }

            ForEach(ServerUpdateTarget.allCases) { target in
                Section(target.title) {
                    ServerUpdateTargetRows(
                        target: target,
                        info: serverUpdater.info(for: target),
                        isLoading: serverUpdater.loadingTargets.contains(target),
                        anyUpdating: serverUpdater.updatingAction != nil,
                        isUpdating: serverUpdater.updatingAction == target.action,
                        onRefresh: { Task { await refreshServerUpdate(target) } },
                        onUpdate: { selectedUpgrade = target.action }
                    )
                }
            }

            Section("批量操作") {
                Button { selectedUpgrade = .webUI } label: { Label("更新 WEBUI", systemImage: "globe") }
                    .disabled(serverUpdater.updatingAction != nil)
                Button { selectedUpgrade = .all } label: { Label("更新所有", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(serverUpdater.updatingAction != nil)
            }

            Section("网络") {
                Button { Task { await speedTest() } } label: {
                    if isSpeedTesting { HStack { ProgressView(); Text("正在执行网络测速") } }
                    else { Label("执行网络测速", systemImage: "gauge.with.dots.needle.67percent") }
                }
                .disabled(isSpeedTesting || serverUpdater.updatingAction != nil)
                if !networkMessage.isEmpty { Text(networkMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }

            AppUpdateLatestSection(model: appUpdater)
            AppUpdateOptionsSection(model: appUpdater)
            AppUpdateHistorySection(model: appUpdater)
        }
        .navigationTitle("更新与网络")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { appUpdater.cancelDownload() }
        .sheet(item: $appUpdater.completedPackage) { package in ActivityShareSheet(items: [package.url]) }
        .confirmationDialog(
            selectedUpgrade?.label ?? "执行更新",
            isPresented: Binding(
                get: { selectedUpgrade != nil },
                set: { if !$0 { selectedUpgrade = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认执行") {
                guard let action = selectedUpgrade else { return }
                selectedUpgrade = nil
                Task { await runServerUpdate(action) }
            }
            Button("取消", role: .cancel) { selectedUpgrade = nil }
        } message: {
            Text("将调用后端升级接口执行 \(selectedUpgrade?.rawValue ?? "")。升级过程中服务可能会短暂不可用。")
        }
    }

    private var serverUpdateSummary: String {
        if serverUpdater.hasAnyUpdate {
            return serverUpdater.updateCount > 0 ? "\(serverUpdater.updateCount) 条待更新" : "发现可用更新"
        }
        if serverUpdater.isLoading { return "正在检查" }
        if serverUpdater.allLatest { return "全部最新" }
        return "状态未知"
    }

    @MainActor private func load() async {
        async let serverLoad: Void = serverUpdater.load(appState)
        async let appLoad: Void = appUpdater.load(appState)
        _ = await (serverLoad, appLoad)
    }

    @MainActor private func speedTest() async {
        isSpeedTesting = true
        defer { isSpeedTesting = false }
        do {
            let raw = try await appState.api(APIPath.speedTest)
            networkMessage = jsonMessage(raw) ?? "测速任务已提交"
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func refreshServerUpdate(_ target: ServerUpdateTarget) async {
        await appState.runManualRefresh(
            title: "正在检查\(target.title)",
            successMessage: "\(target.title)检查完成"
        ) {
            await serverUpdater.refresh(target, appState: appState)
            if !serverUpdater.errorMessage.isEmpty {
                appState.presentedError = serverUpdater.errorMessage
            }
        }
    }

    @MainActor private func runServerUpdate(_ action: ServerUpgradeAction) async {
        _ = await appState.runManualTask(
            title: "正在执行\(action.label)",
            successMessage: "\(action.label)任务已完成"
        ) {
            let succeeded = await serverUpdater.run(action, appState: appState)
            if !succeeded, !serverUpdater.errorMessage.isEmpty {
                appState.presentedError = serverUpdater.errorMessage
            }
            return succeeded
        }
    }
}

private func serverUpdatePayload(_ value: Any) -> Any? {
    if value is NSNull { return nil }
    guard let dictionary = value as? [String: Any] else { return value }
    let isEnvelope = dictionary["code"] != nil || dictionary["succeed"] != nil || dictionary["success"] != nil
    guard isEnvelope else { return value }
    for key in ["data", "result"] {
        if let nested = dictionary[key], !(nested is NSNull) { return nested }
    }
    return value
}

private func serverUpdateFirstValue(_ json: [String: Any], keys: [String]) -> Any? {
    for key in keys where json[key] != nil { return json[key] }
    return nil
}

private func serverUpdateFirstString(_ json: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = json[key] as? String {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        } else if let value = json[key] as? NSNumber {
            return value.stringValue
        }
    }
    return nil
}

private func serverUpdateFirstBool(_ json: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        if let value = json[key] as? Bool { return value }
        if let value = json[key] as? NSNumber { return value.boolValue }
        if let value = json[key] as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "y": return true
            case "false", "0", "no", "n": return false
            default: continue
            }
        }
    }
    return nil
}

private func serverUpdateFirstInt(_ json: [String: Any], keys: [String]) -> Int? {
    for key in keys {
        if let value = json[key] as? Int { return value }
        if let value = json[key] as? NSNumber { return value.intValue }
        if let value = json[key] as? String, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return number }
    }
    return nil
}

private func serverUpdateParseCommitValue(_ value: Any?) -> [ServerUpdateCommit] {
    guard let value, !(value is NSNull) else { return [] }
    if let values = value as? [Any] { return serverUpdateParseCommitList(values) }
    if let text = value as? String { return serverUpdateParseCommits(text) }
    if let dictionary = value as? [String: Any] {
        if serverUpdateIsCommitMap(dictionary) { return [ServerUpdateCommit(dictionary)] }
        return serverUpdateParseCommitList(Array(dictionary.values))
    }
    return [ServerUpdateCommit(text: String(describing: value))]
}

private func serverUpdateParseSingleCommit(_ value: Any?) -> ServerUpdateCommit? {
    if let dictionary = value as? [String: Any] { return ServerUpdateCommit(dictionary) }
    if let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return ServerUpdateCommit(text: text)
    }
    return nil
}

private func serverUpdateIsCommitMap(_ json: [String: Any]) -> Bool {
    ["hex", "hash", "commit", "sha", "data", "message"].contains { json[$0] != nil }
}

private func serverUpdateParseCommitList(_ values: [Any]) -> [ServerUpdateCommit] {
    values.compactMap { value in
        let commit: ServerUpdateCommit
        if let dictionary = value as? [String: Any] { commit = ServerUpdateCommit(dictionary) }
        else { commit = ServerUpdateCommit(text: String(describing: value)) }
        guard !commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !serverUpdateLooksCurrent(commit.message) else { return nil }
        return commit
    }
}

private func serverUpdateParseCommits(_ text: String) -> [ServerUpdateCommit] {
    let pattern = #"(?ms)^commit\s+([0-9a-f]{7,40})(.*?)(?=^commit\s+[0-9a-f]{7,40}|\z)"#
    if let expression = try? NSRegularExpression(pattern: pattern),
       !expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).isEmpty {
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let hashRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
            let raw = String(text[fullRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(text[bodyRange])
            let message = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.hasPrefix("Author:") && !$0.hasPrefix("Date:") } ?? raw
            var commit = ServerUpdateCommit(text: message)
            commit.hash = String(text[hashRange])
            commit.author = serverUpdateFirstMatch(in: body, pattern: #"(?m)^Author:\s*(.+)$"#, capture: 1)
            commit.date = serverUpdateFirstMatch(in: body, pattern: #"(?m)^Date:\s*(.+)$"#, capture: 1)
            commit.raw = raw
            return commit
        }
    }
    return text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !serverUpdateLooksCurrent($0) }
        .map { ServerUpdateCommit(text: $0) }
}

private func serverUpdateFirstMatch(in text: String, pattern: String, capture: Int = 0) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > capture,
          let range = Range(match.range(at: capture), in: text) else { return nil }
    let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func serverUpdateInferAvailability(_ text: String?, commits: [ServerUpdateCommit]) -> Bool? {
    if !commits.isEmpty { return true }
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    if serverUpdateLooksCurrent(text) { return false }
    return serverUpdateFirstMatch(in: text, pattern: #"\b[0-9a-f]{7,40}\b"#) == nil ? nil : true
}

private func serverUpdateLooksCurrent(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.contains("already up to date") || lower.contains("already up-to-date")
        || lower.contains("up to date") || lower.contains("no update") || lower.contains("no updates")
        || text.contains("暂无更新") || text.contains("无更新") || text.contains("已是最新") || text.contains("已经是最新")
}

private func serverUpdateCommandMessage(_ value: Any) -> String {
    let payload = serverUpdatePayload(value)
    if let text = payload as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "升级命令已执行" : trimmed
    }
    if let dictionary = payload as? [String: Any] {
        return serverUpdateFirstString(
            dictionary,
            keys: ["message", "msg", "detail", "summary", "output", "stdout", "result"]
        ) ?? "升级命令已执行"
    }
    return payload.map { String(describing: $0) } ?? "升级命令已执行"
}

fileprivate enum BackendOptionFieldKind {
    case text
    case multiline
    case integer
    case toggle
}

fileprivate struct BackendOptionFieldDefinition: Identifiable {
    let key: String
    let label: String
    let kind: BackendOptionFieldKind
    let defaultValue: Any
    var sensitive = false
    var readOnly = false
    var help: String?
    var id: String { key }

    static func text(
        _ key: String,
        _ label: String,
        defaultValue: String = "",
        multiline: Bool = false,
        sensitive: Bool = false,
        readOnly: Bool = false,
        help: String? = nil
    ) -> Self {
        .init(
            key: key,
            label: label,
            kind: multiline ? .multiline : .text,
            defaultValue: defaultValue,
            sensitive: sensitive,
            readOnly: readOnly,
            help: help
        )
    }

    static func integer(_ key: String, _ label: String, defaultValue: Int, help: String? = nil) -> Self {
        .init(key: key, label: label, kind: .integer, defaultValue: defaultValue, help: help)
    }

    static func toggle(_ key: String, _ label: String, defaultValue: Bool) -> Self {
        .init(key: key, label: label, kind: .toggle, defaultValue: defaultValue)
    }
}

fileprivate struct BackendOptionDefinition: Identifiable {
    let name: String
    let title: String
    let icon: String
    let fields: [BackendOptionFieldDefinition]
    var additionalDefaults: [String: Any] = [:]
    var readOnly = false
    var id: String { name }

    var initialValue: [String: Any] {
        var result = additionalDefaults
        for field in fields { result[field.key] = field.defaultValue }
        return result
    }
}

private let backendOptionDefinitions: [BackendOptionDefinition] = [
    .init(name: "monkey_token", title: "安全 Token", icon: "key", fields: [
        .text("token", "令牌", sensitive: true)
    ]),
    .init(name: "wechat_work_push", title: "企业微信", icon: "message", fields: [
        .text("corp_id", "企业 ID"),
        .text("corpsecret", "企业密钥", sensitive: true),
        .text("agent_id", "应用 ID"),
        .text("to_uid", "接收 ID"),
        .text("refresh_token", "EncodingAESKey", sensitive: true),
        .text("token", "Token", sensitive: true),
        .text("server", "背景图地址"),
        .text("proxy", "固定代理")
    ]),
    .init(name: "wechat_bot_push", title: "微信机器人", icon: "ellipsis.message", fields: [
        .text("token", "IM BOT Token", readOnly: true, help: "由微信机器人扫码登录同步"),
        .text("to_uid", "IM BOT User ID", readOnly: true, help: "由微信机器人扫码登录同步")
    ], readOnly: true),
    .init(name: "qqbot_push", title: "QQ 机器人", icon: "message.badge", fields: [
        .text("app_id", "机器人 App ID"),
        .text("secret_key", "机器人 Secret", sensitive: true),
        .text("uids", "接收 UIDs", multiline: true, help: "多个 UID 可用逗号或换行分隔")
    ]),
    .init(name: "wxpusher_push", title: "WxPusher", icon: "paperplane", fields: [
        .text("app_id", "应用 ID"), .text("token", "令牌", sensitive: true), .text("uids", "接收人", multiline: true)
    ]),
    .init(name: "pushdeer_push", title: "PushDeer", icon: "paperplane", fields: [
        .text("key", "Key", sensitive: true), .text("proxy", "服务器")
    ]),
    .init(name: "bark_push", title: "Bark", icon: "bell", fields: [
        .text("device_key", "设备 ID", sensitive: true), .text("server", "服务器")
    ]),
    .init(name: "iyuu_push", title: "爱语飞飞", icon: "heart", fields: [
        .text("token", "令牌", sensitive: true), .toggle("repeat", "辅种开关", defaultValue: false)
    ]),
    .init(name: "meow_push", title: "喵呜通知", icon: "bell", fields: [
        .text("token", "喵呜令牌", sensitive: true),
        .integer("max_count", "HTML 高度", defaultValue: 200),
        .text("server", "服务器")
    ]),
    .init(name: "server_chan_push", title: "Server 酱", icon: "bell", fields: [
        .text("token", "SendKey", sensitive: true),
        .text("app_id", "OpenId"),
        .text("server", "消息通道"),
        .integer("count", "隐藏调用 IP", defaultValue: 1)
    ]),
    .init(name: "pushplus_push", title: "PushPlus", icon: "paperplane", fields: [
        .text("token", "令牌", sensitive: true)
    ], additionalDefaults: ["template": "markdown"]),
    .init(name: "telegram_push", title: "Telegram 配置", icon: "paperplane", fields: [
        .text("telegram_chat_id", "ID"),
        .text("telegram_token", "令牌", sensitive: true),
        .text("proxy", "代理")
    ]),
    .init(name: "aliyun_drive", title: "阿里云盘", icon: "externaldrive", fields: [
        .text("refresh_token", "保存令牌", multiline: true, sensitive: true),
        .toggle("welfare", "领取福利", defaultValue: true)
    ]),
    .init(name: "baidu_ocr", title: "百度 OCR", icon: "viewfinder", fields: [
        .text("app_id", "应用 ID"),
        .text("api_key", "APIKey", sensitive: true),
        .text("secret_key", "Secret", sensitive: true)
    ]),
    .init(name: "ssdforum", title: "SSDForum", icon: "globe", fields: [
        .text("cookie", "Cookie", multiline: true, sensitive: true),
        .text("user_agent", "User-Agent", multiline: true),
        .text("todaysay", "今天想说", multiline: true)
    ]),
    .init(name: "cookie_cloud", title: "CookieCloud", icon: "cloud", fields: [
        .text("server", "服务器"), .text("key", "Key", sensitive: true), .text("password", "密码", sensitive: true)
    ]),
    .init(name: "FileList", title: "FileList", icon: "doc", fields: [
        .text("username", "账号"), .text("password", "密码", sensitive: true)
    ]),
    .init(name: "tmdb_api_auth", title: "影视 Token 配置", icon: "film", fields: [
        .text("api_key", "TMDB 密钥", sensitive: true),
        .text("secret_key", "豆瓣 Cookie", multiline: true, sensitive: true),
        .text("proxy", "代理地址")
    ]),
    .init(name: "aggregation_search", title: "聚合搜索配置", icon: "magnifyingglass", fields: [
        .integer("max_count", "站点数量限制", defaultValue: 30, help: "单次搜索的站点数量，0 表示不限制"),
        .integer("limit", "并发数量限制", defaultValue: 30, help: "并发搜索站点数量，0 表示不限制")
    ]),
    .init(name: "notice_category_enable", title: "通知开关", icon: "bell.badge", fields: [
        .toggle("aliyundrive_notice", "阿里云盘", defaultValue: true),
        .toggle("site_data", "站点数据", defaultValue: true),
        .toggle("site_data_success", "成功站点消息", defaultValue: true),
        .toggle("today_data", "今日数据", defaultValue: true),
        .toggle("package_torrent", "拆包", defaultValue: true),
        .toggle("delete_torrent", "删种", defaultValue: true),
        .toggle("rss_torrent", "RSS", defaultValue: true),
        .toggle("push_torrent", "种子推送", defaultValue: true),
        .toggle("program_upgrade", "Docker 升级", defaultValue: true),
        .toggle("ptpp_import", "PTPP 导入", defaultValue: true),
        .toggle("announcement", "公告详情", defaultValue: true),
        .toggle("message", "短消息详情", defaultValue: true),
        .toggle("sign_in_success", "签到成功消息", defaultValue: true),
        .toggle("cookie_sync", "CookieCloud 同步", defaultValue: true)
    ]),
    .init(name: "notice_content_item", title: "站点详情", icon: "list.bullet.rectangle", fields: [
        .toggle("level", "等级", defaultValue: true),
        .toggle("bonus", "魔力", defaultValue: true),
        .toggle("per_bonus", "时魔", defaultValue: true),
        .toggle("score", "积分", defaultValue: true),
        .toggle("ratio", "分享率", defaultValue: true),
        .toggle("seeding_vol", "做种体积", defaultValue: true),
        .toggle("uploaded", "上传量", defaultValue: true),
        .toggle("downloaded", "下载量", defaultValue: true),
        .toggle("seeding", "做种数量", defaultValue: true),
        .toggle("leeching", "吸血数量", defaultValue: true),
        .toggle("invite", "邀请", defaultValue: true),
        .toggle("hr", "HR", defaultValue: true)
    ]),
    .init(name: "auto_import_tags", title: "自动添加标签", icon: "tag", fields: [
        .toggle("repeat", "自动添加标签", defaultValue: false)
    ])
]

private let backendOptionDefinitionsByName = Dictionary(
    backendOptionDefinitions.map { ($0.name, $0) },
    uniquingKeysWith: { _, latest in latest }
)

struct BackendOption: Identifiable {
    let serverID: Int?
    var name: String
    var value: [String: Any]
    var active: Bool
    var id: String { serverID.map { "server-\($0)" } ?? "catalog-\(name)" }
    fileprivate var definition: BackendOptionDefinition? { backendOptionDefinitionsByName[name] }
    var displayName: String { definition?.title ?? name }
    var icon: String { definition?.icon ?? "switch.2" }
    var isReadOnly: Bool { definition?.readOnly == true }

    init(_ json: [String: Any]) {
        serverID = json.int("id")
        name = json.string("name") ?? "未命名配置"
        var mergedValue = backendOptionDefinitionsByName[name]?.initialValue ?? [:]
        for (key, item) in json.dict("value") ?? [:] { mergedValue[key] = item }
        value = mergedValue
        active = json.bool("is_active", "active") ?? true
    }

    fileprivate init(definition: BackendOptionDefinition) {
        serverID = nil
        name = definition.name
        value = definition.initialValue
        active = true
    }
}

@MainActor
final class BackendOptionsViewModel: ObservableObject {
    @Published var options: [BackendOption] = []
    @Published var isLoading = true

    func load(_ appState: AppState) async {
        defer { isLoading = false }
        do {
            var loaded = jsonRows(try await appState.api(APIPath.options)).map(BackendOption.init)
            var merged: [BackendOption] = []
            for definition in backendOptionDefinitions {
                if let index = loaded.firstIndex(where: { $0.name == definition.name }) {
                    merged.append(loaded.remove(at: index))
                } else {
                    merged.append(BackendOption(definition: definition))
                }
            }
            merged.append(contentsOf: loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            options = merged
        }
        catch { appState.presentedError = error.localizedDescription }
    }

    func save(_ appState: AppState, option: BackendOption) async -> Bool {
        var body: [String: Any] = ["name": option.name, "value": option.value, "is_active": option.active]
        if let serverID = option.serverID { body["id"] = serverID }
        let path = option.serverID.map { "\(APIPath.options)/\($0)" } ?? APIPath.options
        let saved = await appState.perform(path, method: option.serverID == nil ? .post : .put, body: body)
        if saved { await load(appState) }
        return saved
    }
}

struct BackendOptionsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = BackendOptionsViewModel()
    @State private var selected: BackendOption?

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else if model.options.isEmpty { EmptyState(icon: "slider.horizontal.3", title: "没有配置项") }
            else {
                List(model.options) { option in
                    Button { selected = option } label: {
                        HStack(spacing: 12) {
                            SymbolBadge(
                                icon: option.icon,
                                color: option.active ? HarvestTheme.green : .secondary,
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName).font(.headline).foregroundStyle(.primary)
                                Text(option.serverID == nil ? "尚未创建" : "\(option.value.count) 个参数").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(
                                label: option.serverID == nil ? "新增" : option.active ? "启用" : "停用",
                                color: option.serverID == nil
                                    ? HarvestTheme.amber
                                    : option.active ? HarvestTheme.green : .secondary
                            )
                        }
                    }.buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        if option.serverID != nil && !option.isReadOnly {
                            Button {
                                Task {
                                    var updated = option
                                    updated.active.toggle()
                                    _ = await model.save(appState, option: updated)
                                }
                            } label: {
                                Label(
                                    option.active ? "停用" : "启用",
                                    systemImage: option.active ? "pause" : "play"
                                )
                            }
                            .tint(HarvestTheme.amber)
                        }
                    }
                }.listStyle(.plain).refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("后端配置").navigationBarTitleDisplayMode(.inline)
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(item: $selected) { option in OptionEditorSheet(option: option) { updated in await model.save(appState, option: updated) }.environmentObject(appState) }
    }
}

struct OptionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let option: BackendOption
    let save: (BackendOption) async -> Bool
    @State private var editedValue: [String: Any]
    @State private var active: Bool
    @State private var isSaving = false
    @State private var showRawEditor = false

    init(option: BackendOption, save: @escaping (BackendOption) async -> Bool) {
        self.option = option
        self.save = save
        _active = State(initialValue: option.active)
        _editedValue = State(initialValue: option.value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") { Toggle("启用 \(option.displayName)", isOn: $active) }
                Section("配置") {
                    ForEach(orderedKeys, id: \.self) { key in
                        BackendOptionValueField(
                            definition: option.definition?.fields.first { $0.key == key },
                            fallbackKey: key,
                            value: valueBinding(for: key)
                        )
                    }
                    if editedValue.isEmpty {
                        Text("当前配置没有参数").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if option.name == "monkey_token" {
                    Section("Token 工具") {
                        Button { makeRandomToken() } label: { Label("生成随机 Token", systemImage: "dice") }
                        Button { copyPrivateText(editedValue["token"] as? String ?? "") } label: { Label("复制 Token", systemImage: "doc.on.doc") }
                            .disabled((editedValue["token"] as? String ?? "").isEmpty)
                    }
                }
                if !option.isReadOnly && needsJSONEditor {
                    Section("高级") {
                        Button { showRawEditor = true } label: {
                            HStack(spacing: 12) {
                                Label("JSON 配置", systemImage: "curlybraces")
                                Spacer()
                                Text("\(editedValue.count) 项")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle(option.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if option.isReadOnly {
                        Button("完成") { dismiss() }
                    } else {
                        Button("保存") { Task { await persist() } }.disabled(isSaving)
                    }
                }
            }
            .disabled(isSaving)
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .sheet(isPresented: $showRawEditor) {
                BackendOptionJSONEditor(value: editedValue) { editedValue = $0 }
            }
        }
    }

    private var orderedKeys: [String] {
        let known = option.definition?.fields.map(\.key) ?? []
        return known + editedValue.keys.filter { !known.contains($0) }.sorted()
    }

    private var needsJSONEditor: Bool {
        guard let definition = option.definition else { return true }
        let knownKeys = Set(definition.fields.map(\.key)).union(definition.additionalDefaults.keys)
        if editedValue.keys.contains(where: { !knownKeys.contains($0) }) { return true }
        return editedValue.values.contains { value in
            value is [String: Any] || value is [Any] || value is NSNull
        }
    }

    private func valueBinding(for key: String) -> Binding<Any> {
        Binding(
            get: { editedValue[key] ?? NSNull() },
            set: { editedValue[key] = $0 }
        )
    }

    private func makeRandomToken() {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        editedValue["token"] = String((0..<8).compactMap { _ in characters.randomElement() })
    }

    private func persist() async {
        isSaving = true
        var updated = option
        updated.value = editedValue
        updated.active = active
        if await save(updated) { dismiss() }
        isSaving = false
    }
}

private struct BackendOptionValueField: View {
    let definition: BackendOptionFieldDefinition?
    let fallbackKey: String
    @Binding var value: Any
    @State private var revealSensitive = false

    private var label: String { definition?.label ?? fallbackKey }
    private var readOnly: Bool { definition?.readOnly == true }
    private var kind: BackendOptionFieldKind? {
        if let definition { return definition.kind }
        if value is Bool { return .toggle }
        if value is Int { return .integer }
        if value is String { return .text }
        return nil
    }

    var body: some View {
        switch kind {
        case .toggle:
            Toggle(label, isOn: Binding(get: { (value as? Bool) ?? false }, set: { value = $0 }))
                .disabled(readOnly)
        case .integer:
            BackendOptionIntegerField(label: label, value: $value, readOnly: readOnly, help: definition?.help)
        case .multiline:
            textField(multiline: true)
        case .text:
            textField(multiline: false)
        case nil:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(prettyJSON(value)).font(.caption.monospaced()).lineLimit(4).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func textField(multiline: Bool) -> some View {
        let text = Binding<String>(get: { (value as? String) ?? String(describing: value) }, set: { value = $0 })
        VStack(alignment: .leading, spacing: 5) {
            if definition?.sensitive == true && !revealSensitive {
                HStack {
                    SecureField(label, text: text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { revealSensitive = true } label: { Image(systemName: "eye") }
                        .buttonStyle(.plain).accessibilityLabel("显示 \(label)")
                }
            } else {
                HStack(alignment: multiline ? .top : .center) {
                    TextField(label, text: text, axis: multiline ? .vertical : .horizontal)
                        .lineLimit(multiline ? 3...8 : 1...1)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if definition?.sensitive == true {
                        Button { revealSensitive = false } label: { Image(systemName: "eye.slash") }
                            .buttonStyle(.plain).accessibilityLabel("隐藏 \(label)")
                    }
                }
            }
            if let help = definition?.help { Text(help).font(.caption2).foregroundStyle(.secondary) }
        }
        .disabled(readOnly)
    }
}

private struct BackendOptionIntegerField: View {
    let label: String
    @Binding var value: Any
    let readOnly: Bool
    let help: String?
    @State private var text: String

    init(label: String, value: Binding<Any>, readOnly: Bool, help: String?) {
        self.label = label
        _value = value
        self.readOnly = readOnly
        self.help = help
        let initial = (value.wrappedValue as? NSNumber)?.stringValue ?? String(describing: value.wrappedValue)
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(label, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .disabled(readOnly)
                .onChange(of: text) { _, newValue in if let number = Int(newValue) { value = number } }
            if !text.isEmpty && Int(text) == nil {
                Text("请输入整数").font(.caption2).foregroundStyle(HarvestTheme.coral)
            } else if let help {
                Text(help).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BackendOptionJSONEditor: View {
    @Environment(\.dismiss) private var dismiss
    let apply: ([String: Any]) -> Void
    private let originalText: String
    @State private var text: String
    @State private var errorMessage: String?
    @State private var isValid = true
    @State private var fieldCount: Int
    @State private var confirmDiscard = false
    @FocusState private var editorFocused: Bool

    init(value: [String: Any], apply: @escaping ([String: Any]) -> Void) {
        self.apply = apply
        let formatted = Self.formattedJSON(value)
        originalText = formatted
        _text = State(initialValue: formatted)
        _fieldCount = State(initialValue: value.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Label(
                        isValid ? "JSON 有效" : "JSON 无效",
                        systemImage: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isValid ? HarvestTheme.green : HarvestTheme.coral)
                    Spacer()
                    if isValid {
                        Text("\(fieldCount) 个顶层字段")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                Divider()

                TextEditor(text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemBackground))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($editorFocused)
                    .accessibilityLabel("配置 JSON")

                if let errorMessage {
                    Divider()
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(HarvestTheme.coral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(HarvestTheme.coral.opacity(0.08))
                }
            }
            .navigationTitle("配置 JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancelEditing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用到表单") { applyJSON() }
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { formatJSON() } label: {
                        Label("格式化", systemImage: "text.alignleft")
                    }
                    .disabled(!isValid)
                    Spacer()
                    Button { restoreOriginal() } label: {
                        Label("恢复", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasChanges)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起") { editorFocused = false }
                }
            }
            .onChange(of: text) { _, _ in validateJSON() }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("放弃未应用的 JSON 修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
        }
    }

    private var hasChanges: Bool { text != originalText }

    private static func formattedJSON(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func decodedObject() throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EditorError.empty }
        guard let data = trimmed.data(using: .utf8) else { throw EditorError.invalidEncoding }
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else { throw EditorError.rootObjectRequired }
        return object
    }

    private func validateJSON() {
        do {
            let value = try decodedObject()
            fieldCount = value.count
            isValid = true
            errorMessage = nil
        } catch {
            fieldCount = 0
            isValid = false
            errorMessage = validationMessage(for: error)
        }
    }

    private func formatJSON() {
        do {
            text = Self.formattedJSON(try decodedObject())
            validateJSON()
        } catch {
            isValid = false
            errorMessage = validationMessage(for: error)
        }
    }

    private func restoreOriginal() {
        text = originalText
        validateJSON()
    }

    private func cancelEditing() {
        if hasChanges { confirmDiscard = true }
        else { dismiss() }
    }

    private func applyJSON() {
        do {
            apply(try decodedObject())
            dismiss()
        } catch {
            isValid = false
            errorMessage = validationMessage(for: error)
        }
    }

    private func validationMessage(for error: Error) -> String {
        if let error = error as? EditorError { return error.localizedDescription }
        return "JSON 格式错误：\(error.localizedDescription)"
    }

    private enum EditorError: LocalizedError {
        case empty
        case invalidEncoding
        case rootObjectRequired

        var errorDescription: String? {
            switch self {
            case .empty: "JSON 内容不能为空"
            case .invalidEncoding: "JSON 必须使用 UTF-8 文本"
            case .rootObjectRequired: "配置顶层必须是 JSON 对象"
            }
        }
    }
}

struct ManagedUser: Identifiable, Hashable {
    let id: Int
    var username: String
    var email: String
    var active: Bool
    var staff: Bool
    var admin: Bool
    var joined: String

    init(_ json: [String: Any]) {
        id = json.int("id", "user_id") ?? 0
        username = json.string("username", "name") ?? ""
        email = json.string("email") ?? ""
        active = json.bool("is_active", "active") ?? false
        staff = json.bool("is_staff", "staff") ?? false
        admin = json.bool("is_superuser", "admin") ?? false
        joined = json.string("date_joined", "created_at", "joined") ?? ""
    }
}

@MainActor
final class UsersViewModel: ObservableObject {
    @Published var users: [ManagedUser] = []
    @Published var isLoading = true
    let endpoint: String
    init(endpoint: String) { self.endpoint = endpoint }

    func load(_ appState: AppState) async {
        defer { isLoading = false }
        do {
            users = jsonRows(try await appState.api(endpoint))
                .map(ManagedUser.init)
                .filter { $0.id > 0 || !$0.username.isEmpty }
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    func toggle(_ appState: AppState, user: ManagedUser) async {
        let body: [String: Any] = [
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "is_active": !user.active,
            "is_staff": user.staff,
            "is_superuser": user.admin
        ]
        if await appState.perform("\(endpoint)/\(user.id)", method: .put, body: body) {
            await load(appState)
        }
    }

    func delete(_ appState: AppState, user: ManagedUser) async {
        if await appState.perform("\(endpoint)/\(user.id)", method: .delete) {
            users.removeAll { $0.id == user.id }
        }
    }
}

struct UserManagementView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = UsersViewModel(endpoint: APIPath.users)
    @State private var showAdd = false
    @State private var editingUser: ManagedUser?
    @State private var resettingUser: ManagedUser?
    @State private var deletingUser: ManagedUser?
    @State private var query = ""

    private var currentUser: ManagedUser? {
        model.users.first { user in
            user.id == appState.profile?.id || user.username == appState.profile?.username
        }
    }

    private var canManageStatus: Bool {
        currentUser?.staff == true || currentUser?.admin == true
            || appState.profile?.isStaff == true || appState.profile?.isSuperuser == true
    }

    private var filteredUsers: [ManagedUser] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return model.users }
        return model.users.filter {
            $0.username.localizedCaseInsensitiveContains(value)
                || $0.email.localizedCaseInsensitiveContains(value)
                || String($0.id).contains(value)
        }
    }

    var body: some View {
        Group {
            if model.isLoading {
                LoadingState()
            } else {
                List {
                    if filteredUsers.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "没有用户" : "没有匹配的用户",
                            systemImage: "person.2.slash"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredUsers) { user in
                            let isCurrent = user.id == appState.profile?.id || user.username == appState.profile?.username
                            Button { editingUser = user } label: { UserRow(user: user, isCurrent: isCurrent) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingUser = user } label: { Label("编辑用户", systemImage: "pencil") }
                                    Button { resettingUser = user } label: { Label("重置密码", systemImage: "key") }
                                    if canManageStatus && !isCurrent {
                                        Button { Task { await model.toggle(appState, user: user) } } label: {
                                            Label(user.active ? "停用" : "启用", systemImage: user.active ? "pause" : "play")
                                        }
                                    }
                                    Button(role: .destructive) { deletingUser = user } label: { Label("删除", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if canManageStatus && !isCurrent {
                                        Button { Task { await model.toggle(appState, user: user) } } label: {
                                            Label(user.active ? "停用" : "启用", systemImage: user.active ? "pause" : "play")
                                        }
                                        .tint(HarvestTheme.amber)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { resettingUser = user } label: { Label("重置密码", systemImage: "key") }.tint(HarvestTheme.amber)
                                    Button { editingUser = user } label: { Label("编辑", systemImage: "pencil") }.tint(HarvestTheme.blue)
                                    Button(role: .destructive) { deletingUser = user } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("用户中心").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索用户名、邮箱或 ID")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("添加用户")
            }
        }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showAdd) { UserEditorSheet(endpoint: APIPath.users) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingUser) { user in UserEditorSheet(endpoint: APIPath.users, user: user) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $resettingUser) { user in UserEditorSheet(endpoint: APIPath.users, user: user, resetPassword: true) { await model.load(appState) }.environmentObject(appState) }
        .confirmationDialog(
            "确定删除用户「\(privacyMaskedText(deletingUser?.username ?? "", enabled: appState.privacyMode))」？",
            isPresented: Binding(
                get: { deletingUser != nil },
                set: { if !$0 { deletingUser = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除用户", role: .destructive) {
                guard let user = deletingUser else { return }
                deletingUser = nil
                Task { await model.delete(appState, user: user) }
            }
            Button("取消", role: .cancel) { deletingUser = nil }
        }
    }
}

struct AdminUserItem: Identifiable {
    let id: Int
    var username: String
    var email: String
    var pay: Int
    var invite: Int
    var tryUser: Bool
    var marked: String
    var expire: Int
    var expiresAt: String
    var updatedAt: String
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        id = json.int("id") ?? 0
        username = json.string("username") ?? ""
        email = json.string("email") ?? ""
        pay = json.int("pay") ?? 168
        invite = json.int("invite") ?? 0
        tryUser = json.bool("try_user", "tryUser") ?? false
        marked = json.string("marked", "remark") ?? ""
        expire = json.int("expire", "expire_days") ?? 36600
        expiresAt = json.string("time_expire", "expires_at") ?? ""
        updatedAt = json.string("updated_at", "updatedAt", "update_time") ?? ""
        raw = json
    }

    var expirationDate: Date? {
        if let date = parseDate(expiresAt) { return date }
        guard let timestamp = Double(expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)),
              timestamp.isFinite,
              timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp)
    }

    var isExpired: Bool {
        expiresAt.contains("已过期") || expirationDate.map { $0 < Date() } == true
    }

    var authorizationText: String {
        guard let expirationDate else { return expire > 0 ? "\(expire) 天" : "-" }
        guard expirationDate > Date() else { return "已过期" }
        let seconds = expirationDate.timeIntervalSinceNow
        return "剩余 \(max(0, clampedInt(ceil(seconds / 86_400)))) 天"
    }
}

@MainActor
final class AdminUsersViewModel: ObservableObject {
    @Published var users: [AdminUserItem] = []
    @Published var isLoading = true

    func load(_ appState: AppState) async {
        defer { isLoading = false }
        do { users = jsonRows(try await appState.api(APIPath.adminUsers)).map(AdminUserItem.init).filter { $0.id > 0 || !$0.email.isEmpty || !$0.username.isEmpty } }
        catch { appState.presentedError = error.localizedDescription }
    }

    func update(_ appState: AppState, user: AdminUserItem, values: [String: Any]) async -> Bool {
        var body: [String: Any] = ["id": user.id]
        for (key, value) in values { body[key] = value }
        let saved = await appState.perform(APIPath.adminUsers, method: .put, body: body)
        if saved { await load(appState) }
        return saved
    }

    func resetToken(_ appState: AppState, user: AdminUserItem, expire: Int, pay: Int, tryUser: Bool) async -> Bool {
        let saved = await appState.perform(
            APIPath.adminResetToken,
            method: .post,
            query: ["user_id": user.id],
            body: ["expire": expire, "pay": pay, "try_user": tryUser]
        )
        if saved { await load(appState) }
        return saved
    }

    func sendToken(_ appState: AppState, user: AdminUserItem) async {
        _ = await appState.perform(APIPath.adminSendToken, method: .get, query: ["user_id": user.id])
    }

    func remove(_ appState: AppState, user: AdminUserItem) async {
        if await appState.perform("\(APIPath.adminUsers)/\(user.id)", method: .delete) {
            users.removeAll { $0.id == user.id }
        }
    }

    func resetInvites(_ appState: AppState, count: Int) async -> Bool {
        let saved = await appState.perform(APIPath.adminResetInvite, method: .get, query: ["count": count])
        if saved { await load(appState) }
        return saved
    }
}

struct AdminView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = AdminUsersViewModel()
    @State private var showInvite = false
    @State private var editingUser: AdminUserItem?
    @State private var resettingUser: AdminUserItem?
    @State private var resettingInvitesUser: AdminUserItem?
    @State private var showResetInvites = false
    @State private var deletingUser: AdminUserItem?
    @State private var query = ""
    @State private var page = 1
    @State private var pageSize = 100

    private let pageSizeOptions = [20, 30, 50, 100, 200, 500, 1_000]

    private var filteredUsers: [AdminUserItem] {
        let sorted = model.users.sorted { $0.updatedAt > $1.updatedAt }
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return sorted }
        return sorted.filter {
            $0.email.localizedCaseInsensitiveContains(value)
                || $0.username.localizedCaseInsensitiveContains(value)
                || $0.marked.localizedCaseInsensitiveContains(value)
                || String($0.pay).contains(value)
                || String($0.invite).contains(value)
                || $0.expiresAt.localizedCaseInsensitiveContains(value)
        }
    }

    private var activeUsers: [AdminUserItem] { model.users.filter { !$0.isExpired } }
    private var totalPages: Int { max(1, (filteredUsers.count + pageSize - 1) / pageSize) }
    private var currentPage: Int { min(max(page, 1), totalPages) }
    private var pagedUsers: [AdminUserItem] {
        let start = (currentPage - 1) * pageSize
        guard start < filteredUsers.count else { return [] }
        return Array(filteredUsers[start..<min(start + pageSize, filteredUsers.count)])
    }
    private var pageRangeText: String {
        guard !filteredUsers.isEmpty else { return "0 / 0" }
        let start = (currentPage - 1) * pageSize + 1
        let end = min(currentPage * pageSize, filteredUsers.count)
        return "\(start)-\(end) / \(filteredUsers.count)"
    }
    private var paidUserCount: Int { activeUsers.filter { $0.pay > 0 }.count }
    private var recentUserCount: Int {
        activeUsers.filter {
            guard let date = parseDate($0.updatedAt) else { return false }
            return Date().timeIntervalSince(date) <= 7 * 86_400
        }.count
    }

    var body: some View {
        Group {
            if !appState.canOpenAdminUsers {
                ContentUnavailableView("无权访问", systemImage: "lock.shield", description: Text("当前账号不具备授权管理权限"))
            }
            else if model.isLoading { LoadingState() }
            else {
                List {
                    Section("概览") {
                        LabeledContent("授权用户", value: "\(model.users.count)")
                        LabeledContent("有效 / 过期", value: "\(activeUsers.count) / \(model.users.filter(\.isExpired).count)")
                        LabeledContent("收费 / 免费", value: "\(paidUserCount) / \(activeUsers.count - paidUserCount)")
                        LabeledContent("7 日内更新", value: "\(recentUserCount)")
                        LabeledContent("正式 / 试用", value: "\(model.users.filter { !$0.tryUser }.count) / \(model.users.filter(\.tryUser).count)")
                        LabeledContent("剩余邀请", value: "\(model.users.reduce(0) { $0 + $1.invite })")
                        LabeledContent("累计金额", value: "\(model.users.reduce(0) { $0 + $1.pay })")
                    }
                    Section("授权用户") {
                        if filteredUsers.isEmpty { Text(query.isEmpty ? "没有授权记录" : "没有匹配的授权用户").foregroundStyle(.secondary) }
                        ForEach(pagedUsers) { user in
                            Button { editingUser = user } label: { AdminUserRow(user: user) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingUser = user } label: { Label("编辑授权", systemImage: "pencil") }
                                    Button { resettingUser = user } label: { Label("重置令牌", systemImage: "key.horizontal") }
                                    Button { resettingInvitesUser = user } label: { Label("重置邀请", systemImage: "ticket") }
                                    Button { Task { await model.sendToken(appState, user: user) } } label: { Label("发送令牌邮件", systemImage: "envelope") }
                                    Button(role: .destructive) { deletingUser = user } label: { Label("删除授权", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { resettingUser = user } label: { Label("重置令牌", systemImage: "key.horizontal") }.tint(HarvestTheme.amber)
                                    Button { Task { await model.sendToken(appState, user: user) } } label: { Label("发送邮件", systemImage: "envelope") }.tint(HarvestTheme.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { deletingUser = user } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                    if !filteredUsers.isEmpty {
                        Section("分页") {
                            LabeledContent("显示范围", value: pageRangeText)
                            HStack {
                                Picker("每页数量", selection: $pageSize) {
                                    ForEach(pageSizeOptions, id: \.self) { Text("\($0) 条").tag($0) }
                                }
                                .pickerStyle(.menu)
                                Spacer()
                                Button { page = max(1, currentPage - 1) } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(currentPage <= 1)
                                Text("\(currentPage) / \(totalPages)")
                                    .font(.subheadline.monospacedDigit())
                                    .frame(minWidth: 58)
                                Button { page = min(totalPages, currentPage + 1) } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(currentPage >= totalPages)
                            }
                        }
                    }
                    Section("系统操作") {
                        Button { showInvite = true } label: { Label("邀请用户", systemImage: "envelope.badge.person.crop") }
                        Button { showResetInvites = true } label: { Label("重置邀请码", systemImage: "ticket") }
                        Button { Task { _ = await appState.perform(APIPath.adminCacheClear, method: .get) } } label: { Label("清理版本缓存", systemImage: "shippingbox.and.arrow.backward") }
                    }
                }
                .refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("授权管理").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索邮箱、用户名、备注或授权信息")
        .task { if appState.canOpenAdminUsers && model.isLoading { await model.load(appState) } }
        .onChange(of: query) { _, _ in page = 1 }
        .onChange(of: pageSize) { _, _ in page = 1 }
        .onChange(of: filteredUsers.count) { _, _ in page = currentPage }
        .sheet(isPresented: $showInvite) { InviteSheet { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingUser) { user in AdminUserEditorSheet(user: user) { values in await model.update(appState, user: user, values: values) } }
        .sheet(item: $resettingUser) { user in AdminTokenResetSheet(user: user) { expire, pay, tryUser in await model.resetToken(appState, user: user, expire: expire, pay: pay, tryUser: tryUser) } }
        .sheet(item: $resettingInvitesUser) { user in AdminInviteResetSheet(user: user) { count in await model.update(appState, user: user, values: ["email": user.email, "invite": count]) } }
        .sheet(isPresented: $showResetInvites) { ResetInvitesSheet { count in await model.resetInvites(appState, count: count) } }
        .confirmationDialog(
            "确定删除授权用户「\(privacyMaskedText(deletingUser?.email ?? "", enabled: appState.privacyMode))」？",
            isPresented: Binding(
                get: { deletingUser != nil },
                set: { if !$0 { deletingUser = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除授权", role: .destructive) {
                guard let user = deletingUser else { return }
                deletingUser = nil
                Task { await model.remove(appState, user: user) }
            }
            Button("取消", role: .cancel) { deletingUser = nil }
        }
    }
}

struct AdminUserRow: View {
    @EnvironmentObject private var appState: AppState
    let user: AdminUserItem
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    user.isExpired
                        ? HarvestTheme.coral.opacity(0.14)
                        : user.tryUser ? HarvestTheme.amber.opacity(0.14) : HarvestTheme.green.opacity(0.14)
                )
                .frame(width: 42, height: 42)
                .overlay {
                    Image(
                        systemName: user.isExpired
                            ? "calendar.badge.exclamationmark"
                            : user.tryUser ? "hourglass" : "key.fill"
                    )
                    .foregroundStyle(
                        user.isExpired
                            ? HarvestTheme.coral
                            : user.tryUser ? HarvestTheme.amber : HarvestTheme.green
                    )
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(privacyMaskedText(user.username.isEmpty ? user.email : user.username, enabled: appState.privacyMode)).font(.headline)
                if !user.username.isEmpty {
                    Text(privacyMaskedText(user.email, enabled: appState.privacyMode)).font(.caption).foregroundStyle(.secondary)
                }
                Text(
                    user.expiresAt.isEmpty
                        ? "有效期 \(user.expire) 天"
                        : "\(user.authorizationText) · \(user.expiresAt)"
                )
                .font(.caption2)
                .foregroundStyle(user.isExpired ? HarvestTheme.coral : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(user.invite) 邀请").font(.caption)
                Text(user.isExpired ? "过期" : user.tryUser ? "试用" : user.pay > 0 ? "收费" : "免费")
                    .font(.caption2)
                    .foregroundStyle(
                        user.isExpired
                            ? HarvestTheme.coral
                            : user.tryUser ? HarvestTheme.amber : HarvestTheme.green
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

struct AdminUserEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserItem
    let save: ([String: Any]) async -> Bool
    @State private var username: String
    @State private var email: String
    @State private var pay: String
    @State private var invite: String
    @State private var tryUser: Bool
    @State private var marked: String
    @State private var expire: String

    init(user: AdminUserItem, save: @escaping ([String: Any]) async -> Bool) {
        self.user = user
        self.save = save
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
        _pay = State(initialValue: String(user.pay))
        _invite = State(initialValue: String(user.invite))
        _tryUser = State(initialValue: user.tryUser)
        _marked = State(initialValue: user.marked)
        _expire = State(initialValue: String(user.expire))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") { TextField("用户名", text: $username); TextField("邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("备注", text: $marked) }
                Section("授权") {
                    TextField("支付金额", text: $pay).keyboardType(.numberPad)
                    TextField("邀请码数量", text: $invite).keyboardType(.numberPad)
                    TextField("有效天数", text: $expire).keyboardType(.numberPad)
                    Toggle("试用用户", isOn: $tryUser)
                }
            }
            .navigationTitle("编辑授权").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let body: [String: Any] = [
                                "id": user.id,
                                "username": username,
                                "email": email,
                                "pay": Int(pay) ?? 0,
                                "invite": Int(invite) ?? 0,
                                "try_user": tryUser,
                                "marked": marked,
                                "expire": Int(expire) ?? 0
                            ]
                            if await save(body) { dismiss() }
                        }
                    }
                    .disabled(email.isEmpty)
                }
            }
        }
    }
}

struct AdminTokenResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserItem
    let reset: (Int, Int, Bool) async -> Bool
    @State private var expire: String
    @State private var pay: String
    @State private var tryUser: Bool

    init(user: AdminUserItem, reset: @escaping (Int, Int, Bool) async -> Bool) {
        self.user = user
        self.reset = reset
        _expire = State(initialValue: String(user.expire == 0 ? 36_600 : user.expire))
        _pay = State(initialValue: String(user.pay == 0 ? 168 : user.pay))
        _tryUser = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            Form { TextField("有效天数", text: $expire).keyboardType(.numberPad); TextField("支付金额", text: $pay).keyboardType(.numberPad); Toggle("试用用户", isOn: $tryUser) }
                .navigationTitle("重置令牌").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("重置") {
                            Task {
                                if await reset(Int(expire) ?? 0, Int(pay) ?? 0, tryUser) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled((Int(expire) ?? 0) <= 0 || (Int(pay) ?? 0) <= 0)
                    }
                }
        }
    }
}

struct ResetInvitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reset: (Int) async -> Bool
    @State private var count = "3"
    var body: some View {
        NavigationStack {
            Form { TextField("邀请码数量", text: $count).keyboardType(.numberPad) }
                .navigationTitle("重置邀请码").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("重置") {
                            Task {
                                if await reset(Int(count) ?? 0) { dismiss() }
                            }
                        }
                        .disabled((Int(count) ?? -1) < 0)
                    }
                }
        }
    }
}

struct AdminInviteResetSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserItem
    let reset: (Int) async -> Bool
    @State private var count = "3"

    var body: some View {
        NavigationStack {
            Form {
                Section("授权用户") {
                    LabeledContent("邮箱", value: privacyMaskedText(user.email, enabled: appState.privacyMode))
                }
                Section("邀请数量") {
                    Picker("数量", selection: $count) {
                        Text("3 次").tag("3")
                        Text("4 次").tag("4")
                        Text("5 次").tag("5")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("重置邀请").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("重置") { Task { if await reset(Int(count) ?? 3) { dismiss() } } }
                }
            }
        }
    }
}

struct UserRow: View {
    @EnvironmentObject private var appState: AppState
    let user: ManagedUser
    var isCurrent = false
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(user.active ? HarvestTheme.green.opacity(0.14) : Color.secondary.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay(Text(user.username.isEmpty ? "?" : String(user.username.prefix(1)).uppercased()).font(.headline).foregroundStyle(user.active ? HarvestTheme.green : .secondary))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(privacyMaskedText(user.username.isEmpty ? "未命名用户" : user.username, enabled: appState.privacyMode)).font(.headline)
                    if user.staff { Image(systemName: "person.badge.shield.checkmark").foregroundStyle(HarvestTheme.blue).font(.caption) }
                    if user.admin { Image(systemName: "checkmark.shield.fill").foregroundStyle(HarvestTheme.coral).font(.caption) }
                    if isCurrent { Text("当前").font(.caption2).foregroundStyle(HarvestTheme.green) }
                }
                Text(user.email.isEmpty
                    ? "ID \(user.id)"
                    : "\(privacyMaskedText(user.email, enabled: appState.privacyMode)) · ID \(user.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(label: user.active ? "启用" : "停用", color: user.active ? HarvestTheme.green : .secondary)
        }
        .padding(.vertical, 4)
    }
}

struct UserEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let endpoint: String
    let user: ManagedUser?
    let resetPassword: Bool
    let onSaved: () async -> Void
    @State private var username: String
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validationError: String?
    @State private var isSaving = false

    init(endpoint: String, user: ManagedUser? = nil, resetPassword: Bool = false, onSaved: @escaping () async -> Void) {
        self.endpoint = endpoint
        self.user = user
        self.resetPassword = resetPassword
        self.onSaved = onSaved
        _username = State(initialValue: user?.username ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .disabled(resetPassword)
                SecureField(user == nil ? "初始密码" : "新密码", text: $password)
                SecureField("确认密码", text: $confirmation)
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(HarvestTheme.coral)
                }
            }
            .navigationTitle(user == nil ? "添加用户" : resetPassword ? "重置密码" : "编辑用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(username.isEmpty || password.isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
    }

    @MainActor private func save() async {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty else { validationError = "用户名不能为空"; return }
        guard !password.isEmpty else { validationError = user == nil ? "初始密码不能为空" : "新密码不能为空"; return }
        guard password == confirmation else { validationError = "两次输入的密码不一致"; return }
        validationError = nil
        isSaving = true
        defer { isSaving = false }
        let body: [String: Any] = ["username": normalizedUsername, "password": password]
        let path = user.map { "\(endpoint)/\($0.id)" } ?? endpoint
        let method: HTTPMethod = user == nil ? .post : .put
        if await appState.perform(path, method: method, body: body) {
            await onSaved()
            dismiss()
        }
    }
}

struct InviteSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let notify: Bool
    let onSaved: () async -> Void
    @State private var email = ""
    @State private var isSending = false

    init(notify: Bool = false, onSaved: @escaping () async -> Void) {
        self.notify = notify
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("邀请邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle(notify ? "试用邀请" : "邀请用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { Task { await send() } }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .overlay { if isSending { ProgressView().controlSize(.large) } }
        }
    }

    @MainActor private func send() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        var query: [String: Any] = ["invite_email": address]
        if !notify { query["notify"] = false }
        if await appState.perform(APIPath.adminUsers, method: .post, query: query) {
            await onSaved()
            dismiss()
        }
    }
}

private enum LogSource: String, CaseIterable, Identifiable {
    case app = "APP"
    case server = "服务端"
    var id: String { rawValue }
}

private struct DisplayLogEntry: Identifiable, Hashable {
    let id: String
    let timestamp: String
    let level: String
    let message: String
}

private struct SharedLogArchive: Identifiable {
    let url: URL
    var id: URL { url }
}

struct LogView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("logs.fontSize") private var fontSize = 12.0
    @AppStorage("logs.appThreshold") private var appThresholdRaw = AppLogThreshold.info.rawValue
    @State private var entries: [DisplayLogEntry] = []
    @State private var appAllEntries: [DisplayLogEntry] = []
    @State private var appVisibleStart = 0
    @State private var serverLoadedCount = 0
    @State private var serverTotal = 0
    @State private var isLoadingOlder = false
    @State private var source: LogSource = .app
    @State private var query = ""
    @State private var isLoading = true
    @State private var filterLevel = "ALL"
    @State private var serverLevel = "INFO"
    @State private var connected = false
    @State private var serverStreamStatus = "快照数据"
    @State private var streamRestartGeneration = 0
    @State private var paused = false
    @State private var following = true
    @State private var sharedArchive: SharedLogArchive?

    private let filterLevels = ["ALL", "VERBOSE", "DEBUG", "INFO", "WARN", "ERROR"]
    private let serverLevels = ["DEBUG", "INFO", "WARN", "ERROR"]
    private let pageSize = 100
    private let minimumFontSize = 8.0
    private let maximumFontSize = 16.0

    private var displayedFontSize: Double {
        min(maximumFontSize, max(minimumFontSize, fontSize))
    }

    private var filtered: [DisplayLogEntry] {
        entries.filter { entry in
            guard selectedLogLevelMatches(entry.level) else { return false }
            guard !query.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(query)
                || entry.level.localizedCaseInsensitiveContains(query)
                || entry.timestamp.localizedCaseInsensitiveContains(query)
        }
    }

    private var hasOlder: Bool {
        source == .app ? appVisibleStart > 0 : serverLoadedCount < serverTotal
    }

    var body: some View {
        let visibleEntries = filtered
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Picker("日志来源", selection: $source) {
                        ForEach(LogSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        StatusPill(
                            label: paused ? "已暂停" : (source == .app ? "本地日志" : (connected ? "实时连接" : serverStreamStatus)),
                            color: paused ? HarvestTheme.amber : (source == .app || connected ? HarvestTheme.green : HarvestTheme.amber)
                        )
                        Button {
                            following.toggle()
                            if following { scrollToBottom(proxy) }
                        } label: {
                            Label(following ? "跟随最新" : "暂停跟随", systemImage: following ? "arrow.down.to.line" : "hand.raised")
                        }
                        .font(.caption)
                        Spacer()
                        Picker("内容筛选", selection: $filterLevel) {
                            ForEach(filterLevels, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if source == .app {
                            Picker("APP 级别", selection: $appThresholdRaw) {
                                ForEach(AppLogThreshold.allCases) { level in
                                    Text(level.label).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Picker("服务级别", selection: $serverLevel) {
                                ForEach(serverLevels, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                if isLoading {
                    LoadingState()
                } else if visibleEntries.isEmpty {
                    EmptyState(icon: "doc.text", title: query.isEmpty ? "没有日志" : "没有匹配日志")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if hasOlder {
                            Button { Task { await loadOlder() } } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingOlder { ProgressView().controlSize(.small) }
                                    Label("加载更早日志", systemImage: "arrow.up.to.line")
                                    Spacer()
                                }
                            }
                            .disabled(isLoadingOlder)
                        }
                        ForEach(visibleEntries) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.level)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(logColor(entry.level))
                                    Spacer()
                                    Text(entry.timestamp).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Text(entry.message)
                                    .font(.system(size: displayedFontSize, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .onChange(of: entries.count) { _, _ in
                if following { scrollToBottom(proxy) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(paused ? "继续接收日志" : "暂停接收日志")

                    Menu {
                        Button { scrollToTop(proxy) } label: { Label("到顶部", systemImage: "arrow.up.to.line") }
                        Button {
                            following = true
                            scrollToBottom(proxy)
                        } label: { Label("到底部", systemImage: "arrow.down.to.line") }
                        Divider()
                        Button { copyPrivateText(logText) } label: { Label("复制当前日志", systemImage: "doc.on.doc") }
                            .disabled(entries.isEmpty)
                        Button { Task { await clearCurrent() } } label: { Label("清空当前视图", systemImage: "trash") }
                            .disabled(entries.isEmpty)
                        Button {
                            if source == .server {
                                streamRestartGeneration &+= 1
                            } else {
                                Task { await reload() }
                            }
                        } label: {
                            Label(source == .server ? "重新连接" : "重载", systemImage: "arrow.clockwise")
                        }
                        Divider()
                        Button { fontSize = max(minimumFontSize, displayedFontSize - 1) } label: { Label("减小字号", systemImage: "minus") }
                            .disabled(displayedFontSize <= minimumFontSize)
                        Button { fontSize = min(maximumFontSize, displayedFontSize + 1) } label: { Label("增大字号", systemImage: "plus") }
                            .disabled(displayedFontSize >= maximumFontSize)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("日志工具")

                    Button { Task { await shareAppLogs() } } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("打包分享 APP 日志")
                }
            }
        }
        .searchable(text: $query, prompt: "筛选日志")
        .sheet(item: $sharedArchive) { archive in ActivityShareSheet(items: [archive.url]) }
        .navigationTitle("日志中心")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(source.rawValue)-\(serverLevel)-\(streamRestartGeneration)") {
            entries = []
            appAllEntries = []
            appVisibleStart = 0
            serverLoadedCount = 0
            serverTotal = 0
            isLoading = true
            connected = false
            serverStreamStatus = "快照数据"
            await load()
            guard !paused else { return }
            if source == .app { await watchAppLogs() }
            else { await watchServerLogs() }
        }
        .onChange(of: paused) { _, isPaused in
            if isPaused { serverStreamStatus = "已暂停" }
            streamRestartGeneration &+= 1
        }
        .onChange(of: appThresholdRaw) { _, rawValue in
            let threshold = AppLogThreshold(rawValue: rawValue) ?? .info
            if threshold.rawValue != rawValue { appThresholdRaw = threshold.rawValue }
            recordAppLog(.info, "APP 日志级别已切换为：\(threshold.label)")
        }
    }

    private func load() async {
        defer { isLoading = false }
        if source == .app {
            await loadAppLogs(resetWindow: true)
            connected = true
            return
        }
        do {
            let page = try await fetchServerPage(offset: 0)
            entries = page.entries
            serverLoadedCount = page.count
            serverTotal = page.total
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    private func reload() async {
        isLoading = entries.isEmpty
        await load()
    }

    private func loadAppLogs(resetWindow: Bool = false) async {
        let records = await AppLogStore.shared.snapshot()
        let next = records.map {
                DisplayLogEntry(
                    id: $0.id.uuidString,
                    timestamp: $0.timestamp.formatted(date: .numeric, time: .standard),
                    level: $0.level.rawValue,
                    message: $0.message
                )
            }
        if resetWindow || appAllEntries.isEmpty {
            appAllEntries = next
            appVisibleStart = max(0, next.count - pageSize)
            entries = Array(next.suffix(pageSize))
            return
        }

        let previousCount = appAllEntries.count
        let samePrefix = next.count >= previousCount
            && Array(next.prefix(previousCount)) == appAllEntries
        appAllEntries = next
        if samePrefix {
            entries.append(contentsOf: next.dropFirst(previousCount))
        } else {
            let visibleCount = min(max(entries.count, pageSize), next.count)
            appVisibleStart = max(0, next.count - visibleCount)
            entries = Array(next.suffix(visibleCount))
        }
    }

    private func watchAppLogs() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            guard !Task.isCancelled else { return }
            if !paused { await loadAppLogs() }
        }
    }

    private func fetchServerPage(offset: Int) async throws -> (entries: [DisplayLogEntry], count: Int, total: Int) {
        let raw = try await appState.api(
            APIPath.logs,
            query: ["limit": pageSize, "offset": offset, "level": serverLevel]
        )
        let payload = jsonPayloadDictionary(raw) ?? [:]
        let rows: [[String: Any]]
        if let values = payload["items"] as? [[String: Any]] {
            rows = values
        } else {
            rows = jsonRows(raw)
        }
        return (
            displayEntries(Array(rows.reversed())),
            rows.count,
            payload.int("total") ?? rows.count
        )
    }

    @MainActor private func loadOlder() async {
        guard hasOlder, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        if source == .app {
            let nextStart = max(0, appVisibleStart - pageSize)
            entries.insert(contentsOf: appAllEntries[nextStart..<appVisibleStart], at: 0)
            appVisibleStart = nextStart
            following = false
            return
        }

        do {
            let page = try await fetchServerPage(offset: serverLoadedCount)
            let known = Set(entries.map(\.id))
            entries.insert(contentsOf: page.entries.filter { !known.contains($0.id) }, at: 0)
            serverLoadedCount += page.count
            serverTotal = page.total
            following = false
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    private func watchServerLogs() async {
        let maximumReconnectAttempts = 3
        var reconnectAttempt = 0
        while !Task.isCancelled {
            var receivedFrame = false
            var disconnectMessage = "日志流已断开"
            do {
                let stream = APIClient.shared.streamSSE(
                    baseURL: appState.baseURL,
                    path: APIPath.logsStream,
                    token: appState.accessToken,
                    method: .get,
                    query: ["level": serverLevel, "limit": pageSize]
                )
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    if !receivedFrame {
                        receivedFrame = true
                        reconnectAttempt = 0
                    }
                    connected = true
                    serverStreamStatus = "实时连接"
                    let payload = jsonPayloadDictionary(event) ?? event
                    let type = payload.string("type")?.lowercased() ?? ""
                    if type == "heartbeat" || type == "connected" { connected = true; continue }
                    guard !paused else { continue }
                    var rows = payload.rows("entries", "logs", "rows")
                    if rows.isEmpty, payload.string("display", "raw", "message", "text", "detail") != nil {
                        rows = [payload]
                    }
                    guard !rows.isEmpty else { continue }
                    let next = displayEntries(rows)
                    let known = Set(entries.map(\.id))
                    let additions = next.filter { !known.contains($0.id) }
                    if type == "snapshot" && entries.isEmpty { entries = next }
                    else { entries.append(contentsOf: additions) }
                    serverLoadedCount += additions.count
                    serverTotal = max(serverTotal, serverLoadedCount)
                }
            } catch {
                disconnectMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            connected = false
            if receivedFrame { reconnectAttempt = 0 }
            guard reconnectAttempt < maximumReconnectAttempts else {
                serverStreamStatus = "重连已停止"
                await AppLogStore.shared.append(
                    .warning,
                    "服务端日志流断开：\(disconnectMessage)，连续重试 \(maximumReconnectAttempts) 次失败，已停止连接"
                )
                return
            }
            reconnectAttempt += 1
            serverStreamStatus = "重连 \(reconnectAttempt)/\(maximumReconnectAttempts)"
            await AppLogStore.shared.append(
                .warning,
                "服务端日志流断开：\(disconnectMessage)，3 秒后重连（\(reconnectAttempt)/\(maximumReconnectAttempts)）"
            )
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
        }
    }

    private func displayEntries(_ rows: [[String: Any]]) -> [DisplayLogEntry] {
        rows.map { entry in
            let timestamp = entry.string("timestamp", "logged_at", "time", "created_at", "date") ?? ""
            let entryLevel = (entry.string("level", "type") ?? "INFO").uppercased()
            let message = entry.string("display", "raw", "message", "text", "detail") ?? prettyJSON(entry)
            return DisplayLogEntry(
                id: entry.string("id", "uuid") ?? "\(timestamp)|\(entryLevel)|\(message)",
                timestamp: timestamp,
                level: entryLevel,
                message: message
            )
        }
    }

    private func clearCurrent() async {
        if source == .app {
            appVisibleStart = appAllEntries.count
        } else {
            serverLoadedCount = 0
        }
        entries = []
    }

    @MainActor private func shareAppLogs() async {
        do {
            sharedArchive = SharedLogArchive(url: try await AppLogStore.shared.exportArchive())
        } catch {
            appState.presentedError = "打包 APP 日志失败：\(error.localizedDescription)"
        }
    }

    private var logText: String {
        entries.map { "[\($0.timestamp)] [\($0.level)] \($0.message)" }.joined(separator: "\n")
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let id = filtered.first?.id else { return }
        following = false
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = filtered.last?.id else { return }
        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func logColor(_ level: String) -> Color {
        let text = level.lowercased()
        if text.contains("error") || text.contains("fatal") { return HarvestTheme.coral }
        if text.contains("warn") { return HarvestTheme.amber }
        if text.contains("debug") { return HarvestTheme.blue }
        if text.contains("verbose") || text.contains("trace") { return Color(red: 0.48, green: 0.42, blue: 0.62) }
        return HarvestTheme.green
    }

    private func selectedLogLevelMatches(_ candidate: String) -> Bool {
        guard filterLevel != "ALL" else { return true }
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if filterLevel == "VERBOSE" { return normalized == "VERBOSE" || normalized == "TRACE" }
        if filterLevel == "WARN" { return normalized == "WARN" || normalized == "WARNING" }
        return normalized == filterLevel
    }
}

struct BrowserStorageSnapshot {
    let cookie: String
    let localStorage: String
    let localStorageItemCount: Int
}

struct BrowserTorrentRequest: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

private func browserTorrentRequest(
    url: URL?,
    mimeType: String? = nil,
    contentDisposition: String? = nil,
    suggestedFileName: String? = nil
) -> BrowserTorrentRequest? {
    guard let url else { return nil }
    let value = url.absoluteString.lowercased()
    let path = url.path.lowercased()
    let mime = mimeType?.lowercased() ?? ""
    let disposition = contentDisposition?.lowercased() ?? ""
    let fileName = suggestedFileName?.lowercased() ?? ""
    let isTorrent = url.scheme?.lowercased() == "magnet"
        || path.hasSuffix(".torrent")
        || value.contains(".torrent?")
        || mime.contains("bittorrent")
        || disposition.contains(".torrent")
        || fileName.hasSuffix(".torrent")
    return isTorrent ? BrowserTorrentRequest(url: url) : nil
}

@MainActor
final class BrowserSessionModel: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var loadProgress = 0.0
    @Published private(set) var loadError: String?
    @Published var pendingTorrent: BrowserTorrentRequest?
    weak var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?

    func attach(_ webView: WKWebView) {
        if self.webView !== webView {
            progressObservation?.invalidate()
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                self?.refreshProgress(view)
            }
        }
        self.webView = webView
        refreshState(webView)
    }

    func refreshState(_ webView: WKWebView? = nil) {
        guard let view = webView ?? self.webView else { return }
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        currentURL = view.url
        isLoading = view.isLoading
        refreshProgress(view)
    }

    private func refreshProgress(_ webView: WKWebView) {
        let progress = min(max(webView.estimatedProgress, 0), 1)
        loadProgress = webView.isLoading ? min(max(progress, 0.02), 0.995) : 1
    }

    func goBack() {
        loadError = nil
        webView?.goBack()
    }

    func goForward() {
        loadError = nil
        webView?.goForward()
    }

    func reload() {
        loadError = nil
        webView?.reload()
    }

    func setUserAgent(_ value: String?) {
        loadError = nil
        webView?.customUserAgent = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        webView?.reload()
    }

    func load(_ url: URL) {
        loadError = nil
        webView?.load(URLRequest(url: url))
    }

    func loadAndWait(_ url: URL, timeout: TimeInterval = 15) async throws {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        let previousURL = webView.url
        load(url)
        let deadline = Date().addingTimeInterval(timeout)
        var navigationStarted = false
        while Date() < deadline {
            try Task.checkCancellation()
            if webView.isLoading || webView.url != previousURL { navigationStarted = true }
            if navigationStarted, !webView.isLoading, webView.url != nil {
                refreshState(webView)
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw APIError(statusCode: 0, message: "目标页面加载超时")
    }

    func navigationStarted(_ webView: WKWebView) {
        loadError = nil
        refreshState(webView)
    }

    func navigationFinished(_ webView: WKWebView) {
        loadError = nil
        refreshState(webView)
    }

    func navigationFailed(_ webView: WKWebView, error: Error) {
        let nsError = error as NSError
        let cancelledRequest = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        let interruptedByPolicy = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
        if cancelledRequest || interruptedByPolicy {
            refreshState(webView)
            return
        }
        loadError = error.localizedDescription
        refreshState(webView)
    }

    func interceptTorrent(_ request: BrowserTorrentRequest) {
        pendingTorrent = request
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        return try await webView.evaluateJavaScript(script)
    }

    func callAsyncJavaScript(_ script: String) async throws -> Any? {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        return try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func captureStorage(allowEmpty: Bool = false) async throws -> BrowserStorageSnapshot {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        let host = webView.url?.host?.lowercased() ?? ""
        let allCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let cookieText = allCookies
            .filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix("." + domain)
            }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        let script = "JSON.stringify({ values: Object.fromEntries(Object.entries(window.localStorage)), count: window.localStorage.length })"
        let result = try await webView.evaluateJavaScript(script)
        let localStoragePayload: [String: Any]
        if let text = result as? String,
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            localStoragePayload = dictionary
        } else {
            localStoragePayload = [:]
        }
        let localStorageValues: [String: Any]
        if let dictionary = localStoragePayload["values"] as? [String: Any] {
            localStorageValues = dictionary
        } else if let dictionary = localStoragePayload["values"] as? NSDictionary {
            localStorageValues = dictionary.reduce(into: [String: Any]()) { result, entry in
                result[String(describing: entry.key)] = entry.value
            }
        } else {
            localStorageValues = [:]
        }
        let localStorageText: String
        if localStorageValues.isEmpty {
            localStorageText = ""
        } else if let data = try? JSONSerialization.data(withJSONObject: localStorageValues, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) {
            localStorageText = text
        } else {
            localStorageText = ""
        }
        let itemCount = (localStoragePayload["count"] as? NSNumber)?.intValue ?? localStorageValues.count
        guard allowEmpty || !cookieText.isEmpty || !localStorageText.isEmpty else {
            throw APIError(statusCode: 0, message: "当前页面没有可同步的 Cookie 或 LocalStorage")
        }
        return BrowserStorageSnapshot(
            cookie: cookieText,
            localStorage: localStorageText,
            localStorageItemCount: itemCount
        )
    }

    func captureLongScreenshot() async throws -> UIImage {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        guard webView.bounds.width > 0, webView.bounds.height > 0 else {
            throw APIError(statusCode: 0, message: "网页尚未完成布局")
        }

        let metricsScript = """
        JSON.stringify({
          scrollY: window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0,
          viewportHeight: window.innerHeight || document.documentElement.clientHeight || document.body.clientHeight || 0,
          contentHeight: Math.max(
            document.body ? document.body.scrollHeight : 0,
            document.documentElement ? document.documentElement.scrollHeight : 0,
            document.body ? document.body.offsetHeight : 0,
            document.documentElement ? document.documentElement.offsetHeight : 0
          )
        })
        """
        let rawMetrics = try? await webView.evaluateJavaScript(metricsScript)
        let metrics: [String: Any]
        if let text = rawMetrics as? String,
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            metrics = dictionary
        } else {
            metrics = [:]
        }
        let viewportHeight = (metrics["viewportHeight"] as? NSNumber)?.doubleValue ?? Double(webView.bounds.height)
        let contentHeight = (metrics["contentHeight"] as? NSNumber)?.doubleValue
            ?? Double(max(webView.scrollView.contentSize.height, webView.bounds.height))
        let originalOffset = (metrics["scrollY"] as? NSNumber)?.doubleValue
            ?? Double(webView.scrollView.contentOffset.y)
        guard viewportHeight > 0, contentHeight > 0 else { return try await captureVisibleSnapshot(webView) }

        let estimatedPointScale = Double(webView.bounds.height) / viewportHeight
        let maximumContentHeight = 60_000 / (Double(max(UIScreen.main.scale, 1)) * max(estimatedPointScale, 0.01))
        let capturedContentHeight = min(contentHeight, maximumContentHeight)
        let maxScroll = max(0, capturedContentHeight - viewportHeight)
        let step = max(1, viewportHeight * 0.85)
        var offsets = [0.0]
        var next = 0.0
        while next < maxScroll, offsets.count < 200 {
            next = min(maxScroll, next + step)
            if abs((offsets.last ?? 0) - next) < 1 { break }
            offsets.append(next)
        }

        var pieces: [(image: UIImage, offset: Double)] = []
        let safeOriginalOffset = max(0, clampedInt(originalOffset))
        defer {
            webView.evaluateJavaScript("window.scrollTo(0, \(safeOriginalOffset));", completionHandler: nil)
        }
        for offset in offsets {
            try Task.checkCancellation()
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, \(max(0, clampedInt(offset)))); true;")
            try await Task.sleep(for: .milliseconds(300))
            pieces.append((try await captureVisibleSnapshot(webView), offset))
        }
        guard let first = pieces.first else { return try await captureVisibleSnapshot(webView) }

        let pointScale = Double(first.image.size.height) / max(viewportHeight, 1)
        let maximumPointHeight = 60_000 / Double(max(first.image.scale, 1))
        let outputHeight = CGFloat(min(maximumPointHeight, max(1, capturedContentHeight * pointScale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = first.image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: first.image.size.width, height: outputHeight),
            format: format
        ).image { context in
            context.cgContext.setFillColor(UIColor.systemBackground.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: first.image.size.width, height: outputHeight))
            for piece in pieces {
                let y = CGFloat(piece.offset * pointScale)
                guard y < outputHeight else { continue }
                let height = min(piece.image.size.height, outputHeight - y)
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: y, width: first.image.size.width, height: height))
                piece.image.draw(
                    in: CGRect(x: 0, y: y, width: first.image.size.width, height: piece.image.size.height),
                    blendMode: .copy,
                    alpha: 1
                )
                context.cgContext.restoreGState()
            }
        }
    }

    private func captureVisibleSnapshot(_ webView: WKWebView) async throws -> UIImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? APIError(statusCode: 0, message: "网页截图失败")) }
            }
        }
    }

    func clearCurrentSiteData() async throws {
        guard let webView else { throw APIError(statusCode: 0, message: "浏览器尚未加载") }
        let host = webView.url?.host?.lowercased() ?? ""
        guard !host.isEmpty else { throw APIError(statusCode: 0, message: "当前站点地址无效") }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if host == domain || host.hasSuffix("." + domain) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.delete(cookie) { continuation.resume() }
                }
            }
        }
        _ = try? await webView.callAsyncJavaScript(
            """
            try { window.localStorage.clear(); } catch (_) {}
            try { window.sessionStorage.clear(); } catch (_) {}
            try {
              if (typeof caches !== 'undefined') {
                const keys = await caches.keys();
                await Promise.all(keys.map((key) => caches.delete(key)));
              }
            } catch (_) {}
            try {
              if (typeof indexedDB !== 'undefined' && typeof indexedDB.databases === 'function') {
                const databases = await indexedDB.databases();
                for (const database of databases) {
                  if (database && database.name) indexedDB.deleteDatabase(database.name);
                }
              }
            } catch (_) {}
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        let dataStore = webView.configuration.websiteDataStore
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) {
                continuation.resume(returning: $0)
            }
        }
        let matchingRecords = records.filter { record in
            let name = record.displayName.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return name == host || host.hasSuffix("." + name) || name.hasSuffix("." + host)
        }
        if !matchingRecords.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                dataStore.removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    for: matchingRecords
                ) {
                    continuation.resume()
                }
            }
        }

        webView.configuration.userContentController.removeAllUserScripts()
        webView.reload()
    }
}

struct NativeBrowserView: UIViewRepresentable {
    let urlString: String
    let title: String
    let cookie: String
    let localStorage: String
    let userAgent: String
    let localStorageURLs: [String]
    let installsLocalStorageAuthBridge: Bool
    let session: BrowserSessionModel?

    init(
        urlString: String,
        title: String,
        cookie: String = "",
        localStorage: String = "",
        userAgent: String = "",
        localStorageURLs: [String] = [],
        installsLocalStorageAuthBridge: Bool = false,
        session: BrowserSessionModel? = nil
    ) {
        self.urlString = urlString
        self.title = title
        self.cookie = cookie
        self.localStorage = localStorage
        self.userAgent = userAgent
        self.localStorageURLs = localStorageURLs
        self.installsLocalStorageAuthBridge = installsLocalStorageAuthBridge
        self.session = session
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, allowedHosts: browserAllowedHosts())
    }

    func makeUIView(context: Context) -> WKWebView {
        excludeBrowserStorageFromBackup()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if let script = localStorageScript() {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            context.coordinator.localStorageScript = script
        }

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        session?.attach(view)
        if !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            view.customUserAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let url = URL(string: urlString), let host = url.host else { return view }

        let request = URLRequest(url: url)
        let cookies = browserCookies(host: host, secure: url.scheme?.lowercased() == "https")
        guard !cookies.isEmpty else {
            view.load(request)
            return view
        }

        let group = DispatchGroup()
        let store = configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak view] in view?.load(request) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.allowedHosts = browserAllowedHosts()
        session?.attach(uiView)
        let nextScript = localStorageScript()
        guard context.coordinator.localStorageScript != nextScript else { return }
        context.coordinator.localStorageScript = nextScript
        uiView.configuration.userContentController.removeAllUserScripts()
        if let nextScript {
            uiView.configuration.userContentController.addUserScript(
                WKUserScript(source: nextScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        if uiView.url != nil { uiView.reload() }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var session: BrowserSessionModel?
        var localStorageScript: String?
        var allowedHosts: Set<String>

        init(session: BrowserSessionModel?, allowedHosts: Set<String>) {
            self.session = session
            self.allowedHosts = allowedHosts
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            session?.navigationStarted(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
            session?.refreshState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            session?.navigationFinished(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            session?.navigationFailed(webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            session?.navigationFailed(webView, error: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
            session?.refreshState(webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let request = browserTorrentRequest(url: navigationAction.request.url) {
                session?.interceptTorrent(request)
                decisionHandler(.cancel)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "data", "blob"].contains(scheme) {
                decisionHandler(.allow)
                return
            }
            if scheme == "http" || scheme == "https" {
                let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
                guard !isMainFrame || isAllowedNavigation(url) else {
                    if navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
                        openExternally(url)
                    }
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }
            openExternally(url)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let response = navigationResponse.response
            let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
            if let request = browserTorrentRequest(
                url: response.url,
                mimeType: response.mimeType,
                contentDisposition: disposition,
                suggestedFileName: response.suggestedFilename
            ) {
                session?.interceptTorrent(request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if let request = browserTorrentRequest(url: url) {
                session?.interceptTorrent(request)
            } else if isAllowedNavigation(url) {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
            return nil
        }

        private func isAllowedNavigation(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
            return allowedHosts.contains { allowed in
                host == allowed || host.hasSuffix(".\(allowed)")
            }
        }

        private func openExternally(_ url: URL) {
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let presenter = presentationController(for: webView) else {
                completionHandler()
                return
            }
            let alert = UIAlertController(
                title: webDialogTitle(for: frame, fallback: webView),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let presenter = presentationController(for: webView) else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(
                title: webDialogTitle(for: frame, fallback: webView),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let presenter = presentationController(for: webView) else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(
                title: webDialogTitle(for: frame, fallback: webView),
                message: prompt,
                preferredStyle: .alert
            )
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }

        private func webDialogTitle(for frame: WKFrameInfo, fallback webView: WKWebView) -> String {
            frame.request.url?.host ?? webView.url?.host ?? "网页提示"
        }

        private func presentationController(for webView: WKWebView) -> UIViewController? {
            var controller = webView.window?.rootViewController
            var advanced = true
            while advanced {
                advanced = false
                if let presented = controller?.presentedViewController {
                    controller = presented
                    advanced = true
                } else if let navigation = controller as? UINavigationController,
                          let visible = navigation.visibleViewController {
                    controller = visible
                    advanced = true
                } else if let tabs = controller as? UITabBarController,
                          let selected = tabs.selectedViewController {
                    controller = selected
                    advanced = true
                }
            }
            return controller
        }
    }

    private func browserCookies(host: String, secure: Bool) -> [HTTPCookie] {
        cookie.split(separator: ";").compactMap { pair in
            let text = String(pair).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = text.firstIndex(of: "=") else { return nil }
            let name = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value
            ]
            if secure { properties[.secure] = "TRUE" }
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            return HTTPCookie(properties: properties)
        }
    }

    private func excludeBrowserStorageFromBackup() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for component in ["WebKit", "Cookies"] {
            var url = library.appendingPathComponent(component, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    private func browserAllowedHosts() -> Set<String> {
        var allowedHosts: Set<String> = []
        for value in [urlString] + localStorageURLs {
            guard let host = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased(),
                  !host.isEmpty else { continue }
            allowedHosts.insert(host)
            if host.hasPrefix("www.") { allowedHosts.insert(String(host.dropFirst(4))) }
            if host.hasPrefix("m.") { allowedHosts.insert(String(host.dropFirst(2))) }
        }
        return allowedHosts
    }

    private func localStorageScript() -> String? {
        let storage = localStorage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storage.isEmpty, let storageLiteral = javaScriptLiteral(storage) else { return nil }

        let allowedHosts = browserAllowedHosts()
        guard !allowedHosts.isEmpty,
              let hostsData = try? JSONSerialization.data(withJSONObject: allowedHosts.sorted()),
              let hostsLiteral = String(data: hostsData, encoding: .utf8) else { return nil }
        var authHosts = allowedHosts
        if allowedHosts.contains(where: { $0.contains("m-team") || $0.contains("mteam") }) {
            authHosts.insert("api.m-team.cc")
            authHosts.insert("api2.m-team.cc")
        }
        guard let authHostsData = try? JSONSerialization.data(withJSONObject: authHosts.sorted()),
              let authHostsLiteral = String(data: authHostsData, encoding: .utf8) else { return nil }
        let authBridge = installsLocalStorageAuthBridge ? "true" : "false"
        return """
        (() => {
          const allowedHosts = new Set(\(hostsLiteral));
          if (!allowedHosts.has(window.location.hostname.toLowerCase())) return 0;
          const marker = '__harvest_local_storage_injected__';
          try {
            if (window.sessionStorage.getItem(marker) === 'cleared') return 0;
          } catch (_) {}
          const raw = \(storageLiteral);
          const setItem = (key, value) => {
            if (key === undefined || key === null || String(key).length === 0) return 0;
            const text = typeof value === 'object' && value !== null ? JSON.stringify(value) : String(value ?? '');
            window.localStorage.setItem(String(key), text);
            return 1;
          };
          const applyObject = (data) => {
            let count = 0;
            if (Array.isArray(data)) {
              data.forEach((item) => { if (Array.isArray(item) && item.length >= 2) count += setItem(item[0], item[1]); });
            } else if (data && typeof data === 'object') {
              Object.keys(data).forEach((key) => { count += setItem(key, data[key]); });
            }
            return count;
          };
          const applyText = (text) => {
            let count = 0;
            text.split(';').forEach((part) => {
              const index = part.indexOf('=');
              if (index > 0) count += setItem(part.slice(0, index).trim(), part.slice(index + 1).trim());
            });
            return count;
          };
          const text = String(raw).trim();
          let count = 0;
          if (text.startsWith('{') || text.startsWith('[')) {
            try { count = applyObject(JSON.parse(text)); } catch (_) { count = applyText(text); }
          } else {
            count = applyText(text);
          }
          if (count > 0) {
            try { window.sessionStorage.setItem(marker, 'injected'); } catch (_) {}
          }

          const installAuthBridge = \(authBridge);
          if (installAuthBridge && !window.__harvest_api_auth_bridge_installed__) {
            window.__harvest_api_auth_bridge_installed__ = true;
            const tokenFromStorage = () => {
              for (const key of ['auth', 'token', 'accessToken', 'access_token', 'jwt']) {
                try {
                  const value = window.localStorage.getItem(key);
                  if (value && String(value).trim()) return String(value).trim();
                } catch (_) {}
              }
              return '';
            };
            const authHeader = () => {
              const token = tokenFromStorage();
              if (!token) return '';
              return token.toLowerCase().startsWith('bearer ') ? token : 'Bearer ' + token;
            };
            const apiHosts = new Set(\(authHostsLiteral));
            const shouldAttachAuth = (value) => {
              if (!value) return false;
              try {
                const url = new URL(String(value), window.location.href);
                return url.protocol === 'https:' && apiHosts.has(url.hostname.toLowerCase());
              } catch (_) { return false; }
            };

            if (typeof window.fetch === 'function') {
              const nativeFetch = window.fetch.bind(window);
              window.fetch = (input, init) => {
                try {
                  const target = input && typeof input === 'object' && 'url' in input ? input.url : input;
                  const headerValue = authHeader();
                  if (!headerValue || !shouldAttachAuth(target)) return nativeFetch(input, init);
                  const headers = new Headers(typeof Request !== 'undefined' && input instanceof Request ? input.headers : undefined);
                  if (init && init.headers) new Headers(init.headers).forEach((value, key) => headers.set(key, value));
                  if (!headers.has('authorization')) headers.set('Authorization', headerValue);
                  return nativeFetch(input, Object.assign({}, init || {}, { headers }));
                } catch (_) { return nativeFetch(input, init); }
              };
            }

            const xhr = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
            if (xhr && xhr.open && xhr.send && xhr.setRequestHeader) {
              const nativeOpen = xhr.open;
              const nativeSend = xhr.send;
              const nativeSetRequestHeader = xhr.setRequestHeader;
              xhr.open = function(method, url) {
                this.__harvest_auth_url = url;
                this.__harvest_has_auth_header = false;
                return nativeOpen.apply(this, arguments);
              };
              xhr.setRequestHeader = function(name, value) {
                if (String(name || '').toLowerCase() === 'authorization') this.__harvest_has_auth_header = true;
                return nativeSetRequestHeader.apply(this, arguments);
              };
              xhr.send = function() {
                try {
                  const headerValue = authHeader();
                  if (headerValue && !this.__harvest_has_auth_header && shouldAttachAuth(this.__harvest_auth_url)) {
                    nativeSetRequestHeader.call(this, 'Authorization', headerValue);
                  }
                } catch (_) {}
                return nativeSend.apply(this, arguments);
              };
            }
          }
          return count;
        })();
        """
    }

    private func javaScriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
