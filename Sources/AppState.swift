import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case success
        case failure(String)
    }

    @Published var phase: Phase = .idle
    @Published var wallpaper: Wallpaper?
    @Published var previewImage: NSImage?
    @Published var previewError: String?
    @Published var pixelText: String = "尺寸待获取"
    @Published var isDownloading = false
    @Published var isApplying = false
    @Published var message: String?
    @Published var messageIsError = false
    @Published var showingSettings = false
    @Published var needsDirectorySetup = false
    @Published var launchAtLogin = false
    /// 键盘清洁模式：开启后全屏蒙层拦截键盘输入，方便擦拭键盘；再点鼠标解除。
    @Published var cleaningMode = false

    let settings = WallpaperSettings.shared

    private var cachedImage: CachedImage?
    private var isRefreshing = false
    private var isRunningScheduledTask = false
    /// 最近一次自动任务尝试时间（含失败），用于失败后的重试冷却。仅内存，重启即清零。
    private var lastScheduledAttempt: Date?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// 冷启动 / 唤醒后的稳定期截止点：此前不触发补跑，避免桌面服务未就绪时误判成功。
    private var notBefore: Date?
    /// 主窗口当前是否可见，由 AppDelegate 通知。用于决定自动任务完成后是否保留预览内存。
    private var mainWindowVisible = false

    // MARK: - 生命周期

    func start() {
        NotificationService.shared.requestAuthorizationIfNeeded()
        launchAtLogin = LaunchAtLoginService.shared.isEnabled()
        needsDirectorySetup = (settings.directoryPath == nil)

        // 单次定时到下个执行点，取代每分钟轮询；启动/唤醒后统一由调度器补偿，
        // 且都带一段稳定期，避开桌面服务尚未就绪的窗口。
        notBefore = Date().addingTimeInterval(SchedulePolicy.startupGrace)
        scheduleNext()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notBefore = Date().addingTimeInterval(SchedulePolicy.wakeGrace)
                self?.scheduleNext()
            }
        }

        Task {
            await refresh()
            // 启动后按当前日期补偿一次，不追溯多日（规格 4.3）；统一走调度器。
            scheduleNext()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        // 退出前若仍处于清洁模式，复位以便 AppDelegate 清理蒙层与事件监听。
        if cleaningMode { cleaningMode = false }
    }

    // MARK: - 今日数据

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        phase = .loading
        previewError = nil
        message = nil

        do {
            let wallpaper = try await BingWallpaperService.shared.fetchToday(force: force)
            self.wallpaper = wallpaper
            pixelText = "尺寸待获取"
            phase = .success

            // 预览失败不影响下载与其它设置（规格 4.1），单独报告并提供重试。
            do {
                let image = try await ImageCache.shared.load(
                    wallpaper.imageURL(preferUHD: settings.preferUHD), force: force
                )
                cachedImage = image
                previewImage = NSImage(data: image.data)
                var updated = wallpaper
                updated.pixelWidth = image.width
                updated.pixelHeight = image.height
                self.wallpaper = updated
                pixelText = updated.pixelText
            } catch {
                cachedImage = nil
                previewImage = nil
                previewError = describe(error) + " " + hint(for: error)
            }
        } catch {
            phase = .failure(describe(error))
            setMessage(describe(error) + " " + hint(for: error), isError: true)
        }
    }

    // MARK: - 下载

    /// 返回是否完成（当天文件已存在算成功）。自动任务据此决定能否标记当天已执行。
    @discardableResult
    func download(overwrite: Bool = false) async -> Bool {
        guard !isDownloading, let wallpaper else { return false }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let image: CachedImage
            if let cachedImage {
                image = cachedImage
            } else {
                image = try await ImageCache.shared.load(
                    wallpaper.imageURL(preferUHD: settings.preferUHD)
                )
                cachedImage = image
            }
            let outcome = try DownloadService.shared.save(image, wallpaper: wallpaper,
                                                          overwrite: overwrite)
            switch outcome {
            case .skipped(let url):
                setMessage("当天壁纸已存在，按规则跳过：\(url.lastPathComponent)", isError: false)
            case .saved(let url, _, _, _), .overwritten(let url, _, _, _):
                setMessage("已保存 \(url.lastPathComponent)", isError: false)
                NotificationService.shared.send(title: "Dayflux", body: "今日壁纸已下载")
            }
            return true
        } catch {
            setMessage(describe(error) + " " + hint(for: error), isError: true)
            return false
        }
    }

    /// 已存在成品时询问是否覆盖；任何覆盖必须先取得本次明确操作（规格 2.3）。
    func downloadWithConflictCheck() async {
        guard let wallpaper, DownloadService.shared.fileExists(for: wallpaper) else {
            await download()
            return
        }
        let alert = NSAlert()
        alert.messageText = "当天壁纸已存在"
        alert.informativeText = "是否覆盖已保存的文件？选择「取消」则保留原文件，不做任何修改。"
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            setMessage("已取消，原文件未改动", isError: false)
            return
        }
        await download(overwrite: true)
    }

    // MARK: - 桌面

    /// 返回桌面是否设置成功；失败时自动任务不标记当天已执行。
    @discardableResult
    func applyDesktop() async -> Bool {
        guard !isApplying, let wallpaper else { return false }
        isApplying = true
        defer { isApplying = false }
        do {
            let target = try DownloadService.shared.targetURL(for: wallpaper)
            if !FileManager.default.fileExists(atPath: target.path) {
                let image: CachedImage
                if let cachedImage { image = cachedImage }
                else {
                    image = try await ImageCache.shared.load(
                        wallpaper.imageURL(preferUHD: settings.preferUHD)
                    )
                    cachedImage = image
                }
                _ = try DownloadService.shared.save(image, wallpaper: wallpaper, overwrite: false)
            }
            try await DesktopService.shared.apply(target)
            setMessage("已设置桌面（所有已连接显示器）", isError: false)
            NotificationService.shared.send(title: "Dayflux", body: "桌面壁纸已更新")
            return true
        } catch {
            // 桌面设置失败不删除已下载文件（规格 4.3）。
            setMessage(describe(error) + " " + hint(for: error), isError: true)
            return false
        }
    }

    func revealDirectory() {
        do {
            let directory = try StorageService.shared.directory()
            var target = directory
            if let wallpaper,
               let file = try? DownloadService.shared.targetURL(for: wallpaper),
               FileManager.default.fileExists(atPath: file.path) {
                target = file
            }
            StorageService.shared.reveal(target)
        } catch {
            setMessage(describe(error) + " " + hint(for: error), isError: true)
        }
    }

    // MARK: - 设置动作

    func changeDirectory() {
        let url = StorageService.shared.chooseDirectory()
        if url != nil {
            needsDirectorySetup = false
            setMessage("保存目录已更新；原有文件不会被迁移或删除", isError: false)
        }
    }

    func changeQuality() async {
        cachedImage = nil
        previewImage = nil
        await refresh()
    }

    func clearCache() {
        do {
            try ImageCache.shared.clear()
            cachedImage = nil
            setMessage("应用缓存已清理；用户保存目录未受影响", isError: false)
        } catch {
            setMessage(describe(error), isError: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            try await LaunchAtLoginService.shared.set(enabled)
            launchAtLogin = LaunchAtLoginService.shared.isEnabled()
        } catch {
            launchAtLogin = false
            setMessage("登录启动注册失败：\(describe(error))。不影响下载与换桌面。", isError: true)
        }
    }

    // MARK: - 键盘清洁

    /// 切换键盘清洁模式：开启→全屏禁用键盘；再次点击（鼠标）→解除。
    func toggleCleaner() {
        cleaningMode.toggle()
    }

    // MARK: - 调度
    // 常驻菜单栏应用 + 每分钟检查 + 唤醒补偿。不安装 LaunchAgent：
    // 应用本身常驻，LaunchAgent 的「应用未运行也能触发」优势在此不成立，
    // 且未公证应用安装 LaunchAgent 会增加不确定性。
    // lastRunDate 只在核心链路全部成功后写入：任务失败当天仍会按冷却间隔重试。

    private func tick() {
        guard settings.autoDownload || settings.autoChange else { scheduleNext(); return }
        guard !isRunningScheduledTask else { scheduleNext(); return }
        let now = Date()
        guard SchedulePolicy.shouldRun(
            now: now,
            hour: settings.dailyHour,
            minute: settings.dailyMinute,
            lastRunDate: settings.lastRunDate,
            lastAttempt: lastScheduledAttempt
        ) else { scheduleNext(); return }

        let today = DWFormat.todayString(now)
        isRunningScheduledTask = true
        lastScheduledAttempt = now
        DWLog.schedule("开始当天任务 date=\(today)")
        Task { @MainActor in
            defer {
                isRunningScheduledTask = false
                // 后台（窗口不可见）自动任务完成后无需常驻预览图，释放以省内存。
                if !mainWindowVisible { releasePreviewResources() }
                scheduleNext()
            }
            let succeeded = await performScheduledTask()
            if succeeded {
                settings.lastRunDate = today
                lastScheduledAttempt = nil
                notBefore = nil
                DWLog.schedule("任务成功（桌面已回读确认）→ 写入 lastRunDate=\(today)")
            } else {
                DWLog.schedule("任务失败 → 不写 lastRunDate，\(Int(SchedulePolicy.retryInterval / 60)) 分钟后重试")
                setMessage("自动任务未完成，将在 5 分钟后重试；已有文件不受影响。", isError: true)
            }
        }
    }

    /// 计算并挂起「下一次执行点」的单次定时器，取代每分钟轮询。
    private func scheduleNext() {
        let now = Date()
        let next = SchedulePolicy.nextFire(
            now: now,
            hour: settings.dailyHour,
            minute: settings.dailyMinute,
            lastRunDate: settings.lastRunDate,
            lastAttempt: lastScheduledAttempt,
            notBefore: notBefore
        )
        let interval = max(0.5, next.timeIntervalSinceNow)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        DWLog.schedule("下次调度检查 in \(Int(interval))s")
    }

    /// 由 AppDelegate 在窗口显隐时通知，决定自动任务后是否保留预览内存。
    func notifyWindowVisibility(_ visible: Bool) {
        mainWindowVisible = visible
    }

    /// 释放预览图与缓存的原图数据；窗口打开时由 refresh 重新加载（磁盘缓存秒回，不联网）。
    func releasePreviewResources() {
        cachedImage = nil
        previewImage = nil
    }

    /// 窗口打开时若预览为空，从磁盘缓存重新加载（不联网）。
    func ensurePreviewLoadedIfNeeded() {
        guard cachedImage == nil else { return }
        Task { await self.refresh() }
    }

    private func performScheduledTask() async -> Bool {
        await refresh(force: true)
        guard case .success = phase, wallpaper != nil else { return false }
        var succeeded = true
        if settings.autoDownload || settings.autoChange {
            succeeded = await download()
        }
        if settings.autoChange {
            let applied = await applyDesktop()
            succeeded = succeeded && applied
        }
        return succeeded
    }

    // MARK: - 辅助

    func setMessage(_ text: String, isError: Bool) {
        message = text
        messageIsError = isError
    }

    private func describe(_ error: Error) -> String {
        if let dwError = error as? DWError { return dwError.localizedDescription }
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut: return "请求超时"
        case NSURLErrorNotConnectedToInternet: return "网络未连接"
        case NSURLErrorCannotFindHost: return "找不到服务器"
        case NSURLErrorCannotConnectToHost: return "无法连接服务器"
        case NSURLErrorNetworkConnectionLost: return "网络连接中断"
        case NSURLErrorDNSLookupFailed: return "域名解析失败"
        case NSURLErrorSecureConnectionFailed: return "安全连接建立失败"
        case NSURLErrorServerCertificateUntrusted: return "服务器证书不受信任"
        default: return nsError.localizedDescription
        }
    }

    private func hint(for error: Error) -> String {
        (error as? DWError)?.hint ?? "可重试；已有文件不受影响。"
    }
}
