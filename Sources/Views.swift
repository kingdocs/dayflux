import Foundation
import AppKit
import SwiftUI

// MARK: - 复用组件

private let surfaceColor = Color(nsColor: NSColor(srgbRed: 0.965, green: 0.965,
                                                  blue: 0.973, alpha: 1.0))

struct StatusBadge: View {
    let text: String
    var highlighted: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(highlighted ? Color(nsColor: NSColor(srgbRed: 0.23, green: 0.43,
                                                                   blue: 0.07, alpha: 1))
                                         : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(highlighted
                    ? Color(nsColor: NSColor(srgbRed: 0.918, green: 0.953, blue: 0.871, alpha: 1))
                    : surfaceColor)
            )
            .accessibilityLabel(text)
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    var busy: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 15))
                        .frame(width: 16, height: 16)
                }
                Text(title).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(surfaceColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(title)
    }
}

struct SettingRow: View {
    let title: String
    let value: String
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 12))
                Spacer()
                if highlighted {
                    StatusBadge(text: value)
                } else {
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，当前 \(value)，打开设置")
    }
}

// MARK: - 主窗口

struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: WallpaperSettings = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DailyWall")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                StatusBadge(text: "今日壁纸")
            }
            .padding(.bottom, 12)

            previewArea

            // 标题仅取接口 title；缺失时整行隐藏，不以版权说明代替（规格 4.1）。
            if let title = state.wallpaper?.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.top, 12)
                    .accessibilityLabel("今日壁纸标题：\(title)")
            }

            // 显示下载后解析的真实像素，而非 UHD 请求标签（规格 7.2）。
            HStack(spacing: 5) {
                Text("Bing")
                Text("·")
                Text(state.wallpaper?.displayDate ?? "—")
                Text("·")
                Text(state.pixelText)
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                ActionButton(title: "设置桌面", systemImage: "display",
                             busy: state.isApplying, disabled: state.wallpaper == nil) {
                    Task { await state.applyDesktop() }
                }
                ActionButton(title: "下载壁纸", systemImage: "square.and.arrow.down",
                             busy: state.isDownloading, disabled: state.wallpaper == nil) {
                    Task { await state.downloadWithConflictCheck() }
                }
                ActionButton(title: "打开目录", systemImage: "folder") {
                    state.revealDirectory()
                }
            }
            .padding(.top, 14)

            if state.needsDirectorySetup {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.orange)
                    Text("首次使用请选择保存目录")
                        .font(.system(size: 11))
                    Spacer()
                    Button("选择目录") { state.changeDirectory() }
                        .font(.system(size: 11))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
                .padding(.top, 12)
            }

            if let message = state.message {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: state.messageIsError
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text(message)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(state.messageIsError ? .red : .secondary)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(state.messageIsError ? Color.red.opacity(0.08) : surfaceColor))
                .padding(.top, 10)
            }

            Divider().padding(.top, 16)

            VStack(spacing: 0) {
                SettingRow(title: "自动下载",
                           value: settings.autoDownload ? "已开启" : "已关闭",
                           highlighted: settings.autoDownload) { state.showingSettings = true }
                SettingRow(title: "自动更换",
                           value: settings.autoChange
                               ? "每天 " + DWFormat.timeString(hour: settings.dailyHour,
                                                               minute: settings.dailyMinute)
                               : "已关闭",
                           highlighted: settings.autoChange) { state.showingSettings = true }
                SettingRow(title: "保存目录",
                           value: StorageService.shared.displayDirectory()) {
                    state.showingSettings = true
                }
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 430)
        .background(Color.white)
        .sheet(isPresented: $state.showingSettings) {
            SettingsView(state: state)
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        // 固定内容宽度 430 - 左右各 16 = 398，按 16:9 取高 224。
        // 主窗口宽度固定；aspectRatio 在 VStack 中会被高度反约束导致预览偏窄。
        Rectangle()
            .fill(Color(nsColor: NSColor.windowBackgroundColor))
            .frame(width: 398, height: 224)
            .overlay(
                ZStack {
                    if let image = state.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .accessibilityLabel("今日壁纸预览")
                    } else if state.previewError != nil {
                        failureView(text: state.previewError ?? "预览加载失败")
                    } else if case .failure(let text) = state.phase {
                        failureView(text: text)
                    } else {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在获取今日壁纸…")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func failureView(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 22))
                .foregroundColor(.secondary)
            Text("暂时无法显示").font(.system(size: 12))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
            Button("重试") { Task { await state.refresh(force: true) } }
                .font(.system(size: 11))
        }
    }
}

// MARK: - 设置面板

/// 纯 Command Line Tools 下 SwiftUI 的 @State 宏插件不可用，
/// 用 ObservableObject 承载弹窗状态（与工程内其它视图一致的写法）。
private final class HelpPopoverState: ObservableObject {
    @Published var showing = false
}

/// 问号说明按钮：图标紧跟分组标题，点击后在上方弹出气泡，说明文字不再常驻占版面。
private struct HelpButton: View {
    let label: String
    let text: String
    @StateObject private var popoverState = HelpPopoverState()

    var body: some View {
        Button {
            popoverState.showing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label)说明")
        .popover(isPresented: $popoverState.showing, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(14)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: WallpaperSettings = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 固定在顶部：滚动到任何位置都能直接关闭设置面板。
            HStack {
                Text("设置").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    section("菜单栏",
                            help: "左键点菜单栏图标打开主窗口，右键打开菜单。关闭图标后，可用 Dimble 启动器或在访达双击应用打开。") {
                        Toggle("显示菜单栏图标", isOn: $settings.showMenuBarIcon)
                    }

                    section("来源与清晰度",
                            help: "图片来源固定为 Bing 每日壁纸。超高清是请求偏好，实际像素以下载后解析结果为准。") {
                        Picker("清晰度", selection: $settings.preferUHD) {
                            Text("超高清 UHD（3840 × 2160）").tag(true)
                            Text("标准（1920 × 1080）").tag(false)
                        }
                        .onChange(of: settings.preferUHD) {
                            Task { await state.changeQuality() }
                        }
                    }

                    section("下载与保存",
                            help: "更改目录只影响之后的下载，不迁移也不删除原目录文件。同一天的重复文件默认跳过，覆盖需逐次确认。") {
                        Toggle("自动下载当天壁纸", isOn: $settings.autoDownload)
                        HStack {
                            Text(StorageService.shared.displayDirectory())
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("更改…") { state.changeDirectory() }
                        }
                    }

                    section("自动化",
                            help: "应用常驻时每分钟检查一次，到点自动执行；关机或睡眠后恢复时按当天补一次，不追溯多日。若任务失败，5 分钟后自动重试，直到当天成功。") {
                        Toggle("每天定时更换桌面", isOn: $settings.autoChange)
                        HStack(spacing: 6) {
                            Text("每日时间")
                            Picker("时", selection: $settings.dailyHour) {
                                ForEach(0..<24, id: \.self) {
                                    Text(String(format: "%02d", $0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 78)
                            Text(":")
                            Picker("分", selection: $settings.dailyMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                                    Text(String(format: "%02d", $0)).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 78)
                            Spacer()
                        }
                    }

                    section("通知与启动",
                            help: "系统拒绝通知授权或登录启动注册失败时，下载与更换桌面仍可正常使用。") {
                        Toggle("下载完成通知", isOn: $settings.notifications)
                        Toggle("登录时启动", isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { value in Task { await state.setLaunchAtLogin(value) } }
                        ))
                    }

                    section("隐私与缓存",
                            help: "缓存位于 ~/Library/Caches/DailyWall，仅用于预览与重试，与保存目录分离，不存放账号凭据。壁纸版权归原权利人，接口声明「仅限用作桌面壁纸」；本应用仅供自用，不打包、不分发、不商用图片。") {
                        HStack {
                            Text("当前占用 \(ImageCache.shared.usageText())")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("清理应用缓存") { state.clearCache() }
                        }
                    }
                }
                .padding(16)
                .frame(width: 430)
            }
        }
        .frame(width: 430)
        .frame(maxHeight: 620)
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, help: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                HelpButton(label: title, text: help)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
