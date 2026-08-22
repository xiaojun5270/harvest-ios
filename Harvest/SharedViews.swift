import Foundation
import CryptoKit
import ImageIO
import SwiftUI
import UIKit

struct RemoteMediaPosterAPI: Sendable {
    let baseURL: String
    let accessToken: String
}

actor RemoteImageDataCache {
    static let shared = RemoteImageDataCache()

    private static let cachePolicyVersionKey = "images.cachePolicyVersion"
    private static let cachePolicyVersion = 3

    private let memoryCache: NSCache<NSString, NSData>
    private let diskCache: URLCache
    private let persistentImageDirectory: URL?
    private let legacyPersistentImageDirectory: URL?
    private let session: URLSession
    private let privateSession: URLSession
    private let linkedMediaSession: URLSession
    private var inFlight: [String: Task<Data, Error>] = [:]

    private init() {
        let memory = NSCache<NSString, NSData>()
        memory.totalCostLimit = 48 * 1_024 * 1_024
        memory.countLimit = 240
        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 192 * 1_024 * 1_024,
            diskPath: "harvest-public-images-v3"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let publicSession = URLSession(configuration: configuration)
        let privateConfiguration = URLSessionConfiguration.ephemeral
        privateConfiguration.urlCache = nil
        privateConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        privateConfiguration.timeoutIntervalForRequest = 8
        privateConfiguration.timeoutIntervalForResource = 15
        privateConfiguration.waitsForConnectivity = false
        privateConfiguration.httpShouldSetCookies = false
        privateConfiguration.httpCookieStorage = nil
        let linkedMediaConfiguration = URLSessionConfiguration.ephemeral
        linkedMediaConfiguration.urlCache = nil
        linkedMediaConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        linkedMediaConfiguration.timeoutIntervalForRequest = 8
        linkedMediaConfiguration.timeoutIntervalForResource = 15
        linkedMediaConfiguration.waitsForConnectivity = false
        linkedMediaConfiguration.httpMaximumConnectionsPerHost = 3
        linkedMediaConfiguration.httpShouldSetCookies = false
        linkedMediaConfiguration.httpCookieStorage = nil
        let persistentDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Harvest", isDirectory: true)
            .appendingPathComponent("PersistentImages", isDirectory: true)
        let legacyPersistentDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("HarvestPersistentImages", isDirectory: true)
        let defaults = UserDefaults.standard
        let previousCachePolicyVersion = defaults.integer(forKey: Self.cachePolicyVersionKey)
        if previousCachePolicyVersion < Self.cachePolicyVersion {
            cache.removeAllCachedResponses()
            defaults.set(Self.cachePolicyVersion, forKey: Self.cachePolicyVersionKey)
        }
        if let persistentDirectory {
            try? FileManager.default.createDirectory(
                at: persistentDirectory,
                withIntermediateDirectories: true
            )
        }
        memoryCache = memory
        diskCache = cache
        persistentImageDirectory = persistentDirectory
        legacyPersistentImageDirectory = legacyPersistentDirectory
        session = publicSession
        privateSession = URLSession(configuration: privateConfiguration)
        linkedMediaSession = URLSession(configuration: linkedMediaConfiguration)
    }

    func data(
        for url: URL,
        headers: [String: String] = [:],
        persistentCacheID: String? = nil,
        prefersLinkedMediaPoster: Bool = false,
        linkedMediaAPI: RemoteMediaPosterAPI? = nil
    ) async throws -> Data {
        guard let normalizedURL = URL(string: normalizedRemoteImageURL(url.absoluteString)) else {
            throw APIError(statusCode: 0, message: "图片地址无效")
        }
        let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: headers)
        // 站点图标接口可能需要 Bearer 认证，但落盘内容只有图片数据，不包含请求头。
        // 仅对明确标记为 site-icon 的资源允许持久化，避免放宽其它敏感图片缓存。
        let isSiteIcon = isSiteIconCache(persistentCacheID)
        let isResourceCover = isResourceCoverCache(persistentCacheID)
        // A private tracker cover may require Cookie/Referer to download, but
        // the persisted file contains only decoded image bytes and its filename
        // is a SHA-256 digest. Allow explicitly marked resource covers to remain
        // available offline just like site icons.
        let persistToDisk = (isPublicCacheURL(normalizedURL) || isSiteIcon || isResourceCover)
            && (!hasSensitiveImageHeaders(effectiveHeaders) || isSiteIcon || isResourceCover)
        let persistentID = persistToDisk ? persistentCacheID : nil
        if !persistToDisk, let persistentCacheID {
            removePersistentData(for: persistentCacheID)
        }
        let variant = prefersLinkedMediaPoster ? "linked-media-poster" : ""
        let key = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders, variant: variant)
        let cacheKey = key as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            if let persistentID {
                storePersistentData(cached as Data, for: persistentID)
            }
            return cached as Data
        }
        if let persistentID, let cached = persistentData(for: persistentID) {
            memoryCache.setObject(cached as NSData, forKey: cacheKey, cost: cached.count)
            return cached
        }

        let cachePolicy: URLRequest.CachePolicy = persistToDisk ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData
        // A failed tracker image must not stall every visible search card for
        // twenty seconds before the next candidate can be attempted.
        var request = URLRequest(url: normalizedURL, cachePolicy: cachePolicy, timeoutInterval: 8)
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        for (name, value) in effectiveHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if persistToDisk, let cached = diskCache.cachedResponse(for: request) {
            let isSuccessful = (cached.response as? HTTPURLResponse).map {
                (200..<300).contains($0.statusCode)
            } ?? true
            let isNotHTML = !((cached.response.mimeType ?? "").lowercased().contains("html"))
            let isPlaceholder = (cached.response as? HTTPURLResponse).map {
                isRemoteImagePlaceholderResponse($0, data: cached.data, url: normalizedURL)
            } ?? false
            if isSuccessful, isNotHTML, !isPlaceholder, !cached.data.isEmpty {
                if let persistentID {
                    storePersistentData(cached.data, for: persistentID)
                }
                memoryCache.setObject(cached.data as NSData, forKey: cacheKey, cost: cached.data.count)
                return cached.data
            }
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        if let task = inFlight[key] {
            let data = try await task.value
            if let persistentID {
                storePersistentData(data, for: persistentID)
            }
            return data
        }

        let task = Task<Data, Error> {
            let activeSession = prefersLinkedMediaPoster
                ? linkedMediaSession
                : (persistToDisk ? session : privateSession)
            let (data, response) = try await activeSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError(statusCode: http.statusCode, message: "图片加载失败（\(http.statusCode)）")
            }
            if let http = response as? HTTPURLResponse,
               isRemoteImagePlaceholderResponse(http, data: data, url: normalizedURL) {
                throw APIError(statusCode: 0, message: "图片代理返回了占位图")
            }
            let mimeType = (response as? HTTPURLResponse)?.mimeType?.lowercased() ?? ""
            let bodyPrefix = String(data: data.prefix(512), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let isJSONResponse = mimeType.contains("json")
                || bodyPrefix.hasPrefix("{")
                || bodyPrefix.hasPrefix("[")
            if isJSONResponse,
               let nestedImageURL = remoteImageURLFromResponse(data, baseURL: normalizedURL),
               nestedImageURL != normalizedURL {
                return try await self.data(
                    for: nestedImageURL,
                    headers: forwardedRemoteImageHeaders(
                        effectiveHeaders,
                        from: normalizedURL,
                        to: nestedImageURL
                    ),
                    persistentCacheID: persistentCacheID,
                    prefersLinkedMediaPoster: prefersLinkedMediaPoster,
                    linkedMediaAPI: linkedMediaAPI
                )
            }
            if mimeType.contains("html") || bodyPrefix.hasPrefix("<!doctype html")
                || bodyPrefix.hasPrefix("<html") || bodyPrefix.hasPrefix("<head") {
                if prefersLinkedMediaPoster,
                   let mediaPageURL = remoteMediaPageURLFromHTML(data, baseURL: normalizedURL),
                   mediaPageURL != normalizedURL {
                    if let linkedMediaAPI,
                       let apiPosterURL = await linkedMediaPosterURL(
                        for: mediaPageURL,
                        api: linkedMediaAPI
                       ) {
                        return try await self.data(
                            for: apiPosterURL,
                            headers: forwardedRemoteImageHeaders(
                                effectiveHeaders,
                                from: mediaPageURL,
                                to: apiPosterURL
                            ),
                            persistentCacheID: persistentCacheID,
                            prefersLinkedMediaPoster: true,
                            linkedMediaAPI: linkedMediaAPI
                        )
                    }
                    return try await self.data(
                        for: mediaPageURL,
                        headers: forwardedRemoteImageHeaders(
                            effectiveHeaders,
                            from: normalizedURL,
                            to: mediaPageURL
                        ),
                        persistentCacheID: persistentCacheID,
                        prefersLinkedMediaPoster: true,
                        linkedMediaAPI: linkedMediaAPI
                    )
                }
                // A number of trackers protect their poster endpoint and return
                // a small HTML page containing the real image URL. Follow the
                // common OpenGraph/lazy-image values instead of treating that
                // response as a hard image failure.
                guard let imageURL = remoteImageURLFromHTML(data, baseURL: normalizedURL),
                      imageURL != normalizedURL else {
                    throw APIError(statusCode: 0, message: "图片服务返回了网页内容")
                }
                return try await self.data(
                    for: imageURL,
                    headers: forwardedRemoteImageHeaders(
                        effectiveHeaders,
                        from: normalizedURL,
                        to: imageURL
                    ),
                    persistentCacheID: persistentCacheID,
                    prefersLinkedMediaPoster: prefersLinkedMediaPoster,
                    linkedMediaAPI: linkedMediaAPI
                )
            }
            guard !data.isEmpty, data.count <= 20 * 1_024 * 1_024 else {
                throw APIError(statusCode: 0, message: "图片数据无效")
            }
            if persistToDisk {
                let cached = CachedURLResponse(response: response, data: data, storagePolicy: .allowed)
                diskCache.storeCachedResponse(cached, for: request)
            }
            if let persistentID {
                storePersistentData(data, for: persistentID)
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

    private func linkedMediaPosterURL(
        for mediaPageURL: URL,
        api: RemoteMediaPosterAPI
    ) async -> URL? {
        guard let reference = linkedMediaReference(from: mediaPageURL) else { return nil }
        var baseURL = api.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseURL.hasSuffix("/") { baseURL.removeLast() }
        guard !baseURL.isEmpty,
              let url = URL(string: baseURL + reference.apiPath) else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if !api.accessToken.isEmpty {
            request.setValue("Bearer \(api.accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await linkedMediaSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return remotePosterURLFromMediaResponse(data, reference: reference)
        } catch {
            return nil
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
        if let legacyPersistentImageDirectory {
            try? FileManager.default.removeItem(at: legacyPersistentImageDirectory)
        }
        RemoteDecodedImageCache.shared.removeAll()
        RemoteAnimatedImageCache.shared.removeAll()
    }

    func persistentData(for cacheID: String) -> Data? {
        guard let url = persistentFileURL(for: cacheID) else { return nil }
        if let data = validPersistentData(at: url) {
            return data
        }
        guard let legacyURL = legacyPersistentFileURL(for: cacheID),
              let data = validPersistentData(at: legacyURL) else { return nil }
        try? data.write(to: url, options: .atomic)
        return data
    }

    func persistentData(
        for cacheID: String,
        requestURL: URL,
        headers: [String: String]
    ) -> Data? {
        let isSiteIcon = isSiteIconCache(cacheID)
        let isResourceCover = isResourceCoverCache(cacheID)
        let canPersist = (isPublicCacheURL(requestURL) || isSiteIcon || isResourceCover)
            && (!hasSensitiveImageHeaders(headers) || isSiteIcon || isResourceCover)
        guard canPersist else {
            removePersistentData(for: cacheID)
            return nil
        }
        return persistentData(for: cacheID)
    }

    func removePersistentData(for cacheID: String) {
        if let url = persistentFileURL(for: cacheID) {
            try? FileManager.default.removeItem(at: url)
        }
        if let legacyURL = legacyPersistentFileURL(for: cacheID) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    private func storePersistentData(_ data: Data, for cacheID: String) {
        guard let url = persistentFileURL(for: cacheID) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persistentFileURL(for cacheID: String) -> URL? {
        guard !cacheID.isEmpty, let persistentImageDirectory else { return nil }
        return persistentImageDirectory.appendingPathComponent(persistentFileName(for: cacheID), isDirectory: false)
    }

    private func legacyPersistentFileURL(for cacheID: String) -> URL? {
        guard !cacheID.isEmpty, let legacyPersistentImageDirectory else { return nil }
        return legacyPersistentImageDirectory.appendingPathComponent(persistentFileName(for: cacheID), isDirectory: false)
    }

    private func persistentFileName(for cacheID: String) -> String {
        let digest = SHA256.hash(data: Data(cacheID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return digest
    }

    private func validPersistentData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= 20 * 1_024 * 1_024 else { return nil }
        return data
    }

    private func isPublicCacheURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil else { return false }
        let containsSensitiveQuery = (components.queryItems ?? []).contains { item in
            let key = item.name.lowercased().filter { $0.isLetter || $0.isNumber }
            return [
                "password", "passwd", "secret", "token", "cookie", "passkey", "authkey",
                "authorization", "apikey", "signature", "credential", "rss", "username", "email"
            ].contains { key.contains($0) }
        }
        if containsSensitiveQuery { return false }
        let containsSensitivePath = components.path.split(separator: "/").contains { rawSegment in
            let segment = String(rawSegment)
            let normalized = segment.lowercased().filter { $0.isLetter || $0.isNumber }
            return ["token", "secret", "passkey", "authkey", "apikey", "credential"].contains { normalized.contains($0) }
                || (segment.count >= 24 && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        }
        return !containsSensitivePath
    }

    private func hasSensitiveImageHeaders(_ headers: [String: String]) -> Bool {
        headers.keys.contains { key in
            let normalized = key.lowercased()
            return normalized == "cookie" || normalized == "authorization" || normalized.contains("token")
        }
    }

    private func isSiteIconCache(_ cacheID: String?) -> Bool {
        guard let cacheID else { return false }
        return cacheID.hasPrefix("site-icon|")
    }

    private func isResourceCoverCache(_ cacheID: String?) -> Bool {
        guard let cacheID else { return false }
        return cacheID.hasPrefix("resource-cover|")
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
        let cost = clampedInt(
            Double(image.size.width * image.size.height * image.scale * image.scale * 4)
        )
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() { cache.removeAllObjects() }
}

private func decodedRemoteDisplayImage(_ data: Data, maximumPixelSize: Int = 1_200) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize)
    ]
    if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
        return UIImage(cgImage: image)
    }
    guard let decoded = UIImage(data: data) else { return nil }
    return decoded.preparingForDisplay() ?? decoded
}

private func isRemoteImagePlaceholderResponse(
    _ response: HTTPURLResponse,
    data: Data,
    url: URL
) -> Bool {
    let path = url.path.lowercased()
    guard path.hasPrefix("/api/v1/site/image/")
            || path.hasPrefix("/api/v1/media/image/")
            || path.hasPrefix("/api/v1/system/image/") else {
        return false
    }

    // The backend uses no-cache headers for both successful proxy responses
    // and its fallback image. Headers alone therefore cannot identify the
    // placeholder; inspect the actual PNG dimensions and payload size instead.
    // Harvest's fallback is a very small 200 x 280 PNG. Detect it even when an
    // intermediary strips or changes the response headers.
    guard data.count <= 2_048,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
        return false
    }
    return width == 200 && height == 280
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
        // Site logos are rendered at a small size. Capping decoded frames prevents
        // several GIF logos from retaining hundreds of full RGBA frames while scrolling.
        let maximumFrameCount = 90
        let frameStep = max(1, Int(ceil(Double(frameCount) / Double(maximumFrameCount))))

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, clampedInt(maximumPixelSize))
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
        let decodedBytes = decodedFrames.reduce(0.0) { partial, image in
            partial + Double(image.size.width * image.size.height * image.scale * image.scale * 4)
        }
        memoryCost = clampedInt(decodedBytes)
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
    private var displayedAnimatedImage: RemoteAnimatedImage?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func display(_ animatedImage: RemoteAnimatedImage) {
        if displayedCacheKey == animatedImage.cacheKey {
            displayedAnimatedImage = animatedImage
            startRemoteAnimationIfNeeded()
            return
        }
        displayedCacheKey = animatedImage.cacheKey
        displayedAnimatedImage = animatedImage
        stopRemoteAnimation()
        image = animatedImage.frames.first
        startRemoteAnimationIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopRemoteAnimation()
        } else {
            startRemoteAnimationIfNeeded()
        }
    }

    func stopRemoteAnimation() {
        layer.removeAnimation(forKey: "harvest.site-logo.animation")
    }

    private func startRemoteAnimationIfNeeded() {
        guard window != nil,
              layer.animation(forKey: "harvest.site-logo.animation") == nil,
              let animatedImage = displayedAnimatedImage,
              animatedImage.frames.count > 1 else {
            return
        }

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

    static func dismantleUIView(_ imageView: AnimatedRemoteUIImageView, coordinator: Void) {
        imageView.stopRemoteAnimation()
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

private func isLikelyPageChromeImageURL(_ url: URL) -> Bool {
    let value = (url.path + "?" + (url.query ?? "")).lowercased()
    return [
        "favicon", "/logo", "logo.", "_logo", "-logo",
        "avatar", "userpic", "/smil", "/emoji", "/badge",
        "loading", "spinner", "blank.", "no-image", "no_image",
        "placeholder", "default-avatar"
    ].contains { value.contains($0) }
}

private enum LinkedMediaReference {
    case douban(id: String)
    case tmdb(kind: String, id: String)

    var apiPath: String {
        switch self {
        case let .douban(id):
            return "/api/option/douban/subject/\(id)"
        case let .tmdb(kind, id):
            return "/api/tmdb/\(kind)/\(id)"
        }
    }

    var isTMDB: Bool {
        if case .tmdb = self { return true }
        return false
    }
}

private func linkedMediaReference(from url: URL) -> LinkedMediaReference? {
    let host = url.host?.lowercased() ?? ""
    let components = url.pathComponents.filter { $0 != "/" }
    let lowered = components.map { $0.lowercased() }
    if host.hasSuffix("douban.com"),
       let index = lowered.lastIndex(of: "subject"),
       components.indices.contains(index + 1) {
        let id = components[index + 1]
        if !id.isEmpty, id.allSatisfy({ $0.isNumber }) { return .douban(id: id) }
    }
    if host == "themoviedb.org" || host.hasSuffix(".themoviedb.org") {
        for kind in ["movie", "tv"] {
            guard let index = lowered.lastIndex(of: kind),
                  components.indices.contains(index + 1) else { continue }
            let id = components[index + 1].split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            if !id.isEmpty, id.allSatisfy({ $0.isNumber }) { return .tmdb(kind: kind, id: id) }
        }
    }
    return nil
}

private func remotePosterURLFromMediaResponse(
    _ data: Data,
    reference: LinkedMediaReference
) -> URL? {
    guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return nil
    }

    func imageValues(
        _ value: Any,
        depth: Int = 0,
        acceptsGenericURL: Bool = false
    ) -> [String] {
        guard depth < 7 else { return [] }
        if let value = value as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? [] : [normalized]
        }
        if let values = value as? [Any] {
            return values.flatMap {
                imageValues($0, depth: depth + 1, acceptsGenericURL: acceptsGenericURL)
            }
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        let imageKeys = [
            "poster_path", "posterPath", "poster_url", "posterUrl", "poster",
            "cover_url", "coverUrl", "cover", "image_url", "imageUrl", "image",
            "pic", "large", "normal", "medium", "small"
        ]
        var values = imageKeys.flatMap { key in
            dictionary[key].map {
                imageValues($0, depth: depth + 1, acceptsGenericURL: true)
            } ?? []
        }
        if acceptsGenericURL {
            values.append(contentsOf: ["url", "src", "href"].flatMap { key in
                dictionary[key].map {
                    imageValues($0, depth: depth + 1, acceptsGenericURL: true)
                } ?? []
            })
        }
        if !values.isEmpty { return values }
        for key in ["data", "result", "subject", "target", "movie", "tv", "media", "images"] {
            if let nested = dictionary[key] {
                values.append(contentsOf: imageValues(nested, depth: depth + 1))
            }
        }
        return values
    }

    for rawValue in imageValues(object) {
        var value = rawValue
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        if reference.isTMDB, value.hasPrefix("/") {
            value = "https://image.tmdb.org/t/p/w342\(value)"
        } else if reference.isTMDB, value.lowercased().contains("image.tmdb.org/t/p/") {
            for size in ["original", "w500", "w780", "w1280"] {
                value = value.replacingOccurrences(
                    of: "/t/p/\(size)/",
                    with: "/t/p/w342/",
                    options: [.caseInsensitive]
                )
            }
        } else if value.hasPrefix("//") {
            value = "https:\(value)"
        }
        value = normalizedRemoteImageURL(value)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !isLikelyPageChromeImageURL(url) else { continue }
        return url
    }
    return nil
}

private func isLinkedMediaPageURL(_ url: URL) -> Bool {
    let host = url.host?.lowercased() ?? ""
    let path = url.path.lowercased()
    let isDoubanSubject = ((host == "movie.douban.com" || host == "www.douban.com")
        && path.contains("/subject/"))
        || (host == "m.douban.com" && path.contains("/movie/subject/"))
    if isDoubanSubject {
        return true
    }
    if (host == "themoviedb.org" || host.hasSuffix(".themoviedb.org")),
       path.range(
        of: #"/(?:[a-z]{2}(?:-[a-z]{2})?/)?(?:movie|tv)/\d+"#,
        options: .regularExpression
       ) != nil {
        return true
    }
    return false
}

private func remoteMediaPageURLFromHTML(_ data: Data, baseURL: URL) -> URL? {
    guard !isLinkedMediaPageURL(baseURL) else { return nil }
    let html = String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "\\/", with: "/")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&#x2F;", with: "/")
        .replacingOccurrences(of: "&#47;", with: "/")
    guard !html.isEmpty else { return nil }
    let patterns = [
        #"(?i)((?:https?:)?//(?:(?:movie|www)\.douban\.com/subject|m\.douban\.com/movie/subject)/\d+/?(?:\?[^\"'<>\s]*)?)"#,
        #"(?i)((?:https?:)?//(?:www\.)?themoviedb\.org/(?:[a-z]{2}(?:-[a-z]{2})?/)?(?:movie|tv)/\d+(?:-[^\"'<>/?\s]+)?)"#
    ]
    var documents = [html]
    if let decoded = html.removingPercentEncoding, decoded != html {
        documents.append(decoded)
    }
    for document in documents {
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(document.startIndex..<document.endIndex, in: document)
            for match in expression.matches(in: document, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: document) else { continue }
                var value = String(document[valueRange])
                if value.hasPrefix("//") { value = "https:\(value)" }
                guard let url = URL(string: value), isLinkedMediaPageURL(url) else { continue }
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = "https"
                components?.query = nil
                components?.fragment = nil
                if let normalizedURL = components?.url { return normalizedURL }
            }
        }
    }
    return nil
}

private func remoteImageURLFromHTML(_ data: Data, baseURL: URL) -> URL? {
    // Tracker pages are not consistently UTF-8. Lossy decoding still preserves
    // ASCII attribute names and URLs, which are the only parts needed here.
    let html = String(decoding: data, as: UTF8.self)
    guard !html.isEmpty else { return nil }
    let patterns = [
        #"(?is)<img[^>]+(?:class|id)\s*=\s*[\"'][^\"']*(?:poster|cover|torrentpic|screenshot)[^\"']*[\"'][^>]+(?:src|data-src|data-original|data-lazy-src|data-thumb|srcset)\s*=\s*[\"']([^\"']+)[\"']"#,
        #"(?is)<img[^>]+(?:src|data-src|data-original|data-lazy-src|data-thumb|srcset)\s*=\s*[\"']([^\"']+)[\"'][^>]+(?:class|id)\s*=\s*[\"'][^\"']*(?:poster|cover|torrentpic|screenshot)[^\"']*[\"']"#,
        #"(?is)<(?:td|div|section|article)[^>]+(?:class|id)\s*=\s*[\"'][^\"']*(?:kdescr|torrent[-_ ]?(?:description|content))[^\"']*[\"'][^>]*>(?:(?!</(?:td|div|section|article)\s*>).)*?<img[^>]+(?:src|data-src|data-original|data-lazy-src|data-thumb|srcset)\s*=\s*[\"']([^\"']+)[\"']"#,
        #"(?is)(?:data-poster|data-cover|data-image|data-preview)\s*=\s*[\"']([^\"']+)[\"']"#,
        #"(?is)[\"'](?:poster|poster_url|cover|cover_url|image|image_url)[\"']\s*:\s*[\"'](https?:\\?/\\?/[^\"']+)[\"']"#,
        #"(?is)<meta[^>]+(?:property|name)\s*=\s*[\"'](?:og:image|twitter:image)[\"'][^>]+content\s*=\s*[\"']([^\"']+)[\"']"#,
        #"(?is)<meta[^>]+content\s*=\s*[\"']([^\"']+)[\"'][^>]+(?:property|name)\s*=\s*[\"'](?:og:image|twitter:image)[\"']"#,
        #"(?is)<link[^>]+rel\s*=\s*[\"']image_src[\"'][^>]+href\s*=\s*[\"']([^\"']+)[\"']"#
    ]
    for pattern in patterns {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html) else { continue }
            var value = String(html[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x2F;", with: "/")
                .replacingOccurrences(of: "&#47;", with: "/")
                .replacingOccurrences(of: "\\/", with: "/")
            // srcset stores density/width descriptors after each URL. The
            // first source is sufficient for the compact resource card.
            if value.contains(",") || value.range(of: #"\s(?:\d+(?:\.\d+)?x|\d+w)(?:\s|,|$)"#, options: .regularExpression) != nil {
                if let firstSource = value.split(separator: ",", maxSplits: 1).first,
                   let sourceURL = firstSource
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .first {
                    value = String(sourceURL)
                }
            }
            if value.hasPrefix("//") { value = "https:\(value)" }
            guard !value.isEmpty,
                  !value.lowercased().hasPrefix("data:") else { continue }
            if let absolute = URL(string: value),
               ["http", "https"].contains(absolute.scheme?.lowercased() ?? ""),
               !isLikelyPageChromeImageURL(absolute) {
                return absolute
            }
            if let relative = URL(string: value, relativeTo: baseURL)?.absoluteURL,
               ["http", "https"].contains(relative.scheme?.lowercased() ?? ""),
               !isLikelyPageChromeImageURL(relative) {
                return relative
            }
        }
    }
    return nil
}

private func remoteImageURLFromResponse(_ data: Data, baseURL: URL) -> URL? {
    guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return nil
    }

    func strings(_ value: Any, depth: Int = 0) -> [String] {
        guard depth < 6 else { return [] }
        if let text = value as? String {
            let normalized = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "\\/", with: "/")
            if normalized.hasPrefix("<") {
                return remoteImageURLFromHTML(Data(normalized.utf8), baseURL: baseURL)
                    .map { [$0.absoluteString] } ?? []
            }
            return normalized.isEmpty ? [] : [normalized]
        }
        if let dictionary = value as? [String: Any] {
            var result: [String] = []
            for (key, nested) in dictionary {
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("image") || normalizedKey.contains("poster")
                    || normalizedKey.contains("cover") || normalizedKey.contains("thumb")
                    || ["url", "src", "href", "path"].contains(normalizedKey) {
                    result.append(contentsOf: strings(nested, depth: depth + 1))
                } else if depth < 3 {
                    result.append(contentsOf: strings(nested, depth: depth + 1))
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.flatMap { strings($0, depth: depth + 1) }
        }
        return []
    }

    for value in strings(object) {
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !isLikelyPageChromeImageURL(url) else { continue }
        return url
    }
    return nil
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

private func forwardedRemoteImageHeaders(
    _ headers: [String: String],
    from sourceURL: URL,
    to destinationURL: URL
) -> [String: String] {
    var forwarded = headers
    let crossesHost = sourceURL.host?.lowercased() != destinationURL.host?.lowercased()
    if crossesHost {
        forwarded.keys.filter {
            let name = $0.lowercased()
            return name == "cookie" || name.contains("authorization") || name == "referer"
                || name.contains("token") || name.contains("api-key")
                || name.contains("apikey") || name.contains("secret")
        }.forEach { forwarded.removeValue(forKey: $0) }
        if var origin = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) {
            origin.path = "/"
            origin.query = nil
            origin.fragment = nil
            if let originURL = origin.url {
                forwarded["Referer"] = originURL.absoluteString
            }
        }
    } else if !forwarded.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }) {
        forwarded["Referer"] = sourceURL.absoluteString
    }
    if isLinkedMediaPageURL(destinationURL) {
        forwarded["User-Agent"] = doubanImageUserAgent
        if isDoubanImageHost(destinationURL.host?.lowercased() ?? "") {
            forwarded["Referer"] = doubanImageReferer
        }
    }
    return remoteImageHeaders(for: destinationURL, additional: forwarded)
}

func remoteImageCacheKey(url: URL, headers: [String: String], variant: String = "") -> String {
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
    let baseKey = "\(url.absoluteString)|\(headerPart)"
    return variant.isEmpty ? baseKey : "\(baseKey)|variant=\(variant)"
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let headers: [String: String]
    let persistentCacheID: String?
    let maximumPixelSize: Int
    let prefersLinkedMediaPoster: Bool
    let linkedMediaAPI: RemoteMediaPosterAPI?
    private let onFailure: (() -> Void)?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var loadedImage: UIImage?

    init(
        url: URL?,
        headers: [String: String] = [:],
        persistentCacheID: String? = nil,
        maximumPixelSize: Int = 1_200,
        prefersLinkedMediaPoster: Bool = false,
        linkedMediaAPI: RemoteMediaPosterAPI? = nil,
        onFailure: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.headers = headers
        self.persistentCacheID = persistentCacheID
        self.maximumPixelSize = max(1, maximumPixelSize)
        self.prefersLinkedMediaPoster = prefersLinkedMediaPoster
        self.linkedMediaAPI = linkedMediaAPI
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
        .task(id: requestKey, priority: .utility) {
            loadedImage = nil
            guard let url,
                  let normalizedURL = URL(string: normalizedRemoteImageURL(url.absoluteString)) else {
                if !Task.isCancelled { await MainActor.run { onFailure?() } }
                return
            }
            let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: headers)
            let variant = prefersLinkedMediaPoster ? "linked-media-poster" : ""
            let cacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders, variant: variant)
            let decodedCacheKey = "\(cacheKey)|decoded|\(maximumPixelSize)"
            if let cached = RemoteDecodedImageCache.shared.image(for: decodedCacheKey) {
                loadedImage = cached
                return
            }
            do {
                let data = try await RemoteImageDataCache.shared.data(
                    for: normalizedURL,
                    headers: effectiveHeaders,
                    persistentCacheID: persistentCacheID,
                    prefersLinkedMediaPoster: prefersLinkedMediaPoster,
                    linkedMediaAPI: linkedMediaAPI
                )
                guard !Task.isCancelled else { return }
                let pixelSize = maximumPixelSize
                let image = await Task.detached(priority: .utility) { () -> UIImage? in
                    decodedRemoteDisplayImage(data, maximumPixelSize: pixelSize)
                }.value
                guard !Task.isCancelled, let image else {
                    if let persistentCacheID {
                        await RemoteImageDataCache.shared.removePersistentData(for: persistentCacheID)
                    }
                    if !Task.isCancelled { await MainActor.run { onFailure?() } }
                    return
                }
                RemoteDecodedImageCache.shared.insert(image, for: decodedCacheKey)
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
        let cacheKey = remoteImageCacheKey(
            url: normalizedURL,
            headers: remoteImageHeaders(for: normalizedURL, additional: headers),
            variant: prefersLinkedMediaPoster ? "linked-media-poster" : ""
        )
        return "\(cacheKey)|decoded|\(maximumPixelSize)"
    }
}

struct RemoteImageCandidate: Identifiable {
    let url: URL
    let headers: [String: String]
    let persistentCacheID: String?
    let prefersLinkedMediaPoster: Bool
    let linkedMediaAPI: RemoteMediaPosterAPI?

    init(
        url: URL,
        headers: [String: String] = [:],
        persistentCacheID: String? = nil,
        prefersLinkedMediaPoster: Bool = false,
        linkedMediaAPI: RemoteMediaPosterAPI? = nil
    ) {
        self.url = url
        self.headers = headers
        self.persistentCacheID = persistentCacheID
        self.prefersLinkedMediaPoster = prefersLinkedMediaPoster
        self.linkedMediaAPI = linkedMediaAPI
    }

    var id: String {
        remoteImageCacheKey(
            url: url,
            headers: remoteImageHeaders(for: url, additional: headers),
            variant: prefersLinkedMediaPoster ? "linked-media-poster" : ""
        )
    }
}

struct CachedRemoteImageCandidates<Content: View, Placeholder: View>: View {
    let candidates: [RemoteImageCandidate]
    let maximumPixelSize: Int
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    @State private var candidateIndex = 0
    @State private var restoredImage: UIImage?
    @State private var isRestoring = true

    init(
        candidates: [RemoteImageCandidate],
        maximumPixelSize: Int = 1_200,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.candidates = candidates
        self.maximumPixelSize = max(1, maximumPixelSize)
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let restoredImage {
                content(Image(uiImage: restoredImage))
            } else if isRestoring {
                placeholder()
            } else if candidateIndex < candidates.count {
                let candidate = candidates[candidateIndex]
                CachedRemoteImage(
                    url: candidate.url,
                    headers: candidate.headers,
                    persistentCacheID: candidate.persistentCacheID,
                    maximumPixelSize: maximumPixelSize,
                    prefersLinkedMediaPoster: candidate.prefersLinkedMediaPoster,
                    linkedMediaAPI: candidate.linkedMediaAPI,
                    onFailure: advanceCandidate,
                    content: content,
                    placeholder: placeholder
                )
            } else {
                placeholder()
            }
        }
        .task(id: restoreKey, priority: .utility) { await restorePersistedCandidate() }
    }

    private var candidateKey: String { candidates.map(\.id).joined(separator: "|") }
    private var restoreKey: String { "\(candidateKey)|decoded|\(maximumPixelSize)" }

    private func advanceCandidate() {
        candidateIndex = min(candidateIndex + 1, candidates.count)
    }

    @MainActor private func restorePersistedCandidate() async {
        restoredImage = nil
        candidateIndex = 0
        isRestoring = true
        defer { isRestoring = false }

        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled,
                  let persistentCacheID = candidate.persistentCacheID,
                  let normalizedURL = URL(string: normalizedRemoteImageURL(candidate.url.absoluteString)) else {
                continue
            }
            let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: candidate.headers)
            let variant = candidate.prefersLinkedMediaPoster ? "linked-media-poster" : ""
            let cacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders, variant: variant)
            let decodedCacheKey = "\(cacheKey)|decoded|\(maximumPixelSize)"
            if let cached = RemoteDecodedImageCache.shared.image(for: decodedCacheKey) {
                candidateIndex = index
                restoredImage = cached
                return
            }
            guard let data = await RemoteImageDataCache.shared.persistentData(
                for: persistentCacheID,
                requestURL: normalizedURL,
                headers: effectiveHeaders
            ) else { continue }
            let pixelSize = maximumPixelSize
            let image = await Task.detached(priority: .utility) {
                decodedRemoteDisplayImage(data, maximumPixelSize: pixelSize)
            }.value
            guard !Task.isCancelled else { return }
            guard let image else {
                await RemoteImageDataCache.shared.removePersistentData(for: persistentCacheID)
                continue
            }
            RemoteDecodedImageCache.shared.insert(image, for: decodedCacheKey)
            candidateIndex = index
            restoredImage = image
            return
        }
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
        .task(id: requestKey, priority: .utility) { await loadCurrentCandidate() }
        .onChange(of: candidateKey) { _, _ in
            candidateIndex = 0
            loadedImage = nil
        }
    }

    private var candidateKey: String { candidates.map(\.id).joined(separator: "|") }

    private var requestKey: String {
        guard candidateIndex < candidates.count else { return "\(candidateKey)|exhausted" }
        return "\(candidateKey)|\(candidateIndex)|\(max(1, clampedInt(maximumPixelSize.rounded(.up))))"
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
        let variant = candidate.prefersLinkedMediaPoster ? "linked-media-poster" : ""
        let dataCacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders, variant: variant)
        let decodedCacheKey = "\(dataCacheKey)|animated|\(max(1, clampedInt(maximumPixelSize.rounded(.up))))"
        if let cached = RemoteAnimatedImageCache.shared.image(for: decodedCacheKey) {
            loadedImage = cached
            return
        }

        do {
            let data = try await RemoteImageDataCache.shared.data(
                for: normalizedURL,
                headers: effectiveHeaders,
                persistentCacheID: candidate.persistentCacheID,
                prefersLinkedMediaPoster: candidate.prefersLinkedMediaPoster,
                linkedMediaAPI: candidate.linkedMediaAPI
            )
            guard !Task.isCancelled else { return }
            let pixelSize = maximumPixelSize
            let decoded = await Task.detached(priority: .utility) {
                RemoteAnimatedImage(data: data, cacheKey: decodedCacheKey, maximumPixelSize: pixelSize)
            }.value
            guard !Task.isCancelled, let decoded else {
                if let persistentCacheID = candidate.persistentCacheID {
                    await RemoteImageDataCache.shared.removePersistentData(for: persistentCacheID)
                }
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
                  let normalizedURL = URL(string: normalizedRemoteImageURL(candidate.url.absoluteString)) else {
                continue
            }
            let effectiveHeaders = remoteImageHeaders(for: normalizedURL, additional: candidate.headers)
            guard let data = await RemoteImageDataCache.shared.persistentData(
                for: persistentCacheID,
                requestURL: normalizedURL,
                headers: effectiveHeaders
            ) else { continue }
            let variant = candidate.prefersLinkedMediaPoster ? "linked-media-poster" : ""
            let dataCacheKey = remoteImageCacheKey(url: normalizedURL, headers: effectiveHeaders, variant: variant)
            let decodedCacheKey = "\(dataCacheKey)|animated|\(max(1, clampedInt(maximumPixelSize.rounded(.up))))"
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
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(
                                cornerRadius: HarvestTheme.cardCornerRadius,
                                style: .continuous
                            )
                        )
                }
            }
        }
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
    @State private var availableAppUpdate: String?
    @State private var handledNoticePresentation = 0
    @State private var lastNonSearchTab = 2

    private var showsNewsTab: Bool {
        appState.mediaTMDBEnabled || appState.mediaDoubanEnabled
    }

    private var showsAdminTabs: Bool {
        appState.profile?.isSuperuser == true
            || (appState.isRestoringSession && appState.hasStoredSession)
    }

    private var defaultContentTab: Int {
        showsAdminTabs ? 2 : 3
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
            .toolbar(appState.selectedTab == 5 ? .hidden : .visible, for: .navigationBar)
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
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill").symbolRenderingMode(.hierarchical)
                    }
                        .accessibilityLabel("设置")
                }
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
        .onChange(of: appState.profile?.isSuperuser) { _, isSuperuser in
            guard isSuperuser != true,
                  !appState.isRestoringSession,
                  (appState.selectedTab == 1 || appState.selectedTab == 2) else { return }
            appState.selectedTab = 3
        }
        .onChange(of: appState.searchPresentationGeneration) { _, _ in
            appState.selectedTab = 5
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
            if showsAdminTabs {
                Tab("站点", systemImage: "globe.asia.australia.fill", value: 1) { SitesView() }
                Tab("仪表盘", systemImage: "chart.bar.xaxis", value: 2) { DashboardView() }
            }
            Tab("下载", systemImage: "arrow.down.circle.fill", value: 3) { DownloadsView() }
            Tab("搜索", systemImage: "magnifyingglass", value: 5) {
                SearchView { appState.selectedTab = lastNonSearchTab }
            }
        }
        .tint(appState.accent.color)
    }

    private var legacyTabView: some View {
        TabView(selection: $appState.selectedTab) {
            if showsNewsTab {
                NewsView().tabItem { Label("资讯", systemImage: "newspaper.fill") }.tag(0)
            }
            if showsAdminTabs {
                SitesView().tabItem { Label("站点", systemImage: "globe.asia.australia.fill") }.tag(1)
                DashboardView().tabItem { Label("仪表盘", systemImage: "chart.bar.xaxis") }.tag(2)
            }
            DownloadsView().tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }.tag(3)
            SearchView { appState.selectedTab = lastNonSearchTab }
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(5)
        }
        .tint(appState.accent.color)
    }

    private func presentPendingNoticeIfNeeded() {
        guard appState.noticePresentationGeneration != handledNoticePresentation else { return }
        handledNoticePresentation = appState.noticePresentationGeneration
        showingNotices = true
    }

    private func validContentTab(_ candidate: Int) -> Int {
        if candidate == 0, showsNewsTab { return candidate }
        if candidate == 3 { return candidate }
        if showsAdminTabs, (1...3).contains(candidate) { return candidate }
        return defaultContentTab
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
        VStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.13))
                        .frame(width: 30, height: 30)
                    if feedback.phase == .running {
                        ProgressView()
                            .controlSize(.small)
                            .tint(color)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(color)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(feedback.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if let message = feedback.message, !message.isEmpty {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(feedback.phase == .running ? .updatesFrequently : [])
            Spacer(minLength: 0)
        }
        .safeAreaPadding(.top, 8)
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
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
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            appState.presentedError = "无法获取当前页面截图"
            return
        }
        isCapturing = true
        let restorePrivacy = !appState.privacyMode
        if restorePrivacy {
            appState.setPrivacyMode(true)
            await waitForScreenUpdate(window)
        }

        defer {
            if restorePrivacy { appState.setPrivacyMode(false) }
            isCapturing = false
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

    @MainActor private func waitForScreenUpdate(_ window: UIWindow) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                DispatchQueue.main.async {
                    window.setNeedsLayout()
                    window.layoutIfNeeded()
                    continuation.resume()
                }
            }
        }
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

struct FlowingSymbolBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let color: Color
    var size: CGFloat = 38
    var showsProgress = false

    private var cornerRadius: CGFloat { max(5, size * 0.2) }
    private var glowLineWidth: CGFloat { max(1.15, size * 0.05) }
    private var phaseOffset: Double {
        Double(icon.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 })
    }

    var body: some View {
        badge
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
                .padding(1.1)

            if showsProgress {
                ProgressView()
                    .tint(.white)
                    .controlSize(size >= 40 ? .regular : .small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(0.24), lineWidth: 0.7)

            HardwareFlowingBorder(
                color: color,
                lineWidth: glowLineWidth,
                cornerRadius: cornerRadius,
                circular: false,
                phaseOffset: phaseOffset,
                paused: reduceMotion
            )
        }
    }
}

struct FlowingCircleBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    var lineWidth: CGFloat = 1.8

    var body: some View {
        HardwareFlowingBorder(
            color: color,
            lineWidth: lineWidth,
            cornerRadius: 0,
            circular: true,
            phaseOffset: 0,
            paused: reduceMotion
        )
        .allowsHitTesting(false)
    }
}

private struct HardwareFlowingBorder: UIViewRepresentable {
    let color: Color
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    let circular: Bool
    let phaseOffset: Double
    let paused: Bool

    func makeUIView(context: Context) -> HardwareFlowingBorderView {
        let view = HardwareFlowingBorderView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HardwareFlowingBorderView, context: Context) {
        view.configure(
            color: UIColor(color),
            lineWidth: lineWidth,
            cornerRadius: cornerRadius,
            circular: circular,
            phaseOffset: phaseOffset,
            paused: paused
        )
    }

    static func dismantleUIView(_ view: HardwareFlowingBorderView, coordinator: Void) {
        view.stopAnimating()
    }
}

private final class HardwareFlowingBorderView: UIView {
    private let clippedEffectLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()
    private var glowColor = UIColor.systemBlue
    private var borderLineWidth: CGFloat = 1.8
    private var borderCornerRadius: CGFloat = 0
    private var isCircular = false
    private var phaseOffset = 0.0
    private var animationPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        clippedEffectLayer.mask = borderMaskLayer
        clippedEffectLayer.masksToBounds = false
        clippedEffectLayer.shadowOffset = .zero
        layer.addSublayer(clippedEffectLayer)

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        // SwiftUI AngularGradient starts at the trailing edge. Matching that
        // origin keeps the hardware-rendered highlight in its original position.
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.masksToBounds = false
        gradientLayer.shouldRasterize = true
        gradientLayer.rasterizationScale = UIScreen.main.scale
        clippedEffectLayer.addSublayer(gradientLayer)

        borderMaskLayer.fillColor = UIColor.clear.cgColor
        borderMaskLayer.strokeColor = UIColor.white.cgColor
        borderMaskLayer.lineCap = .round
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clippedEffectLayer.frame = bounds
        let gradientSide = hypot(bounds.width, bounds.height)
        gradientLayer.frame = CGRect(
            x: (bounds.width - gradientSide) / 2,
            y: (bounds.height - gradientSide) / 2,
            width: gradientSide,
            height: gradientSide
        )
        borderMaskLayer.frame = clippedEffectLayer.bounds
        let inset = borderLineWidth / 2
        let pathRect = bounds.insetBy(dx: inset, dy: inset)
        borderMaskLayer.path = isCircular
            ? UIBezierPath(ovalIn: pathRect).cgPath
            : UIBezierPath(
                roundedRect: pathRect,
                cornerRadius: max(0, borderCornerRadius - inset)
            ).cgPath
        borderMaskLayer.lineWidth = borderLineWidth
        clippedEffectLayer.shadowColor = glowColor.cgColor
        clippedEffectLayer.shadowOpacity = isCircular ? 0.28 : 0.30
        clippedEffectLayer.shadowRadius = isCircular
            ? 2
            : max(1.2, min(bounds.width, bounds.height) * 0.055)
        restartAnimationIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            restartAnimationIfNeeded()
        }
    }

    func configure(
        color: UIColor,
        lineWidth: CGFloat,
        cornerRadius: CGFloat,
        circular: Bool,
        phaseOffset: Double,
        paused: Bool
    ) {
        let needsAnimationRestart = self.phaseOffset != phaseOffset || animationPaused != paused
        glowColor = color
        borderLineWidth = max(0.75, lineWidth)
        borderCornerRadius = cornerRadius
        isCircular = circular
        self.phaseOffset = phaseOffset
        animationPaused = paused
        gradientLayer.colors = isCircular
            ? [
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0.08).cgColor,
                color.withAlphaComponent(0.28).cgColor,
                color.withAlphaComponent(0.62).cgColor,
                UIColor.white.withAlphaComponent(0.92).cgColor,
                color.withAlphaComponent(0.24).cgColor,
                color.withAlphaComponent(0).cgColor
            ]
            : [
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0.06).cgColor,
                color.withAlphaComponent(0.24).cgColor,
                color.withAlphaComponent(0.56).cgColor,
                UIColor.white.withAlphaComponent(0.90).cgColor,
                color.withAlphaComponent(0.22).cgColor,
                color.withAlphaComponent(0).cgColor
            ]
        gradientLayer.locations = [0, 0.54, 0.62, 0.74, 0.86, 0.93, 0.975, 1]
        setNeedsLayout()
        if needsAnimationRestart { restartAnimationIfNeeded(force: true) }
    }

    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "harvest.flowing-border")
    }

    private func restartAnimationIfNeeded(force: Bool = false) {
        guard window != nil, !bounds.isEmpty else { return }
        if animationPaused {
            stopAnimating()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.setAffineTransform(
                CGAffineTransform(rotationAngle: (42 + phaseOffset) * .pi / 180)
            )
            CATransaction.commit()
            return
        }
        if !force, gradientLayer.animation(forKey: "harvest.flowing-border") != nil { return }
        stopAnimating()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.setAffineTransform(.identity)
        CATransaction.commit()
        let duration = 3.6
        let elapsed = Date().timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: duration)
        let globalPhase = elapsed / duration * Double.pi * 2
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = globalPhase + phaseOffset * .pi / 180
        animation.byValue = Double.pi * 2
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        gradientLayer.add(animation, forKey: "harvest.flowing-border")
    }
}

struct HardwareProgressShimmer: UIViewRepresentable {
    let color: Color
    var paused = false

    func makeUIView(context: Context) -> HardwareProgressShimmerView {
        let view = HardwareProgressShimmerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HardwareProgressShimmerView, context: Context) {
        view.configure(color: UIColor(color), paused: paused)
    }

    static func dismantleUIView(_ view: HardwareProgressShimmerView, coordinator: Void) {
        view.stopAnimating()
    }
}

struct HardwareBreathingSymbolBadge: UIViewRepresentable {
    let icon: String
    let color: Color
    var paused = false

    func makeUIView(context: Context) -> HardwareBreathingSymbolBadgeView {
        let view = HardwareBreathingSymbolBadgeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HardwareBreathingSymbolBadgeView, context: Context) {
        view.configure(icon: icon, color: UIColor(color), paused: paused)
    }

    static func dismantleUIView(_ view: HardwareBreathingSymbolBadgeView, coordinator: Void) {
        view.stopAnimating()
    }
}

final class HardwareBreathingSymbolBadgeView: UIView {
    private let imageView = UIImageView()
    private var animationPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        imageView.contentMode = .center
        imageView.tintColor = .white
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        layer.cornerRadius = min(3.5, min(bounds.width, bounds.height) * 0.25)
        restartAnimationIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            restartAnimationIfNeeded()
        }
    }

    func configure(icon: String, color: UIColor, paused: Bool) {
        let needsRestart = animationPaused != paused
        animationPaused = paused
        backgroundColor = color
        let configuration = UIImage.SymbolConfiguration(pointSize: 6.5, weight: .bold)
        imageView.image = UIImage(systemName: icon, withConfiguration: configuration)
        if needsRestart { restartAnimationIfNeeded(force: true) }
    }

    func stopAnimating() {
        layer.removeAnimation(forKey: "harvest.breathing-symbol")
    }

    private func restartAnimationIfNeeded(force: Bool = false) {
        guard window != nil, !bounds.isEmpty else { return }
        if animationPaused {
            stopAnimating()
            layer.opacity = 1
            return
        }
        if !force, layer.animation(forKey: "harvest.breathing-symbol") != nil { return }
        stopAnimating()
        layer.opacity = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.3
        animation.toValue = 1
        animation.duration = 1.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "harvest.breathing-symbol")
    }
}

final class HardwareProgressShimmerView: UIView {
    private let shimmerLayer = CAGradientLayer()
    private var animationPaused = false
    private var previousSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.shouldRasterize = true
        shimmerLayer.rasterizationScale = UIScreen.main.scale
        layer.addSublayer(shimmerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(max(bounds.width * 0.24, 10), 30)
        shimmerLayer.frame = CGRect(x: -width, y: -2, width: width, height: bounds.height + 4)
        let sizeChanged = abs(previousSize.width - bounds.width) > 0.5
            || abs(previousSize.height - bounds.height) > 0.5
        previousSize = bounds.size
        restartAnimationIfNeeded(force: sizeChanged)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            restartAnimationIfNeeded()
        }
    }

    func configure(color: UIColor, paused: Bool) {
        let needsRestart = animationPaused != paused
        animationPaused = paused
        shimmerLayer.colors = [
            color.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.18).cgColor,
            UIColor.white.withAlphaComponent(0.92).cgColor,
            color.withAlphaComponent(0.30).cgColor,
            color.withAlphaComponent(0).cgColor
        ]
        shimmerLayer.locations = [0, 0.24, 0.5, 0.74, 1]
        if needsRestart { restartAnimationIfNeeded(force: true) }
    }

    func stopAnimating() {
        shimmerLayer.removeAnimation(forKey: "harvest.progress-shimmer")
    }

    private func restartAnimationIfNeeded(force: Bool = false) {
        guard window != nil, bounds.width > 2, bounds.height > 0 else { return }
        if animationPaused {
            stopAnimating()
            return
        }
        if !force, shimmerLayer.animation(forKey: "harvest.progress-shimmer") != nil { return }
        stopAnimating()
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = bounds.width + shimmerLayer.bounds.width * 2
        animation.duration = 2.2
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        shimmerLayer.add(animation, forKey: "harvest.progress-shimmer")
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
