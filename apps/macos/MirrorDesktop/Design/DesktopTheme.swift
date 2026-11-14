import AppKit
import NukeUI
import SwiftUI

extension Color {
  public init(mirrorHex: String) {
    let value = UInt64(mirrorHex, radix: 16) ?? 0
    let light: [String: UInt64] = [
      "060606": 0xFAFAFA, "121214": 0xF0F0F2, "18181B": 0xE7E7EB, "222226": 0xDADAE0,
      "FFFFFF": 0x111111,
    ]
    self.init(
      NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? value : light[mirrorHex.uppercased()] ?? value
        return NSColor(
          red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
          blue: Double(hex & 255) / 255, alpha: 1)
      })
  }
  public static let mirrorBackground = Color(mirrorHex: "060606")
  public static let mirrorSurface1 = Color(mirrorHex: "121214")
  public static let mirrorSurface2 = Color(mirrorHex: "18181B")
  public static let mirrorSurface3 = Color(mirrorHex: "222226")
  public static let mirrorInk = Color(mirrorHex: "FFFFFF")
  public static let mirrorOnInk = Color.mirrorBackground
  public static let mirrorTextSecondary = mirrorInk.opacity(0.64)
  public static let mirrorTextTertiary = mirrorInk.opacity(0.44)
  public static let mirrorRed = Color(red: 1, green: 0.24, blue: 0.2)
}

enum DesktopTheme: String, CaseIterable {
  case system, light, dark
  var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
}

struct DesktopImage: View {
  let url: URL?
  var cover = true
  var body: some View {
    GeometryReader { box in
      LazyImage(url: url) { state in
        if let image = state.image {
          image.resizable().aspectRatio(contentMode: cover ? .fill : .fit)
            .frame(width: box.size.width, height: box.size.height)
            .clipped()
        } else {
          Color.mirrorSurface2.overlay {
            if state.isLoading {
              ProgressView().controlSize(.small)
            } else {
              PhosphorView(.film, size: 26, color: .mirrorTextTertiary)
            }
          }
        }
      }
    }
    .clipped()
    .accessibilityHidden(true)
  }
}

struct DesktopAction: View {
  let title: String
  var icon: PhosphorIcon? = nil
  var primary = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        if let icon { PhosphorView(icon, size: 18, color: primary ? .mirrorOnInk : .mirrorInk) }
        Text(title).font(.system(size: 13, weight: .semibold))
      }
      .padding(.horizontal, 19).frame(height: 42)
      .foregroundStyle(primary ? Color.mirrorOnInk : .mirrorInk)
      .background(primary ? Color.mirrorInk : .mirrorSurface2, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

struct DesktopIconButton: View {
  let icon: PhosphorIcon
  let help: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      PhosphorView(icon, size: 19).frame(width: 36, height: 36)
        .background(Color.mirrorSurface2, in: Circle())
        .contentShape(Circle())
    }.buttonStyle(.plain).help(help).accessibilityLabel(help)
  }
}

struct DesktopEmpty: View {
  let title: String
  let message: String
  var icon: PhosphorIcon = .film
  var body: some View {
    VStack(spacing: 14) {
      PhosphorView(icon, size: 34, color: .mirrorTextSecondary)
        .frame(width: 86, height: 86).background(Color.mirrorSurface1, in: Circle())
      Text(title).font(.title3.weight(.semibold))
      Text(message).font(.callout).foregroundStyle(Color.mirrorTextSecondary)
        .multilineTextAlignment(.center).frame(maxWidth: 360)
    }.frame(maxWidth: .infinity, minHeight: 260)
  }
}

struct DesktopError: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    VStack(spacing: 14) {
      DesktopEmpty(title: "Something went wrong", message: message, icon: .warningCircle)
      DesktopAction(title: "Try again", action: retry)
    }.padding(24)
  }
}

extension View {
  func desktopPanel() -> some View {
    padding(22).background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 18))
  }
  func desktopField() -> some View {
    textFieldStyle(.plain).padding(13).background(
      Color.mirrorSurface2, in: RoundedRectangle(cornerRadius: 11))
  }
}
