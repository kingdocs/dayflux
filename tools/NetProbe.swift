import Foundation

/// 网络出口探针：模拟 GUI 应用（不继承 shell 代理环境变量）下的 URLSession 行为。
/// 用法:
///   swiftc -O -swift-version 5 tools/NetProbe.swift -o /tmp/dw_netprobe
///   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy -u ALL_PROXY -u all_proxy /tmp/dw_netprobe
@main
struct NetProbe {
    static let url = URL(string:
        "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN")!

    static func run(_ label: String, _ config: URLSessionConfiguration) async {
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        let start = Date()
        do {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print(String(format: "[%@] HTTP %d, %d bytes, %.2fs",
                         label, code, data.count, Date().timeIntervalSince(start)))
        } catch {
            print(String(format: "[%@] FAIL %@, %.2fs",
                         label, error.localizedDescription, Date().timeIntervalSince(start)))
        }
    }

    static func main() async {
        let proxyEnv = ProcessInfo.processInfo.environment.filter {
            $0.key.lowercased().contains("proxy")
        }
        print("代理环境变量: \(proxyEnv.keys.sorted())")

        let system = URLSessionConfiguration.default
        await run("默认(系统代理)", system)

        let direct = URLSessionConfiguration.default
        direct.connectionProxyDictionary = [
            "HTTPEnable": false,
            "HTTPSEnable": false,
            "SOCKSEnable": false,
        ]
        await run("禁用代理(直连)", direct)
    }
}
