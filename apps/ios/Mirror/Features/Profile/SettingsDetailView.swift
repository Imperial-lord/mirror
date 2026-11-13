import SwiftUI

public enum AppThemeMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

public struct SettingsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appThemeMode") private var themeMode: String = AppThemeMode.dark.rawValue
    @State private var pushNotifications: Bool = true
    @AppStorage("autoplay") private var autoplay: Bool = true
    @State private var downloadOnlyWifi: Bool = true
    @State private var confirmDeleteDownloads = false
    @State private var downloadError: String?
    @State private var disk = (downloads: Int64(0), used: Int64(0), free: Int64(0))
    @State private var videoQualityValue: Double = 0.5 // Good 480

    public init() {}

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (Behance Board 18)
                HStack {
                    Button(action: { dismiss() }) {
                        PhosphorView(.caretLeft, size: 18, color: Color.mirrorInk)
                            .foregroundColor(Color.mirrorInk)
                            .frame(width: 40, height: 40)
                            .background(Color(mirrorHex: "121215"))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.mirrorInk)

                    Spacer()

                    Circle()
                        .fill(Color.clear)
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Notifications
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notifications")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            Toggle("Push notifications", isOn: $pushNotifications)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.mirrorInk)
                                .tint(Color.mirrorInk)
                                .padding(14)
                                .background(Color(mirrorHex: "121215"))
                                .cornerRadius(14)
                        }

                        // 2. Player
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Player")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            Toggle("Autoplay", isOn: $autoplay)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.mirrorInk)
                                .tint(Color.mirrorInk)
                                .padding(14)
                                .background(Color(mirrorHex: "121215"))
                                .cornerRadius(14)
                        }

                        // 3. Downloads
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Downloads")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            Toggle("Download only via Wi-Fi", isOn: $downloadOnlyWifi)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.mirrorInk)
                                .tint(Color.mirrorInk)
                                .padding(14)
                                .background(Color(mirrorHex: "121215"))
                                .cornerRadius(14)
                        }

                        // 4. Video Quality Slider
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Video Quality")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color.mirrorInk)
                                Spacer()
                                Text(videoQualityValue > 0.6 ? "Full HD (1080)" : (videoQualityValue > 0.3 ? "HD (720)" : "Good (480)"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.mirrorTextTertiary)
                            }

                            SettingsQualitySlider(value: $videoQualityValue)
                                .tint(Color.mirrorInk)
                        }
                        .padding(14)
                        .background(Color(mirrorHex: "121215"))
                        .cornerRadius(14)

                        // 5. Storage (Behance Board 18)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Storage")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            Text("Downloaded movies").font(.system(size: 14)).foregroundStyle(Color.mirrorTextSecondary)
                            Text(diskSize(disk.downloads)).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.mirrorInk)
                            GeometryReader { geometry in
                                let total = Double(max(1, disk.used + disk.free))
                                HStack(spacing: 2) {
                                    Rectangle().fill(Color.mirrorInk).frame(width: max(disk.downloads > 0 ? 3 : 0, geometry.size.width * Double(disk.downloads) / total))
                                    Rectangle().fill(Color.mirrorInk.opacity(0.4)).frame(width: max(0, geometry.size.width * Double(max(0, disk.used - disk.downloads)) / total - 2))
                                    Rectangle().fill(Color.mirrorInk.opacity(0.12))
                                }.clipShape(Capsule())
                            }.frame(height: 8)
                            HStack(spacing: 16) {
                                storageIndicator(label: "Mirror", size: diskSize(disk.downloads), color: Color.mirrorInk)
                                storageIndicator(label: "Other used", size: diskSize(max(0, disk.used - disk.downloads)), color: Color.mirrorInk.opacity(0.5))
                                storageIndicator(label: "Free", size: diskSize(disk.free), color: Color.mirrorInk.opacity(0.2))
                            }

                            Button(action: {
                                confirmDeleteDownloads = true
                            }) {
                                Text("Delete all downloads")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(mirrorHex: "EF4444"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding(14)
                        .background(Color(mirrorHex: "121215"))
                        .cornerRadius(14)

                        // 6. Mode / Theme Switcher (Behance Board 18)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Mode")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            HStack(spacing: 12) {
                                themeModeButton(mode: .system, icon: .settingLinear)
                                themeModeButton(mode: .light, icon: .sun)
                                themeModeButton(mode: .dark, icon: .moon)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 16)
                    .padding(.bottom, 110)
                }
            }
        }
        .tint(Color.mirrorInk)
        .toggleStyle(SettingsToggleStyle())
        .navigationBarHidden(true)
        .task { DownloadStore.shared.start(); disk = DownloadStore.shared.diskUsage() }
        .alert("Delete all downloads?", isPresented: $confirmDeleteDownloads) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do { try DownloadStore.shared.deleteAll(); disk = DownloadStore.shared.diskUsage() }
                catch { downloadError = error.localizedDescription }
            }
        } message: { Text("This removes downloaded movies and subtitles from this device. Your watch history will be kept.") }
        .alert("Couldn’t delete downloads", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("OK") { downloadError = nil }
        } message: { Text(downloadError ?? "") }
    }

    private func diskSize(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

    private func storageIndicator(label: String, size: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.mirrorTextTertiary)
                Text(size)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.mirrorInk)
            }
        }
    }

    private func themeModeButton(mode: AppThemeMode, icon: PhosphorIcon) -> some View {
        let isSelected = themeMode == mode.rawValue
        return Button(action: {
            HapticManager.shared.selection()
            themeMode = mode.rawValue
        }) {
            VStack(spacing: 8) {
                PhosphorView(icon, size: 20, color: isSelected ? Color.mirrorInk : Color.mirrorTextTertiary)
                    .foregroundColor(isSelected ? Color.mirrorInk : Color.mirrorTextTertiary)

                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? Color.mirrorInk : Color.mirrorTextTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color(mirrorHex: "18181B") : Color(mirrorHex: "121215"))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.mirrorInk.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
}

private struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button { configuration.isOn.toggle() } label: {
                Circle().fill(configuration.isOn ? Color.mirrorOnInk : Color.mirrorInk)
                    .frame(width: 22, height: 22)
                    .frame(width: 46, height: 28, alignment: configuration.isOn ? .trailing : .leading)
                    .padding(3)
                    .background(configuration.isOn ? Color.mirrorInk : Color.mirrorInk.opacity(0.18), in: Capsule())
            }.buttonStyle(.plain)
                .accessibilityLabel(configuration.isOn ? "On" : "Off")
                .accessibilityValue(configuration.isOn ? "On" : "Off")
        }.accessibilityElement(children: .combine)
    }
}

private struct SettingsQualitySlider: UIViewRepresentable {
    @Binding var value: Double
    @Environment(\.colorScheme) private var scheme
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0; slider.maximumValue = 1
        slider.accessibilityLabel = "Video quality"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }
    func updateUIView(_ slider: UISlider, context: Context) {
        let ink: UIColor = scheme == .dark ? .white : .black
        slider.minimumTrackTintColor = ink
        slider.maximumTrackTintColor = ink.withAlphaComponent(0.14)
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            ink.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        slider.setThumbImage(thumb, for: .normal); slider.setThumbImage(thumb, for: .highlighted)

        context.coordinator.parent = self; slider.value = Float(value)
        slider.accessibilityValue = value > 0.6 ? "Full HD 1080" : value > 0.3 ? "HD 720" : "SD 480"
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject {
        var parent: SettingsQualitySlider
        init(parent: SettingsQualitySlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) { parent.value = Double((slider.value * 2).rounded() / 2) }
    }
}
