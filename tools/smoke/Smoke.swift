import Foundation
import AppKit

/// M1 冒烟测试：不启动 GUI，验证网络解析、UHD 拼接、下载与冲突策略。
/// 成品只写入 /tmp 下的隔离目录，不触碰 ~/Pictures。
@main
struct Smoke {
    static func main() async throws {
        var failures = 0
        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            print("[\(condition ? "PASS" : "FAIL")] \(label) \(detail)")
            if !condition { failures += 1 }
        }

        print("=== DailyWall M1 冒烟测试（无 GUI）===\n")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dw_smoke_out", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // 清理本测试目录上一次的残留，保证「首次写入」判定不受历史文件影响。
        if let items = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent.hasPrefix("DailyWall_") {
                try? FileManager.default.removeItem(at: item)
            }
        }
        defer { WallpaperSettings.shared.directoryPath = nil }

        do {
            let wallpaper = try await BingWallpaperService.shared.fetchToday(force: true)
            check("元数据获取", true)
            print("       title = \(wallpaper.title ?? "(nil)")")
            print("       date  = \(wallpaper.wallpaperDate) -> \(wallpaper.displayDate)")
            check("日期为 8 位 YYYYMMDD", wallpaper.wallpaperDate.count == 8)
            check("title 存在且非空", wallpaper.title?.isEmpty == false)

            let uhd = wallpaper.uhdImageURL.absoluteString
            check("UHD 由 urlbase 拼接", uhd.hasSuffix("_UHD.jpg"), uhd)
            check("UHD URL 不含缩放参数", !uhd.contains("w=1920"))

            let image = try await ImageCache.shared.load(
                wallpaper.imageURL(preferUHD: true), force: false
            )
            check("图片可解码", image.width > 0 && image.height > 0,
                  "\(image.width)×\(image.height)")
            check("UHD 实测 3840×2160",
                  image.width == 3840 && image.height == 2160,
                  "\(image.width)×\(image.height), \(image.data.count) bytes")

            WallpaperSettings.shared.directoryPath = tempDir.path
            let name = DownloadService.shared.fileName(for: wallpaper)
            check("文件名格式", name.hasPrefix("DailyWall_") && name.hasSuffix("_zh-CN.jpg"), name)

            let first = try DownloadService.shared.save(image, wallpaper: wallpaper, overwrite: false)
            if case .saved(let url, _, _, _) = first {
                check("首次写入成品", FileManager.default.fileExists(atPath: url.path),
                      url.lastPathComponent)
            } else {
                check("首次写入成品", false, "\(first)")
            }

            let second = try DownloadService.shared.save(image, wallpaper: wallpaper, overwrite: false)
            if case .skipped = second { check("重复下载按规则跳过", true) }
            else { check("重复下载按规则跳过", false, "\(second)") }

            let file = tempDir.appendingPathComponent(name)
            let before = (try? Data(contentsOf: file))?.count ?? 0
            let third = try DownloadService.shared.save(image, wallpaper: wallpaper, overwrite: true)
            let after = (try? Data(contentsOf: file))?.count ?? 0
            check("确认后覆盖不损坏文件", before > 0 && before == after, "\(before) -> \(after)")
            if case .overwritten = third { check("覆盖返回正确状态", true) }
            else { check("覆盖返回正确状态", false) }

            try ImageCache.shared.clear()
            check("缓存清理不触碰成品目录",
                  FileManager.default.fileExists(atPath: file.path))

            let standard = try await ImageCache.shared.load(
                wallpaper.imageURL(preferUHD: false), force: false
            )
            check("标准图实测 1920×1080",
                  standard.width == 1920 && standard.height == 1080,
                  "\(standard.width)×\(standard.height)")
        } catch {
            print("[FAIL] 异常: \(error)")
            failures += 1
        }

        // 调度策略：失败当天必须能重试，成功后当天不再重复执行。
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
            var c = DateComponents()
            c.timeZone = cal.timeZone
            c.year = 2026; c.month = 11; c.day = day; c.hour = h; c.minute = m
            return cal.date(from: c)!
        }
        let morning = at(10, 9, 0)
        print("\n=== 调度策略（失败当天重试）===")
        check("到点且当天未执行 → 执行",
              SchedulePolicy.shouldRun(now: morning, calendar: cal, hour: 8, minute: 30,
                                       lastRunDate: nil, lastAttempt: nil))
        check("未到设定时间 → 不执行",
              !SchedulePolicy.shouldRun(now: at(10, 8, 0), calendar: cal, hour: 8, minute: 30,
                                        lastRunDate: nil, lastAttempt: nil))
        check("当天已成功 → 不重复",
              !SchedulePolicy.shouldRun(now: morning, calendar: cal, hour: 8, minute: 30,
                                        lastRunDate: "20261110", lastAttempt: nil))
        check("失败后 3 分钟冷却中 → 暂不重试",
              !SchedulePolicy.shouldRun(now: morning, calendar: cal, hour: 8, minute: 30,
                                        lastRunDate: nil,
                                        lastAttempt: morning.addingTimeInterval(-180)))
        check("失败满 5 分钟 → 当天继续重试",
              SchedulePolicy.shouldRun(now: morning, calendar: cal, hour: 8, minute: 30,
                                       lastRunDate: nil,
                                       lastAttempt: morning.addingTimeInterval(-360)))
        check("跨日补偿不受昨日记录影响",
              SchedulePolicy.shouldRun(now: morning, calendar: cal, hour: 8, minute: 30,
                                       lastRunDate: "20261109", lastAttempt: at(9, 9, 0)))

        print("\n结果: \(failures == 0 ? "全部通过" : "\(failures) 项失败")")
        exit(failures == 0 ? 0 : 1)
    }
}
