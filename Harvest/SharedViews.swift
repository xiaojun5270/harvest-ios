import Foundation
import CryptoKit
import ImageIO
import SwiftUI
import UIKit

actor RemoteImageDataCache {
    static let shared = RemoteImageDataCache()

    private let memoryCache: NSCache<NSString, NSData>
    private let diskCache: URLCache
    private let persistentImageDirectory: URL?
    private let session: URLSession
    private let privateSession: URLSession
    private var inFlight: [String: Task<Data, Error>] = [:]

    private init() {
        let memory = NSCache<NSString, NSData>()
        memory.totalCostLimit = 48 * 1_024 * 1_024
        memory.countLimit = 240
        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 192 * 1_024 * 1_024,
            diskPath: "harvest-public-images-v2"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let publicSession = URLSession(configuration: configuration)
        let privateConfiguration = URLSessionConfiguration.ephemeral
        privateConfiguration.urlCache = nil
        privateConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        privateConfiguration.timeoutIntervalForRequest = 20
        privateConfiguration.timeoutIntervalForResource = 45
        privateConfiguration.waitsForConnectivity = true
        privateConfiguration.httpShouldSetCookies = false
        privateConfiguration.httpCookieStorage = nil
        let persistentDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("HarvestPersistentImages", isDirectory: true)
        if let persistentDirectory {
            try? FileManager.default.createDirectory(
                at: persistentDirectory,
                withIntermediateDirectories: true
            )
        }
        memoryCache = memory
        diskCache = cache
        persistentImageDirectory = persistentDirectory
        session = publicSession
        privateSession = URLSession(configuration: privateConfiguration)
    }

    func data(
        for url: URL,
        headers: [String: String] = [:],
        persistentCacheID: String? = nil
    ) async throws -> Data {
        guard let normalizedURL = URL(string: normalizedRemoteImageURL(url.absoluteString)) else {
            throw APIError(statusCode: 0, message: "图片地址无效")
        }
        let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: headers)
        let key = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders)
        let cacheKey = key as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            if let persistentCacheID {
                storePersistentData(cached as Data, for: persistentCacheID)
            }
            return cached as Data
        }
        if let persistentCacheID, let cached = persistentData(for: persistentCacheID) {
            memoryCache.setObject(cached as NSData, forKey: cacheKey, cost: cached.count)
            return cached
        }

        let persistToDisk = isPublicCacheURL(normalizedURL) && !hasSensitiveImageHeaders(effectiveHeaders)
        let cachePolicy: URLRequest.CachePolicy = persistToDisk ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData
        var request = URLRequest(url: normalizedURL, cachePolicy: cachePolicy, timeoutInterval: 20)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        for (name, value) in effectiveHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if persistToDisk, let cached = diskCache.cachedResponse(for: request) {
            let isSuccessful = (cached.response as? HTTPURLResponse).map {
                (200..<300).contains($0.statusCode)
            } ?? true
            let isNotHTML = !((cached.response.mimeType ?? "").lowercased().contains("html"))
            if isSuccessful, isNotHTML, !cached.data.isEmpty {
                if let persistentCacheID {
                    storePersistentData(cached.data, for: persistentCacheID)
                }
                memoryCache.setObject(cached.data as NSData, forKey: cacheKey, cost: cached.data.count)
                return cached.data
            }
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        if let task = inFlight[key] {
            let data = try await task.value
            if let persistentCacheID {
                storePersistentData(data, for: persistentCacheID)
            }
            return data
        }

        let task = Task<Data, Error> {
            let activeSession = persistToDisk ? session : privateSession
            let (data, response) = try await activeSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError(statusCode: http.statusCode, message: "图片加载失败（\(http.statusCode)）")
            }
            if let mimeType = (response as? HTTPURLResponse)?.mimeType?.lowercased(),
               mimeType.contains("html") {
                throw APIError(statusCode: 0, message: "图片服务返回了网页内容")
            }
            guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024 else {
                throw APIError(statusCode: 0, message: "图片数据无效")
            }
            if persistToDisk {
                let cached = CachedURLResponse(response: response, data: data, storagePolicy: .allowed)
                diskCache.storeCachedResponse(cached, for: request)
            }
            if let persistentCacheID {
                storePersistentData(data, for: persistentCacheID)
            }
            memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            return data
        }
        inFlight[key] = task
        do {
            let data = try await task.value
            inFlight[key] = nil
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        memoryCache.removeAllObjects()
        diskCache.removeAllCachedResponses()
        if let persistentImageDirectory {
            try? FileManager.default.removeItem(at: persistentImageDirectory)
            try? FileManager.default.createDirectory(
                at: persistentImageDirectory,
                withIntermediateDirectories: true
            )
        }
        RemoteDecodedImageCache.shared.removeAll()
        RemoteAnimatedImageCache.shared.removeAll()
    }

    func persistentData(for cacheID: String) -> Data? {
        guard let url = persistentFileURL(for: cacheID),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= 20 * 1_024 * 1_024 else { return nil }
        return data
    }

    func removePersistentData(for cacheID: String) {
        guard let url = persistentFileURL(for: cacheID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func storePersistentData(_ data: Data, for cacheID: String) {
        guard let url = persistentFileURL(for: cacheID) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persistentFileURL(for cacheID: String) -> URL? {
        guard !cacheID.isEmpty, let persistentImageDirectory else { return nil }
        let digest = SHA256.hash(data: Data(cacheID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return persistentImageDirectory.appendingPathComponent(digest, isDirectory: false)
    }

    private func isPublicCacheURL(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return true }
        return !items.contains { item in
            let key = item.name.lowercased().filter { $0.isLetter || $0.isNumber }
            return key.contains("token")
                || key.contains("secret")
                || ["passkey", "authkey", "apikey", "signature", "credential"].contains(key)
        }
    }

    private func hasSensitiveImageHeaders(_ headers: [String: String]) -> Bool {
        headers.keys.contains { key in
            let normalized = key.lowercased()
            return normalized == "cookie" || normalized == "authorization" || normalized.contains("token")
        }
    }
}

private final class RemoteDecodedImageCache: @unchecked Sendable {
    static let shared = RemoteDecodedImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 72 * 1_024 * 1_024
        cache.countLimit = 180
    }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() { cache.removeAllObjects() }
}

private final class RemoteAnimatedImage: NSObject, @unchecked Sendable {
    let cacheKey: String
    let frames: [UIImage]
    let keyTimes: [NSNumber]
    let duration: TimeInterval
    let memoryCost: Int

    init?(data: Data, cacheKey: String, maximumPixelSize: CGFloat) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }
        let maximumFrameCount = 180
        let frameStep = max(1, Int(ceil(Double(frameCount) / Double(maximumFrameCount))))

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumPixelSize))
        ]
        var decodedFrames: [UIImage] = []
        var frameDurations: [TimeInterval] = []
        decodedFrames.reserveCapacity(min(frameCount, maximumFrameCount))
        frameDurations.reserveCapacity(min(frameCount, maximumFrameCount))

        for index in stride(from: 0, to: frameCount, by: frameStep) {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary) else {
                continue
            }
            decodedFrames.append(UIImage(cgImage: cgImage))
            let endIndex = min(index + frameStep, frameCount)
            let sampledDuration = (index..<endIndex).reduce(0) { partial, frameIndex in
                partial + Self.frameDuration(source: source, index: frameIndex)
            }
            frameDurations.append(sampledDuration)
        }
        guard !decodedFrames.isEmpty else { return nil }

        let totalDuration = max(frameDurations.reduce(0, +), 0.1)
        var elapsed: TimeInterval = 0
        var times: [NSNumber] = []
        times.reserveCapacity(frameDurations.count)
        for frameDuration in frameDurations {
            times.append(NSNumber(value: elapsed / totalDuration))
            elapsed += frameDuration
        }

        self.cacheKey = cacheKey
        frames = decodedFrames
        keyTimes = times
        duration = totalDuration
        memoryCost = decodedFrames.reduce(0) { partial, image in
            partial + Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        }
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? NSNumber
        let value = (unclamped ?? clamped)?.doubleValue ?? 0.1
        return value < 0.02 ? 0.1 : value
    }
}

private final class RemoteAnimatedImageCache: @unchecked Sendable {
    static let shared = RemoteAnimatedImageCache()
    private let cache = NSCache<NSString, RemoteAnimatedImage>()

    private init() {
        cache.totalCostLimit = 48 * 1_024 * 1_024
        cache.countLimit = 120
    }

    func image(for key: String) -> RemoteAnimatedImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: RemoteAnimatedImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
    }

    func removeAll() { cache.removeAllObjects() }
}

private final class AnimatedRemoteUIImageView: UIImageView {
    private var displayedCacheKey = ""

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func display(_ animatedImage: RemoteAnimatedImage) {
        guard displayedCacheKey != animatedImage.cacheKey else { return }
        displayedCacheKey = animatedImage.cacheKey
        layer.removeAnimation(forKey: "harvest.site-logo.animation")
        image = animatedImage.frames.first
        guard animatedImage.frames.count > 1 else { return }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = animatedImage.frames.compactMap(\.cgImage)
        guard animation.values?.count == animatedImage.frames.count else { return }
        animation.keyTimes = animatedImage.keyTimes
        animation.duration = animatedImage.duration
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "harvest.site-logo.animation")
    }
}

private struct AnimatedRemoteImageView: UIViewRepresentable {
    let image: RemoteAnimatedImage

    func makeUIView(context: Context) -> AnimatedRemoteUIImageView {
        let imageView = AnimatedRemoteUIImageView()
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.layer.contentsGravity = .resizeAspect
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ imageView: AnimatedRemoteUIImageView, context: Context) {
        imageView.contentMode = .scaleAspectFit
        imageView.layer.contentsGravity = .resizeAspect
        imageView.clipsToBounds = true
        imageView.display(image)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AnimatedRemoteUIImageView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

let doubanImageReferer = "https://movie.douban.com/"
let doubanImageUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

private func isDoubanImageHost(_ host: String) -> Bool {
    host == "doubanio.com"
        || host.hasSuffix(".doubanio.com")
        || host == "douban.com"
        || host.hasSuffix(".douban.com")
}

func normalizedRemoteImageURL(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }
    if normalized.hasPrefix("//") {
        normalized = "https:\(normalized)"
    } else if normalized.lowercased().hasPrefix("http://") {
        let host = URL(string: normalized)?.host?.lowercased() ?? ""
        if isDoubanImageHost(host) {
            normalized = "https://" + String(normalized.dropFirst("http://".count))
        }
    } else if !normalized.contains("://") {
        let host = URL(string: "https://\(normalized)")?.host?.lowercased() ?? ""
        if isDoubanImageHost(host) {
            normalized = "https://" + normalized
        }
    }
    return normalized
}

func remoteImageHeaders(for url: URL?, additional: [String: String] = [:]) -> [String: String] {
    var headers = additional
    func matchingHeaderKey(_ name: String) -> String? {
        headers.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    let host = url?.host?.lowercased() ?? ""
    let doubanRequest = isDoubanImageHost(host)
    let carriesDoubanContext = matchingHeaderKey("Referer")
        .flatMap { headers[$0] }
        .map { $0 == doubanImageReferer }
        ?? false
    if !doubanRequest, carriesDoubanContext {
        for name in ["Referer", "Cookie"] {
            if let key = matchingHeaderKey(name) { headers.removeValue(forKey: key) }
        }
        if let key = matchingHeaderKey("User-Agent"), headers[key] == doubanImageUserAgent {
            headers.removeValue(forKey: key)
        }
    }
    if doubanRequest {
        if matchingHeaderKey("Referer") == nil {
            headers["Referer"] = doubanImageReferer
        }
        if matchingHeaderKey("User-Agent") == nil {
            headers["User-Agent"] = doubanImageUserAgent
        }
    }
    if matchingHeaderKey("User-Agent") == nil {
        headers["User-Agent"] = "Harvest-iOS/1.0"
    }
    return headers
}

func remoteImageCacheKey(url: URL, headers: [String: String]) -> String {
    let normalizedHeaders: [(name: String, value: String)] = headers.map { entry in
        (name: entry.key.lowercased(), value: entry.value)
    }
    let sortedHeaders = normalizedHeaders.sorted { left, right in
        if left.name == right.name { return left.value < right.value }
        return left.name < right.name
    }
    let headerPart = sortedHeaders.map { entry in
        entry.name + "=" + entry.value
    }.joined(separator: "&")
    return "\(url.absoluteString)|\(headerPart)"
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let headers: [String: String]
    private let onFailure: (() -> Void)?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var loadedImage: UIImage?

    init(
        url: URL?,
        headers: [String: String] = [:],
        onFailure: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.headers = headers
        self.onFailure = onFailure
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
            }
        }
        .task(id: requestKey) {
            loadedImage = nil
            guard let url,
                  let normalizedURL = URL(string: normalizedRemoteImageURL(url.absoluteString)) else { return }
            let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: headers)
            let cacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders)
            if let cached = RemoteDecodedImageCache.shared.image(for: cacheKey) {
                loadedImage = cached
                return
            }
            do {
                let data = try await RemoteImageDataCache.shared.data(for: normalizedURL, headers: effectiveHeaders)
                guard !Task.isCancelled, let image = UIImage(data: data) else {
                    if !Task.isCancelled { await MainActor.run { onFailure?() } }
                    return
                }
                RemoteDecodedImageCache.shared.insert(image, for: cacheKey)
                loadedImage = image
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { onFailure?() }
            }
        }
    }

    private var requestKey: String {
        guard let url,
              let normalizedURL = URL(string: normalizedRemoteImageURL(url.absoluteString)) else { return "" }
        return remoteImageCacheKey(url: normalizedURL, headers: remoteImageHeaders(for: normalizedURL, additional: headers))
    }
}

struct RemoteImageCandidate: Identifiable {
    let url: URL
    let headers: [String: String]
    let persistentCacheID: String?

    init(
        url: URL,
        headers: [String: String] = [:],
        persistentCacheID: String? = nil
    ) {
        self.url = url
        self.headers = headers
        self.persistentCacheID = persistentCacheID
    }

    var id: String {
        remoteImageCacheKey(url: url, headers: remoteImageHeaders(for: url, additional: headers))
    }
}

struct CachedRemoteImageCandidates<Content: View, Placeholder: View>: View {
    let candidates: [RemoteImageCandidate]
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var candidateIndex = 0

    init(
        candidates: [RemoteImageCandidate],
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.candidates = candidates
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if candidateIndex < candidates.count {
                let candidate = candidates[candidateIndex]
                CachedRemoteImage(
                    url: candidate.url,
                    headers: candidate.headers,
                    onFailure: advanceCandidate,
                    content: content,
                    placeholder: placeholder
                )
            } else {
                placeholder()
            }
        }
        .task(id: candidateKey) { candidateIndex = 0 }
    }

    private var candidateKey: String { candidates.map(\.id).joined(separator: "|") }

    private func advanceCandidate() {
        candidateIndex = min(candidateIndex + 1, candidates.count)
    }
}

struct CachedAnimatedRemoteImageCandidates<Placeholder: View>: View {
    let candidates: [RemoteImageCandidate]
    let maximumPixelSize: CGFloat
    private let placeholder: () -> Placeholder
    @State private var candidateIndex = 0
    @State private var loadedImage: RemoteAnimatedImage?

    init(
        candidates: [RemoteImageCandidate],
        maximumPixelSize: CGFloat,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.candidates = candidates
        self.maximumPixelSize = maximumPixelSize
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let loadedImage {
                AnimatedRemoteImageView(image: loadedImage)
            } else {
                placeholder()
            }
        }
        .task(id: requestKey) { await loadCurrentCandidate() }
        .onChange(of: candidateKey) { _, _ in
            candidateIndex = 0
            loadedImage = nil
        }
    }

    private var candidateKey: String { candidates.map(\.id).joined(separator: "|") }

    private var requestKey: String {
        guard candidateIndex < candidates.count else { return "\(candidateKey)|exhausted" }
        return "\(candidateKey)|\(candidateIndex)|\(Int(maximumPixelSize.rounded(.up)))"
    }

    @MainActor private func loadCurrentCandidate() async {
        loadedImage = nil
        guard candidateIndex < candidates.count else { return }

        if candidateIndex == 0, await loadFirstPersistedCandidate() {
            return
        }

        let candidate = candidates[candidateIndex]
        guard let normalizedURL = URL(string: normalizedRemoteImageURL(candidate.url.absoluteString)) else {
            advanceCandidate()
            return
        }
        let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: candidate.headers)
        let dataCacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders)
        let decodedCacheKey = "\(dataCacheKey)|animated|\(Int(maximumPixelSize.rounded(.up)))"
        if let cached = RemoteAnimatedImageCache.shared.image(for: decodedCacheKey) {
            loadedImage = cached
            return
        }

        do {
            let data = try await RemoteImageDataCache.shared.data(
                for: normalizedURL,
                headers: effectiveHeaders,
                persistentCacheID: candidate.persistentCacheID
            )
            guard !Task.isCancelled else { return }
            let pixelSize = maximumPixelSize
            let decoded = await Task.detached(priority: .utility) {
                RemoteAnimatedImage(data: data, cacheKey: decodedCacheKey, maximumPixelSize: pixelSize)
            }.value
            guard !Task.isCancelled, let decoded else {
                if !Task.isCancelled { advanceCandidate() }
                return
            }
            RemoteAnimatedImageCache.shared.insert(decoded, for: decodedCacheKey)
            loadedImage = decoded
        } catch {
            guard !Task.isCancelled else { return }
            advanceCandidate()
        }
    }

    private func advanceCandidate() {
        candidateIndex = min(candidateIndex + 1, candidates.count)
    }

    @MainActor private func loadFirstPersistedCandidate() async -> Bool {
        for candidate in candidates {
            guard let persistentCacheID = candidate.persistentCacheID,
                  let data = await RemoteImageDataCache.shared.persistentData(for: persistentCacheID),
                  let normalizedURL = URL(string: normalizedRemoteImageURL(candidate.url.absoluteString)) else {
                continue
            }
            let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: candidate.headers)
            let dataCacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders)
            let decodedCacheKey = "\(dataCacheKey)|animated|\(Int(maximumPixelSize.rounded(.up)))"
            if let cached = RemoteAnimatedImageCache.shared.image(for: decodedCacheKey) {
                loadedImage = cached
                return true
            }
            let pixelSize = maximumPixelSize
            let decoded = await Task.detached(priority: .utility) {
                RemoteAnimatedImage(data: data, cacheKey: decodedCacheKey, maximumPixelSize: pixelSize)
            }.value
            guard !Task.isCancelled else { return false }
            guard let decoded else {
                await RemoteImageDataCache.shared.removePersistentData(for: persistentCacheID)
                continue
            }
            RemoteAnimatedImageCache.shared.insert(decoded, for: decodedCacheKey)
            loadedImage = decoded
            return true
        }
        return false
    }
}

private func setupValue(_ value: String?, fallback: String) -> String {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? fallback : normalized
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showHistory = false
    @State private var showSetup = false
    @State private var showAppUpdate = false
    @State private var confirmClearAllData = false
    @State private var isClearingData = false
    @State private var showClearCompleted = false
    @State private var isCheckingServer = false
    @State private var setupStatus: HarvestSetupStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            BrandMark(size: 68)
                            Text("Harvest")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("把站点、下载和自动化任务收进一个工作台")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 32)

                        VStack(spacing: 14) {
                            LabeledField(title: "服务器地址", icon: "server.rack", text: $server,
                                         prompt: "https://harvest.example.com", keyboard: .URL)
                            LabeledField(title: "账号", icon: "person", text: $username, prompt: "管理员账号")
                            SecureLabeledField(title: "密码", text: $password, visible: $showPassword)
                        }

                        Button {
                            Task {
                                guard !isCheckingServer else { return }
                                isCheckingServer = true
                                defer { isCheckingServer = false }
                                let status = await appState.fetchSetupStatus(server: server)
                                if status?.needsSetup == true {
                                    setupStatus = status
                                    showSetup = true
                                } else {
                                    await appState.login(server: server, username: username, password: password)
                                }
                            }
                        } label: {
                            HStack {
                                if appState.isBusy || isCheckingServer { ProgressView().tint(.white) }
                                Text(appState.isBusy || isCheckingServer ? "连接中" : "连接 Harvest")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HarvestTheme.green)
                        .disabled(appState.isBusy || isCheckingServer)

                        if !appState.loginHistory.isEmpty {
                            Button {
                                showHistory = true
                            } label: {
                                Label("使用历史账号", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            confirmClearAllData = true
                        } label: {
                            Label("清理所有持久化数据", systemImage: "trash.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isBusy || isClearingData)

                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                            Text("令牌存储在本机钥匙串，密码不会上传到 Harvest 之外的服务。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        CurrentScreenShareButton()
                            .environmentObject(appState)
                            .buttonStyle(.bordered)
                        Button { showAppUpdate = true } label: {
                            Image(systemName: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(HarvestTheme.green)
                        .accessibilityLabel("APP 升级")
                    }
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
            }
            .navigationTitle("登录")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                LoginHistorySheet(server: $server, username: $username, password: $password)
                    .environmentObject(appState)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSetup) {
                SetupWizardView(server: server, setupStatus: setupStatus) { adminUser, adminPassword in
                    username = adminUser
                    password = adminPassword
                    Task { await appState.login(server: server, username: adminUser, password: adminPassword) }
                }
                .environmentObject(appState)
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showAppUpdate) {
                AppUpdatePromptView()
                    .environmentObject(appState)
                    .presentationDetents([.large])
            }
            .confirmationDialog(
                "清理所有持久化数据？",
                isPresented: $confirmClearAllData,
                titleVisibility: .visible
            ) {
                Button("清理", role: .destructive) {
                    Task {
                        isClearingData = true
                        await appState.clearAllPersistentData()
                        server = ""
                        username = ""
                        password = ""
                        showPassword = false
                        isClearingData = false
                        showClearCompleted = true
                    }
                }
            } message: {
                Text("将清除登录状态、历史账号、钥匙串令牌与密码、所有设置、APP 日志、网页 Cookie 和缓存。")
            }
            .alert("清理完成", isPresented: $showClearCompleted) {
                Button("好", role: .cancel) { }
            } message: {
                Text("本机持久化数据已全部清除。")
            }
            .onAppear {
                server = UserDefaults.standard.string(forKey: "harvest.baseURL") ?? ""
                let history = appState.loginHistory
                let record = history.first(where: { $0.server == server }) ?? history.first
                if let record {
                    if server.isEmpty { server = record.server }
                    username = record.username
                    password = appState.savedPassword(for: record) ?? ""
                }
            }
        }
    }
}

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let server: String
    let setupStatus: HarvestSetupStatus?
    let onComplete: (String, String) -> Void

    @State private var step = 0
    @State private var databaseType = "pgsql"
    @State private var host = "go-harvest-postgres"
    @State private var port = "5432"
    @State private var database = "goharvest"
    @State private var databaseUser = "goharvest"
    @State private var databasePassword = ""
    @State private var debug = false
    @State private var adminUser = "admin"
    @State private var adminPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        server: String,
        setupStatus: HarvestSetupStatus? = nil,
        onComplete: @escaping (String, String) -> Void
    ) {
        self.server = server
        self.setupStatus = setupStatus
        self.onComplete = onComplete
        let defaults = setupStatus?.defaults(for: "pgsql")
        _host = State(initialValue: setupValue(defaults?.host, fallback: "go-harvest-postgres"))
        _port = State(initialValue: setupValue(defaults?.port, fallback: "5432"))
        _database = State(initialValue: setupValue(defaults?.name, fallback: "goharvest"))
        _databaseUser = State(initialValue: setupValue(defaults?.user, fallback: "goharvest"))
        _databasePassword = State(initialValue: defaults?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule().fill(index <= step ? HarvestTheme.green : Color.secondary.opacity(0.2)).frame(height: 5)
                        }
                    }
                    Text(["选择数据库", "同步数据库", "创建管理员"][step]).font(.headline)
                }

                if step == 0 {
                    Section("数据库类型") {
                        Picker("类型", selection: $databaseType) { Text("PostgreSQL").tag("pgsql"); Text("SQLite").tag("sqlite") }.pickerStyle(.segmented)
                            .onChange(of: databaseType) { _, value in applyDatabaseDefaults(value) }
                        Text(databaseType == "pgsql" ? "适合长期运行与多用户部署" : "适合轻量部署，数据保存在服务端文件中")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if step == 1 {
                    Section(databaseType == "pgsql" ? "PostgreSQL" : "SQLite") {
                        if databaseType == "pgsql" {
                            TextField("数据库地址", text: $host).textInputAutocapitalization(.never)
                            TextField("端口", text: $port).keyboardType(.numberPad)
                            TextField("数据库名称", text: $database).textInputAutocapitalization(.never)
                            TextField("数据库账号", text: $databaseUser).textInputAutocapitalization(.never)
                            SecureField("数据库密码", text: $databasePassword)
                        } else {
                            LabeledContent("数据库文件", value: database)
                        }
                        Toggle("调试模式", isOn: $debug)
                    }
                } else {
                    Section("管理员账号") {
                        TextField("用户名", text: $adminUser).textInputAutocapitalization(.never)
                        SecureField("密码（至少 6 位）", text: $adminPassword)
                        SecureField("确认密码", text: $confirmPassword)
                    }
                }

                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(HarvestTheme.coral).font(.caption) }
                }
            }
            .navigationTitle("初始化 Harvest").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "取消" : "上一步") { if step == 0 { dismiss() } else { step -= 1; errorMessage = nil } }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(step == 2 ? "完成" : "下一步") { Task { await advance() } }.disabled(isSubmitting)
                }
            }
            .overlay { if isSubmitting { ZStack { Color.black.opacity(0.12).ignoresSafeArea(); ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)) } } }
        }
    }

    private func advance() async {
        errorMessage = nil
        if step == 0 {
            applyDatabaseDefaults(databaseType)
            step = 1
            return
        }
        if step == 1 {
            if databaseType == "pgsql" {
                guard let databasePort = Int(port),
                      (1...65_535).contains(databasePort),
                      !host.isEmpty,
                      !database.isEmpty,
                      !databaseUser.isEmpty else {
                    errorMessage = "请填写有效的数据库连接信息"
                    return
                }
            }
            isSubmitting = true
            defer { isSubmitting = false }
            var payload: [String: Any] = ["database_type": databaseType, "debug": debug, "name": database]
            if databaseType == "pgsql" {
                payload["host"] = host
                payload["port"] = port
                payload["user"] = databaseUser
                payload["pass"] = databasePassword
            }
            do { try await appState.setupDatabase(server: server, payload: payload); step = 2 }
            catch { errorMessage = error.localizedDescription }
            return
        }
        guard adminPassword.count >= 6 else { errorMessage = "管理员密码至少需要 6 位"; return }
        guard adminPassword == confirmPassword else { errorMessage = "两次输入的密码不一致"; return }
        guard !adminUser.isEmpty else { errorMessage = "管理员用户名不能为空"; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.setupAdministrator(
                server: server,
                username: adminUser,
                password: adminPassword
            )
            dismiss()
            onComplete(adminUser, adminPassword)
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyDatabaseDefaults(_ type: String) {
        let defaults = setupStatus?.defaults(for: type)
        if type == "sqlite" {
            database = setupValue(defaults?.name, fallback: "db/data.sqlite3")
            return
        }
        host = setupValue(defaults?.host, fallback: "go-harvest-postgres")
        port = setupValue(defaults?.port, fallback: "5432")
        database = setupValue(defaults?.name, fallback: "goharvest")
        databaseUser = setupValue(defaults?.user, fallback: "goharvest")
        databasePassword = defaults?.password ?? ""
    }
}

struct LoginHistorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Binding var server: String
    @Binding var username: String
    @Binding var password: String

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.loginHistory) { record in
                    Button {
                        server = record.server
                        username = record.username
                        password = appState.savedPassword(for: record) ?? ""
                        dismiss()
                        Task { await appState.quickLogin(record) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(HarvestTheme.green.opacity(0.15)).frame(width: 40, height: 40)
                                .overlay(Image(systemName: "person.fill").foregroundStyle(HarvestTheme.green))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(privacyMaskedText(record.username, enabled: appState.privacyMode)).font(.headline).foregroundStyle(.primary)
                                Text(record.server).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { appState.removeLoginRecord(record) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("历史账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

struct AccountSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var switchingID: String?

    var body: some View {
        List {
            Section {
                ForEach(appState.loginHistory) { record in
                    let isCurrent = record.server == appState.baseURL
                        && record.username == appState.profile?.username
                    Button {
                        guard !isCurrent else { return }
                        switchingID = record.id
                        Task {
                            await appState.quickLogin(record)
                            switchingID = nil
                            if appState.baseURL == record.server,
                               appState.profile?.username == record.username {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill((isCurrent ? HarvestTheme.green : HarvestTheme.blue).opacity(0.14))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: isCurrent ? "checkmark" : "person.fill")
                                        .foregroundStyle(isCurrent ? HarvestTheme.green : HarvestTheme.blue)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(privacyMaskedText(record.username, enabled: appState.privacyMode)).font(.headline)
                                    if isCurrent { Text("当前").font(.caption2).foregroundStyle(HarvestTheme.green) }
                                }
                                Text(record.server).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if switchingID == record.id { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(.primary)
                    }
                    .disabled(isCurrent || switchingID != nil)
                }
            } header: {
                Text("已保存账号")
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("登录其他账号", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("切换账号")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingNotices = false
    @State private var showingAppUpdate = false
    @State private var showingSearch = false
    @State private var availableAppUpdate: String?
    @State private var handledNoticePresentation = 0
    @State private var lastNonSearchTab = 2

    private var showsNewsTab: Bool {
        appState.mediaTMDBEnabled || appState.mediaDoubanEnabled
    }

    private var defaultContentTab: Int {
        appState.profile?.isSuperuser == true ? 2 : 3
    }

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 18.0, *) {
                    modernTabView
                } else {
                    legacyTabView
                }
            }
            .harvestNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandMark(size: 28)
                        .accessibilityHidden(true)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    CurrentScreenShareButton()
                        .environmentObject(appState)
                    if availableAppUpdate != nil {
                        Button {
                            showingAppUpdate = true
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(HarvestTheme.coral)
                        }
                        .accessibilityLabel("发现 APP 新版本")
                    }
                    Button { showingNotices = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: appState.unreadNoticeCount > 0 ? "bell.fill" : "bell")
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 26, height: 26)
                            if appState.unreadNoticeCount > 0 {
                                Text(appState.unreadNoticeCount > 99 ? "99+" : "\(appState.unreadNoticeCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, appState.unreadNoticeCount > 9 ? 4 : 3)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(HarvestTheme.coral, in: Capsule())
                                    .offset(x: 7, y: -5)
                            }
                        }
                        .frame(width: 34, height: 30)
                    }
                        .accessibilityLabel("消息")
                    LegacySearchToolbarButton { appState.presentSearch() }
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill").symbolRenderingMode(.hierarchical)
                    }
                        .accessibilityLabel("设置")
                }
            }
            .navigationDestination(isPresented: $showingSearch) {
                SearchView { showingSearch = false }
                    .environmentObject(appState)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(appState) }
        .sheet(isPresented: $showingNotices) { NoticeView().environmentObject(appState).presentationDetents([.large]) }
        .sheet(isPresented: $showingAppUpdate) {
            AppUpdatePromptView().environmentObject(appState).presentationDetents([.large])
        }
        .task(id: appState.autoRefreshMinutes) {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(appState.autoRefreshMinutes * 60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                appState.requestAutomaticRefresh(force: true)
            }
        }
        .task(id: appState.isAuthenticated) {
            guard appState.isAuthenticated else { return }
            await appState.requestNotificationAuthorization()
            await appState.refreshNoticeState()
            presentPendingNoticeIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await appState.refreshNoticeState()
            }
        }
        .task(id: appState.isAuthenticated) {
            guard appState.isAuthenticated else {
                availableAppUpdate = nil
                return
            }
            let version = await availableAppUpdateVersion(appState)
            guard !Task.isCancelled else { return }
            availableAppUpdate = version
            guard let version, !isAppUpdateVersionIgnored(version) else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, !showingSettings, !showingNotices else { return }
            showingAppUpdate = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.requestAutomaticRefresh()
                Task { await appState.refreshNoticeState() }
            }
        }
        .onChange(of: appState.noticePresentationGeneration) { _, _ in
            presentPendingNoticeIfNeeded()
        }
        .onChange(of: showsNewsTab) { _, isVisible in
            guard !isVisible else { return }
            if appState.selectedTab == 0 {
                appState.selectedTab = defaultContentTab
            }
            if lastNonSearchTab == 0 {
                lastNonSearchTab = defaultContentTab
            }
        }
        .onChange(of: appState.searchPresentationGeneration) { _, _ in
            if #available(iOS 18.0, *) {
                appState.selectedTab = 5
            } else {
                showingSearch = true
            }
        }
        .onChange(of: appState.selectedTab) { oldValue, newValue in
            if newValue == 5, oldValue != 5 {
                lastNonSearchTab = validContentTab(oldValue)
            } else if newValue != 5 {
                lastNonSearchTab = validContentTab(newValue)
            }
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $appState.selectedTab) {
            if showsNewsTab {
                Tab("资讯", systemImage: "newspaper.fill", value: 0) { NewsView() }
            }
            if appState.profile?.isSuperuser == true {
                Tab("站点", systemImage: "globe.asia.australia.fill", value: 1) { SitesView() }
                Tab("仪表盘", systemImage: "chart.bar.xaxis", value: 2) { DashboardView() }
            }
            Tab("下载", systemImage: "arrow.down.circle.fill", value: 3) { DownloadsView() }
            if appState.profile?.isSuperuser == true {
                Tab("任务", systemImage: "checklist", value: 4) { TasksView() }
            }
            Tab(value: 5, role: .search) {
                SearchView { appState.selectedTab = lastNonSearchTab }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $appState.selectedTab) {
            if showsNewsTab {
                NewsView().tabItem { Label("资讯", systemImage: "newspaper.fill") }.tag(0)
            }
            if appState.profile?.isSuperuser == true {
                SitesView().tabItem { Label("站点", systemImage: "globe.asia.australia.fill") }.tag(1)
                DashboardView().tabItem { Label("仪表盘", systemImage: "chart.bar.xaxis") }.tag(2)
            }
            DownloadsView().tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }.tag(3)
            if appState.profile?.isSuperuser == true {
                TasksView().tabItem { Label("任务", systemImage: "checklist") }.tag(4)
            }
        }
    }

    private func presentPendingNoticeIfNeeded() {
        guard appState.noticePresentationGeneration != handledNoticePresentation else { return }
        handledNoticePresentation = appState.noticePresentationGeneration
        showingNotices = true
    }

    private func validContentTab(_ candidate: Int) -> Int {
        if candidate == 0, showsNewsTab { return candidate }
        if candidate == 3 { return candidate }
        if appState.profile?.isSuperuser == true, (1...4).contains(candidate) { return candidate }
        return defaultContentTab
    }
}

private struct LegacySearchToolbarButton: View {
    let action: () -> Void

    @ViewBuilder var body: some View {
        if #available(iOS 18.0, *) {
            EmptyView()
        } else {
            Button(action: action) {
                Image(systemName: "magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("搜索")
        }
    }
}

struct ManualTaskFeedbackOverlay: View {
    let feedback: ManualTaskFeedback

    private var color: Color {
        switch feedback.phase {
        case .running: HarvestTheme.blue
        case .success: HarvestTheme.green
        case .failure: HarvestTheme.coral
        case .cancelled: .secondary
        }
    }

    private var icon: String {
        switch feedback.phase {
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark"
        case .failure: "exclamationmark"
        case .cancelled: "xmark"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.13))
                        .frame(width: 58, height: 58)
                    if feedback.phase == .running {
                        ProgressView()
                            .controlSize(.large)
                            .tint(color)
                    }
                    if feedback.phase != .running {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(color)
                    }
                }

                VStack(spacing: 5) {
                    Text(feedback.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let message = feedback.message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(minWidth: 172, maxWidth: 260)
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(feedback.phase == .running ? .updatesFrequently : [])
        }
        .allowsHitTesting(feedback.phase == .running)
    }
}

struct CurrentScreenShareButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var shareImage: UIImage?
    @State private var showingShare = false
    @State private var isCapturing = false

    var body: some View {
        Button {
            Task { await captureAndShare() }
        } label: {
            if isCapturing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "camera.viewfinder").symbolRenderingMode(.hierarchical)
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel("截图分享当前页面")
        .sheet(isPresented: $showingShare) {
            if let shareImage { ActivityShareSheet(items: [shareImage]) }
        }
    }

    @MainActor private func captureAndShare() async {
        guard !isCapturing else { return }
        isCapturing = true
        let restorePrivacy = !appState.privacyMode
        if restorePrivacy { appState.setPrivacyMode(true) }
        try? await Task.sleep(for: .milliseconds(180))

        defer {
            if restorePrivacy { appState.setPrivacyMode(false) }
            isCapturing = false
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            appState.presentedError = "无法获取当前页面截图"
            return
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
        shareImage = image
        showingShare = true
    }
}

struct LabeledField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                SymbolBadge(icon: icon, color: HarvestTheme.green, size: 30)
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboard)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var text: String
    @Binding var visible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                SymbolBadge(icon: "key.fill", color: HarvestTheme.green, size: 30)
                Group { if visible { TextField("密码", text: $text) } else { SecureField("密码", text: $text) } }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .accessibilityLabel(visible ? "隐藏密码" : "显示密码")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action).font(.subheadline.weight(.semibold)) }
        }
    }
}

struct SymbolBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                color,
                in: RoundedRectangle(cornerRadius: min(12, size * 0.32), style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: min(12, size * 0.32), style: .continuous)
                    .stroke(Color.white.opacity(0.18))
            )
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SymbolBadge(icon: icon, color: color, size: 36)
                Spacer()
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(value).font(.title2.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if !detail.isEmpty { Text(detail) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(HarvestTheme.green)
            }
        }
    }
}

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(HarvestTheme.green)
            Text("正在同步").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct SessionCacheBanner: View {
    let cachedAt: Date?

    var body: some View {
        HStack(spacing: 9) {
            SymbolBadge(icon: "externaldrive.badge.clock", color: HarvestTheme.green, size: 30)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(HarvestTheme.green)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            HarvestTheme.green.opacity(0.09),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(HarvestTheme.green.opacity(0.20))
        )
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        guard let cachedAt else { return "当前页面使用上次缓存数据" }
        return "当前页面使用上次缓存数据 · \(cachedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension View {
    @ViewBuilder
    func harvestNavigationChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar, .tabBar)
                .toolbarBackground(.visible, for: .navigationBar, .tabBar)
        }
    }

    func cardSurface() -> some View {
        self.padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            )
    }
}
