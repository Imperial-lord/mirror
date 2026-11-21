import SwiftUI

struct SubtitleAppearanceSettings: View {
  @AppStorage("subtitleFontSize") private var size = 18.0
  @AppStorage("subtitleBackgroundOpacity") private var opacity = 0.65
  @AppStorage("subtitleBottomInset") private var inset = 0.0
  @AppStorage("subtitleTimingOffset") private var offset = 0.0
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Subtitle appearance").font(.headline)
      Text("A story worth watching.")
        .font(.system(size: size, weight: .medium)).foregroundStyle(.white)
        .padding(8).background(.black.opacity(opacity), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, minHeight: 60).background(Color.gray.opacity(0.4))
      Text("Text size · \(Int(size))")
      Slider(value: $size, in: 12...32, step: 1).accessibilityLabel("Subtitle text size")
      Text("Background · \(Int(opacity * 100))%")
      Slider(value: $opacity, in: 0...1, step: 0.05).accessibilityLabel("Subtitle background opacity")
      Text("Raise subtitles · \(Int(inset))")
      Slider(value: $inset, in: 0...100, step: 5).accessibilityLabel("Raise subtitles")
      Stepper(value: $offset, in: -10...10, step: 0.5) {
        Text("Timing · \(offset, specifier: "%+.1f") seconds")
      }
      Text("Positive timing makes subtitles appear later.")
        .font(.caption).foregroundStyle(.secondary)
      Button("Reset subtitle settings") { size = 18; opacity = 0.65; inset = 0; offset = 0 }
    }
  }
}
