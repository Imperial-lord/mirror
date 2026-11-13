import SwiftUI

public struct PlayerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSpeed: Float
    @Binding var selectedQuality: String
    let audioLabel: String
    @Binding var selectedSubtitle: String

    private let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
    var qualities: [String] = ["Full HD 1080", "HD 720", "SD 480"]
    var subtitleStatus: String? = nil
    let subtitleOptions: [String]

    public init(
        selectedSpeed: Binding<Float>,
        selectedQuality: Binding<String>,
        selectedSubtitle: Binding<String>,
        qualities: [String] = ["Full HD 1080", "HD 720", "SD 480"],
        subtitleStatus: String? = nil,
        subtitleOptions: [String] = ["Off", "English", "Italian", "Spanish", "French"],
        audioLabel: String = "Original audio"
    ) {
        self._selectedSpeed = selectedSpeed
        self._selectedQuality = selectedQuality
        self.audioLabel = audioLabel
        self.subtitleOptions = subtitleOptions
        self._selectedSubtitle = selectedSubtitle
        self.qualities = qualities
        self.subtitleStatus = subtitleStatus
    }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "121215").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                // Top Header (Behance Board 17)
                HStack {
                    Button(action: { dismiss() }) {
                        PhosphorView(.caretLeft, size: 15)
                            .foregroundColor(Color.mirrorInk)
                            .frame(width: 36, height: 36)
                            .background(Color.mirrorInk.opacity(0.08))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.mirrorInk)

                    Spacer()

                    Circle()
                        .fill(Color.clear)
                        .frame(width: 36, height: 36)
                }
                .padding(.top, Spacing.md)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 1. Video Quality Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Video Quality")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            HStack(spacing: 8) {
                                ForEach(qualities, id: \.self) { quality in
                                    let isSelected = selectedQuality == quality
                                    Button(action: {
                                        HapticManager.shared.selection()
                                        selectedQuality = quality
                                    }) {
                                        Text(quality)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(isSelected ? Color.mirrorOnInk : Color.mirrorInk)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(isSelected ? Color.mirrorInk : Color(mirrorHex: "18181B"))
                                            .cornerRadius(10)
                                    }.disabled(qualities.count == 1)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(mirrorHex: "18181B"))
                        .cornerRadius(14)

                        // 2. Playback Speed Section (Behance Board 17)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Playback speed")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.mirrorTextTertiary)

                            HStack(spacing: 8) {
                                ForEach(speeds, id: \.self) { speed in
                                    let isSelected = selectedSpeed == speed
                                    Button(action: {
                                        HapticManager.shared.selection()
                                        selectedSpeed = speed
                                    }) {
                                        Text(speed == 1.0 ? "1x" : "\(speed, specifier: "%g")x")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(isSelected ? Color.mirrorOnInk : Color.mirrorInk)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(isSelected ? Color.mirrorInk : Color(mirrorHex: "222226"))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(mirrorHex: "18181B"))
                        .cornerRadius(14)

                        // The source audio is fixed; this tile intentionally has no action or chevron.
                        HStack {
                            Text("Audio").font(.system(size: 15))
                            Spacer()
                            Text(audioLabel).font(.system(size: 14)).foregroundStyle(Color.mirrorTextTertiary)
                        }.padding(16).frame(maxWidth: .infinity)
                            .background(Color(mirrorHex: "18181B"), in: RoundedRectangle(cornerRadius: 14))

                        // 4. Subtitle Tracks Section
                        if let subtitleStatus {
                            Text(subtitleStatus).font(.system(size: 12)).foregroundStyle(Color.mirrorTextSecondary)
                        }
                        Menu {
                            ForEach(subtitleOptions, id: \.self) { option in
                                Button(option) {
                                    selectedSubtitle = option
                                }
                            }
                        } label: {
                            HStack {
                                Text("Subtitle")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color.mirrorInk)
                                Spacer()
                                Text(selectedSubtitle)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.mirrorTextTertiary)
                                if subtitleOptions.count > 1 { PhosphorView(.caretRight, size: 12, color: Color.mirrorInk.opacity(0.35)) }
                            }
                            .padding(16)
                            .background(Color(mirrorHex: "18181B"))
                            .cornerRadius(14)
                        }.disabled(subtitleOptions.count <= 1)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
