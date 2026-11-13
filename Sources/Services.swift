import Foundation
import AppKit
import ServiceManagement
import UserNotifications

// MARK: - 偏好（UserDefaults；无数据库、无下载历史）

final class WallpaperSettings: ObservableObject {
    static let shared = WallpaperSettings()

    private enum Key {
        static let preferUHD = "dw.preferUHD"
        static let autoDownload = "dw.autoDownload"
        static let autoChange = "dw.autoChange"
        static let dailyHour = "dw.dailyHour"
        static let dailyMinute = "dw.dailyMinute"
        static let directoryPath = "dw.directoryPath"
        static let notifications = "dw.notifications"
        static let lastRunDate = "dw.lastRunDate"
        static let showMenuBarIcon = "dw.showMenuBarIcon"
    }

    private let defaults = UserDefaults.standard

    @Published var preferUHD: Bool = true { didSet { defaults.set(preferUHD, forKey: Key.preferUHD) } }
    @Published var autoDownload: Bool = false { didSet { defaults.set(autoDownload, forKey: Key.autoDownload) } }
    @Published var autoChange: Bool = false { didSet { defaults.set(autoChange, forKey: Key.autoChange) } }
    @Published var dailyHour: Int = 8 { didSet { defaults.set(dailyHour, forKey: Key.dailyHour) } }
    @Published var dailyMinute: Int = 0 { didSet { defaults.set(dailyMinute, forKey: Key.dailyMinute) } }
    @Published var notifications: Bool = false { didSet { defaults.set(notifications, forKey: Key.notifications) } }
    /// 是否显示本应用自己的菜单栏状态项。关闭后由 Dimble 启动器或访达双击打开应用。
    @Published var showMenuBarIcon: Bool = true {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var directoryPath: String? {
        didSet {
            if let p = directoryPath { defaults.set(p, forKey: Key.directoryPath) }
            else { defaults.removeObject(forKey: Key.directoryPath) }
        }
    }
    @Published var lastRunDate: String? {
        didSet {
            if let d = lastRunDate { defaults.set(d, forKey: Key.lastRunDate) }
            else { defaults.removeObject(forKey: Key.lastRunDate) }
        }
    }

    private init() {
        preferUHD = defaults.object(forKey: Key.preferUHD) as? Bool ?? true
        autoDownload = defaults.object(forKey: Key.autoDownload) as? Bool ?? false
        autoChange = defaults.object(forKey: Key.autoChange) as? Bool ?? false
        dailyHour = defaults.object(forKey: Key.dailyHour) as? Int ?? 8
        // 分钟只提供 5 分钟刻度；历史值规整到最近的下整刻度，避免下拉无匹配项。
        let storedMinute = defaults.object(forKey: Key.dailyMinute) as? Int ?? 0
        dailyMinute = max(0, min(55, storedMinute)) / 5 * 5
        notifications = defaults.object(forKey: Key.notifications) as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        directoryPath = defaults.string(forKey: Key.directoryPath)
        lastRunDate = defaults.string(forKey: Key.lastRunDate)
    }
}

// MARK: - Bing 元数据服务

final class BingWallpaperService {
    static let shared = BingWallpaperService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 2
        // 显式直连：系统代理 / 环境变量代理在 Finder 启动与终端启动下不一致。
        config.connectionProxyDictionary = [
            "HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
        ]
        return URLSession(configuration: config)
    }()

    /// 短期元数据缓存，仅内存，不持久化整段响应（规格 6.1 / 7.2）。
    private var cached: (wallpaper: Wallpaper, at: Date)?
    private let cacheTTL: TimeInterval = 15 * 60

    func fetchToday(force: Bool = false) async throws -> Wallpaper {
        if !force, let c = cached, Date().timeIntervalSince(c.at) < cacheTTL {
            return c.wallpaper
        }
        guard var comps = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx") else {
            throw DWError.network("无法构造请求地址")
        }
        // 固定 idx=0&n=1：n>1 会返回历史，违反「仅当天」约束（M0 记录 A-3）。
        comps.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: "0"),
            URLQueryItem(name: "n", value: "1"),
            URLQueryItem(name: "mkt", value: "zh-CN"),
        ]
        guard let url = comps.url else { throw DWError.network("无法构造请求地址") }

        DWLog.net("元数据请求开始 \(url.absoluteString)")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw DWError.network("无有效 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else { throw DWError.http(http.statusCode) }
            let wallpaper = try decodedWallpaper(from: data)
            cached = (wallpaper, Date())
            DWLog.net("元数据成功 URLSession \(data.count) bytes")
            return wallpaper
        } catch {
            let nsError = error as NSError
            DWLog.net("URLSession 失败 domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)，切换 curl 备用通道")
            let data = try CurlFallback.fetch(url, timeout: 12)
            let wallpaper = try decodedWallpaper(from: data)
            cached = (wallpaper, Date())
            DWLog.net("元数据成功 curl \(data.count) bytes")
            return wallpaper
        }
    }

    private func decodedWallpaper(from data: Data) throws -> Wallpaper {
        let decoded = try JSONDecoder().decode(BingArchiveResponse.self, from: data)
        guard let image = decoded.images?.first else { throw DWError.emptyData }
        return try parse(image)
    }

    private func parse(_ image: BingImage) throws -> Wallpaper {
        guard let base = image.urlbase, !base.isEmpty else {
            throw DWError.missingField("urlbase")
        }
        // 不接受任意 URL / 路径：接口返回值只能作为相对图片标识使用（规格 7.1）。
        guard base.hasPrefix("/"), !base.contains("://"), !base.contains("..") else {
            throw DWError.invalidContent("图片地址不符合预期")
        }
        let host = "https://www.bing.com"
        guard let standard = URL(string: host + base + "_1920x1080.jpg"),
              let uhd = URL(string: host + base + "_UHD.jpg") else {
            throw DWError.missingField("可解析的图片地址")
        }
        // UHD 必须用 urlbase 自行拼接；接口 url 带 w/h 缩放参数会退回 1080p。
        return Wallpaper(
            wallpaperDate: image.enddate ?? image.startdate ?? DWFormat.todayString(),
            title: image.title,
            copyright: image.copyright,
            copyrightURL: URL(string: image.copyrightlink ?? ""),
            standardImageURL: standard,
            uhdImageURL: uhd,
            pixelWidth: nil,
            pixelHeight: nil
        )
    }
}

// MARK: - 缓存图片（仅应用自有缓存目录，与用户保存目录严格分离）

struct CachedImage {
    let data: Data
    let fileURL: URL
    let width: Int
    let height: Int
    let contentType: String
}

final class ImageCache {
    static let shared = ImageCache()

    let directory: URL
    private let fm = FileManager.default
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.connectionProxyDictionary = [
            "HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
        ]
        return URLSession(configuration: config)
    }()

    init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("DailyWall", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func cacheFile(for url: URL) -> URL {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return directory.appendingPathComponent("dw_" + String(hash, radix: 16) + ".jpg")
    }

    func load(_ url: URL, force: Bool = false) async throws -> CachedImage {
        let target = cacheFile(for: url)
        if !force, fm.fileExists(atPath: target.path),
           let data = try? Data(contentsOf: target),
           let size = ImageProbe.jpegSize(data) {
            return CachedImage(data: data, fileURL: target, width: size.width,
                               height: size.height, contentType: "image/jpeg")
        }

        DWLog.net("图片请求开始 \(url.absoluteString)")
        let data: Data
        do {
            let (temp, response) = try await session.download(from: url)
            defer { try? fm.removeItem(at: temp) }
            guard let http = response as? HTTPURLResponse else {
                throw DWError.network("无有效 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else { throw DWError.http(http.statusCode) }
            let mime = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard mime.lowercased().contains("image") else {
                throw DWError.invalidContent("响应不是图片（\(mime)）")
            }
            data = try Data(contentsOf: temp)
            DWLog.net("图片成功 URLSession \(data.count) bytes")
        } catch {
            let nsError = error as NSError
            DWLog.net("图片 URLSession 失败 code=\(nsError.code)，切换 curl 备用通道")
            data = try CurlFallback.fetch(url, timeout: 40)
            DWLog.net("图片成功 curl \(data.count) bytes")
        }
        guard data.count <= 30 * 1024 * 1024 else {
            throw DWError.invalidContent("响应超过 30 MB 上限")
        }
        // curl 通道无法读取 MIME，统一以 JPEG 解码结果作为内容校验（更严格）。
        guard let size = ImageProbe.jpegSize(data) else {
            throw DWError.invalidContent("JPEG 无法解码")
        }
        try data.write(to: target, options: .atomic)
        return CachedImage(data: data, fileURL: target, width: size.width,
                           height: size.height, contentType: "image/jpeg")
    }

    /// 只删除本应用创建的 dw_ 前缀文件，绝不触碰用户保存目录（规格 4.5）。
    func clear() throws {
        let items = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in items where item.lastPathComponent.hasPrefix("dw_") {
            try? fm.removeItem(at: item)
        }
    }

    func usageText() -> String {
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = items.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - 目录与文件责任

final class StorageService {
    static let shared = StorageService()
    private let fm = FileManager.default

    func defaultDirectory() -> URL {
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("DailyWall", isDirectory: true)
    }

    func directory() throws -> URL {
        let url: URL
        if let path = WallpaperSettings.shared.directoryPath {
            url = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            url = defaultDirectory()
        }
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw DWError.directory("路径不是目录")
        }
        guard fm.isWritableFile(atPath: url.path) else {
            throw DWError.directory("无写权限")
        }
        return url
    }

    func displayDirectory() -> String {
        if let path = WallpaperSettings.shared.directoryPath {
            return path.replacingOccurrences(of: fm.homeDirectoryForCurrentUser.path, with: "~")
        }
        return "~/Pictures/DailyWall"
    }

    /// 通过 NSOpenPanel 由用户明确选择目录；不猜测、不擅自回退。
    @MainActor
    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择 Dayflux 保存壁纸的目录（应用不会删除其中的文件）"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        WallpaperSettings.shared.directoryPath = url.path
        return url
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - 下载成品

enum DownloadOutcome {
    case saved(URL, bytes: Int, width: Int, height: Int)
    case skipped(URL)
    case overwritten(URL, bytes: Int, width: Int, height: Int)
}

final class DownloadService {
    static let shared = DownloadService()
    private let fm = FileManager.default

    func fileName(for wallpaper: Wallpaper) -> String {
        "DailyWall_\(wallpaper.wallpaperDate)_zh-CN.jpg"
    }

    func targetURL(for wallpaper: Wallpaper) throws -> URL {
        try StorageService.shared.directory().appendingPathComponent(fileName(for: wallpaper))
    }

    func fileExists(for wallpaper: Wallpaper) -> Bool {
        guard let url = try? targetURL(for: wallpaper) else { return false }
        return fm.fileExists(atPath: url.path)
    }

    /// 临时文件写入 → 校验已完成 → 原子移入；不产生伪完整成品（规格 4.2）。
    func save(_ image: CachedImage, wallpaper: Wallpaper, overwrite: Bool) throws -> DownloadOutcome {
        let directory = try StorageService.shared.directory()
        let target = directory.appendingPathComponent(fileName(for: wallpaper))
        let existed = fm.fileExists(atPath: target.path)
        if existed && !overwrite { return .skipped(target) }

        let temp = directory.appendingPathComponent(".dw_tmp_\(UUID().uuidString).jpg")
        try image.data.write(to: temp, options: .atomic)
        defer { try? fm.removeItem(at: temp) }

        if existed {
            _ = try fm.replaceItemAt(target, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: target)
        }
        let result = (target, image.data.count, image.width, image.height)
        return existed ? .overwritten(result.0, bytes: result.1, width: result.2, height: result.3)
                       : .saved(result.0, bytes: result.1, width: result.2, height: result.3)
    }
}

// MARK: - 系统桌面

final class DesktopService {
    static let shared = DesktopService()

    /// 自用版口径：应用到所有已连接显示器，并回读校验主屏确实生效。
    /// 唤醒 / 登录瞬间桌面服务未就绪时，`setDesktopImageURL` 可能不抛错却不落地；
    /// 若不校验就会误判成功并写下 lastRunDate，导致当天再不重试。
    func apply(_ url: URL) async throws {
        let expected = url.lastPathComponent
        var detail = ""
        for attempt in 1...3 {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { throw DWError.desktop("未检测到显示器") }

            var accepted = 0
            for screen in screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    accepted += 1
                } catch {
                    DWLog.schedule("桌面设置被拒: \(error.localizedDescription)")
                }
            }

            // 给 Dock/WindowServer 一点落盘时间，再回读主屏。
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            let primary = NSScreen.main ?? screens[0]
            let current = NSWorkspace.shared.desktopImageURL(for: primary)
            let matched = current?.lastPathComponent == expected
                || current?.standardizedFileURL.path == url.standardizedFileURL.path
            detail = "accepted=\(accepted)/\(screens.count) 主屏回读=\(current?.lastPathComponent ?? "nil")"
            DWLog.schedule("桌面校验 第\(attempt)次 \(matched ? "已生效" : "未生效") \(detail)")

            if matched { return }
        }
        throw DWError.desktop("壁纸设置后未生效（已重试 3 次：\(detail)）")
    }
}

// MARK: - 通知（可选；任何失败都不影响核心功能）

final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorizationIfNeeded() {
        guard WallpaperSettings.shared.notifications, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard WallpaperSettings.shared.notifications, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)) { _ in }
        }
    }
}

// MARK: - 登录启动（失败仅报告，不反复弹窗）

final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    func isEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @MainActor
    func set(_ enabled: Bool) async throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } else {
            throw DWError.desktop("当前系统不支持登录启动设置")
        }
    }
}
