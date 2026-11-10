import AppKit
import Foundation

/// 复现主程序的调用结构：从 @MainActor 上下文发起 URLSession 请求。
@MainActor
final class MainActorFetcher {
    private let url: URL
    init(url: URL) { self.url = url }

    func fetch() async -> String {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        let start = Date()
        do {
            let (data, _) = try await session.data(from: url)
            return String(format: "OK %d bytes %.2fs", data.count,
                          Date().timeIntervalSince(start))
        } catch {
            let e = error as NSError
            return String(format: "FAIL %.2fs code=%d %@",
                          Date().timeIntervalSince(start), e.code, e.localizedDescription)
        }
    }
}

/// 后台 GUI bundle 探针：定位 app bundle 内 URLSession 超时的真实原因。
/// 不建窗口，运行完自动退出，结果写 /tmp/dw_gui_probe.log。
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let url = URL(string:
        "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN")!
    private var lines: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            lines.append("bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
            lines.append("proxyEnv=\(ProcessInfo.processInfo.environment.filter { $0.key.lowercased().contains("proxy") }.keys.sorted())")
            await testURLSession("default", disabledProxy: false)
            await testURLSession("no-proxy", disabledProxy: true)
            await testCurl()
            let mainResult = await Task { @MainActor in
                await MainActorFetcher(url: self.url).fetch()
            }.value
            lines.append("[main-actor-chain] \(mainResult)")
            let detachedResult = await Task.detached {
                await MainActorFetcher(url: self.url).fetch()
            }.value
            lines.append("[detached-main-actor] \(detachedResult)")
            try? lines.joined(separator: "\n").write(toFile: "/tmp/dw_gui_probe.log",
                                                     atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private func testURLSession(_ label: String, disabledProxy: Bool) async {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        if disabledProxy {
            config.connectionProxyDictionary = [
                "HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
            ]
        }
        let session = URLSession(configuration: config)
        let start = Date()
        do {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            lines.append(String(format: "[\(label)] OK HTTP %d %d bytes %.2fs",
                                code, data.count, Date().timeIntervalSince(start)))
        } catch {
            let e = error as NSError
            lines.append(String(format: "[\(label)] FAIL %.2fs domain=%@ code=%d desc=%@",
                                Date().timeIntervalSince(start), e.domain, e.code,
                                e.localizedDescription))
            lines.append("[\(label)] userInfo=\(e.userInfo)")
        }
    }

    private func testCurl() async {
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--noproxy", "*", "-sS", "-m", "10",
                             "-o", "/tmp/dw_gui_curl.out", "-w", "%{http_code}", url.absoluteString]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            lines.append(String(format: "[curl] exit=%d out=%@ %.2fs",
                                process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines),
                                Date().timeIntervalSince(start)))
        } catch {
            lines.append("[curl] FAIL \(error.localizedDescription)")
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ProbeDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
