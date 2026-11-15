import Foundation
import AppKit

// MARK: - 错误模型
// 每条错误同时给出「发生了什么」与「用户可执行的动作」，符合规格第 5 节。

enum DWError: LocalizedError {
    case network(String)
    case http(Int)
    case emptyData
    case missingField(String)
    case invalidContent(String)
    case directory(String)
    case cache(String)
    case write(String)
    case desktop(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let m):   return "无法获取今日壁纸：\(m)"
        case .http(let c):      return "Bing 返回 HTTP \(c)"
        case .emptyData:        return "接口未返回今日壁纸数据"
        case .missingField(let f): return "接口响应缺少必要字段 \(f)"
        case .invalidContent(let m): return "图片内容校验失败：\(m)"
        case .directory(let m): return "保存目录不可用：\(m)"
        case .cache(let m):     return "应用缓存不可用：\(m)"
        case .write(let m):     return "写入失败：\(m)"
        case .desktop(let m):   return "设置桌面失败：\(m)"
        case .cancelled:        return "操作已取消"
        }
    }

    var hint: String {
        switch self {
        case .network:       return "检查网络后点「重试」。已有文件不受影响。"
        case .http:          return "稍后重试；接口为非正式使用方式，可能临时变更。已有文件不受影响。"
        case .emptyData:     return "稍后重试。已有文件不受影响。"
        case .missingField:  return "接口结构可能已变化，请重新执行 M0 核验。已有文件不受影响。"
        case .invalidContent: return "未写入正式壁纸文件，可重试。已有文件不受影响。"
        case .directory:     return "在「设置」中重新选择目录，并确认有写权限。已有文件不受影响。"
        case .cache:         return "可忽略；缓存只影响加载速度，不影响下载与更换桌面。已有文件不受影响。"
        case .write:         return "检查磁盘空间与目录权限后重试。已有文件不受影响。"
        case .desktop:       return "已下载的文件保留，可手动在 Finder 中设置，或稍后重试。"
        case .cancelled:     return "已有文件不受影响。"
        }
    }
}

// MARK: - Bing 响应（字段全部可选，未知字段由 Codable 自动忽略）

struct BingArchiveResponse: Decodable {
    let images: [BingImage]?
    let tooltips: BingTooltips?
}

struct BingImage: Decodable {
    let startdate: String?
    let enddate: String?
    let fullstartdate: String?
    let title: String?
    let copyright: String?
    let copyrightlink: String?
    let url: String?
    let urlbase: String?
    let wp: Bool?
}

struct BingTooltips: Decodable {
    let walls: String?
    let walle: String?
}

// MARK: - 运行期模型（不保留整段接口响应）

struct Wallpaper {
    /// 取接口 enddate（Bing 生效日），YYYYMMDD。见 M0 核验记录 A-2。
    let wallpaperDate: String
    let title: String?
    let copyright: String?
    let copyrightURL: URL?
    let standardImageURL: URL
    let uhdImageURL: URL
    var pixelWidth: Int?
    var pixelHeight: Int?

    func imageURL(preferUHD: Bool) -> URL {
        preferUHD ? uhdImageURL : standardImageURL
    }

    var displayDate: String {
        guard wallpaperDate.count == 8 else { return wallpaperDate }
        let s = wallpaperDate
        return "\(s.prefix(4))-\(s.dropFirst(4).prefix(2))-\(s.suffix(2))"
    }

    var pixelText: String {
        guard let w = pixelWidth, let h = pixelHeight else { return "尺寸待获取" }
        return "\(w) × \(h)"
    }
}

// MARK: - 图片探测（不依赖 ImageIO 之外的第三方库）

enum ImageProbe {
    /// 从 JPEG SOF 段解析真实像素；解析失败返回 nil，绝不写入伪完整成品。
    static func jpegSize(_ data: Data) -> (width: Int, height: Int)? {
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        let sof: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                               0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            while i < b.count, b[i] == 0xFF { i += 1 }
            guard i < b.count else { break }
            let marker = b[i]
            i += 1
            if marker == 0xD8 || marker == 0xD9 || (0xD0...0xD7).contains(marker) { continue }
            guard i + 2 <= b.count else { break }
            let length = (Int(b[i]) << 8) | Int(b[i + 1])
            guard length >= 2 else { break }
            if sof.contains(marker), i + 7 <= b.count {
                let h = (Int(b[i + 3]) << 8) | Int(b[i + 4])
                let w = (Int(b[i + 5]) << 8) | Int(b[i + 6])
                if w > 0, h > 0 { return (w, h) }
            }
            i += length
        }
        return nil
    }

    static func isJPEG(_ data: Data) -> Bool {
        jpegSize(data) != nil
    }
}

// MARK: - 小工具

enum DWFormat {
    static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func todayString(_ date: Date = Date()) -> String {
        fileDateFormatter.string(from: date)
    }

    static func timeString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - 每日调度策略（纯逻辑，可在无 GUI 的冒烟测试中验证）

enum SchedulePolicy {
    /// 任务失败后的重试冷却，避免每分钟重复打接口。
    static let retryInterval: TimeInterval = 5 * 60

    /// 冷启动 / 唤醒瞬间的稳定期：此时 WindowServer、Dock 与桌面 Space 可能尚未就绪，
    /// `setDesktopImageURL` 会「不抛错但不生效」。补跑统一延后到稳定期之后。
    static let startupGrace: TimeInterval = 10
    static let wakeGrace: TimeInterval = 15

    /// 是否应执行当天的自动任务。
    /// - `lastRunDate` 只在核心链路全部成功后写入；失败保持为空，当天继续重试。
    /// - `lastAttempt` 记录最近一次尝试（含失败），用于冷却。
    static func shouldRun(now: Date = Date(),
                          calendar: Calendar = .current,
                          hour: Int,
                          minute: Int,
                          lastRunDate: String?,
                          lastAttempt: Date?) -> Bool {
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let due = currentHour > hour || (currentHour == hour && currentMinute >= minute)
        guard due else { return false }
        guard lastRunDate != DWFormat.todayString(now) else { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryInterval {
            return false
        }
        return true
    }

    /// 计算下一次应触发自动检查的时间点，配合「单次 Timer」使用（取代每分钟轮询）。
    /// - 今天已完成：明天同一时刻。
    /// - 未完成且未到设定时间：今天的设定时刻。
    /// - 未完成且已错过（含睡眠唤醒补偿）：冷却内则 `lastAttempt + retryInterval`，否则立即（+1s）。
    static func nextFire(now: Date = Date(),
                         calendar: Calendar = .current,
                         hour: Int,
                         minute: Int,
                         lastRunDate: String?,
                         lastAttempt: Date?,
                         notBefore: Date? = nil) -> Date {
        let today = DWFormat.todayString(now)
        let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        let fire: Date
        if lastRunDate == today {
            fire = calendar.date(byAdding: .day, value: 1, to: target)!
        } else if now < target {
            fire = target
        } else if let last = lastAttempt, now.timeIntervalSince(last) < retryInterval {
            fire = last.addingTimeInterval(retryInterval)
        } else {
            fire = now.addingTimeInterval(1)
        }
        // 只推迟「立即补跑」这类近期触发点；今天的设定时刻、明天同一时刻天然在稳定期之后。
        if let notBefore, fire < notBefore { return notBefore }
        return fire
    }
}

// MARK: - 诊断日志与备用网络通道

enum DWLog {
    static func net(_ message: String) { write(message, to: "/tmp/dw_app_net.log") }
    static func schedule(_ message: String) { write(message, to: "/tmp/dw_schedule.log") }

    private static func write(_ message: String, to path: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

enum CurlFallback {
    /// URLSession 通道失败时启用系统 curl 直连。
    /// 实测：同一 GUI bundle 内 curl 直连 0.27s 返回 200，不受代理与 ATS 影响。
    static func fetch(_ url: URL, timeout: Int = 15) throws -> Data {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dw_curl_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--noproxy", "*", "-sS", "-L",
                             "--max-time", String(timeout),
                             "-o", output.path, url.absoluteString]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw DWError.network("备用通道无法启动：\(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw DWError.network("备用通道失败：\(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return try Data(contentsOf: output)
    }
}
