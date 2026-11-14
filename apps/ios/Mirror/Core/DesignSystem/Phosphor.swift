import SwiftUI

/// App icon vocabulary, backed exclusively by official Phosphor 2.1.1 vectors.
/// Regular outlines match the reference; filled variants indicate selected or primary actions.
public enum PhosphorIcon: String, CaseIterable {
    case homeLinear
    case homeBold
    case searchLinear
    case searchBold
    case bookmarkLinear
    case bookmarkBold
    case profileLinear
    case profileBold
    case userLinear
    case arrowLeft
    case arrowRight
    case settingLinear
    case settingBold
    case filter
    case filterSquare
    case heartLinear
    case heartBold
    case playLinear
    case playBold
    case playCircleLinear
    case playCircleBold
    case pauseLinear
    case pauseCircle
    case downloadLinear
    case downloadBold
    case importLinear
    case exportLinear
    case share
    case starLinear
    case starBold
    case magicStar
    case magicStarBold
    case rotateLeft
    case rotateRight
    case backward10
    case forward10
    case lockLinear
    case lockBold
    case slider
    case videoPlay
    case next
    case folder
    case folderAdd
    case eye
    case eyeSlash
    case ticketLinear
    case ticketBold
    case headphoneLinear
    case headphoneBold
    case monitorLinear
    case monitorBold
    case infoLinear
    case infoBold
    case logoutLinear
    case logoutBold
    case closeCircle
    case tickCircle
    case add
    case trash
    case clock
    case screenmirroring
    case maximizeCircle
    case fullscreenEnter
    case fullscreenExit
    case speakerHigh
    case speakerLow
    case speakerMuted
    case moon
    case sun
    case warning
    case editLinear
    case caretLeft
    case caretRight
    case close
    case more
    case film
    case popcorn
    case check
    case userCircleFill
    case userFill
    case smiley
    case camera
    case photo
    case phone
    case tablet
    case prohibit
    case appleLogo
    case googleLogo
    case warningCircle

    public var accessibilityLabel: String {
        switch self {
        case .homeLinear, .homeBold: return "Home"
        case .searchLinear, .searchBold: return "Search"
        case .bookmarkLinear, .bookmarkBold: return "Library"
        case .profileLinear, .profileBold: return "Account"
        case .userLinear, .userCircleFill, .userFill: return "Profile"
        case .arrowLeft, .caretLeft: return "Back"
        case .arrowRight, .next, .caretRight: return "Next"
        case .settingLinear, .settingBold: return "Settings"
        case .filter, .filterSquare: return "Filters"
        case .heartLinear, .heartBold: return "Favorite"
        case .playLinear, .playBold, .playCircleLinear, .playCircleBold: return "Play"
        case .pauseLinear, .pauseCircle: return "Pause"
        case .downloadLinear, .downloadBold, .importLinear: return "Download"
        case .exportLinear: return "Upload"
        case .share: return "Share"
        case .starLinear, .starBold: return "Rating"
        case .magicStar, .magicStarBold: return "Recommendations"
        case .rotateLeft: return "Rotate left"
        case .rotateRight: return "Rotate right"
        case .backward10: return "Rewind 10 seconds"
        case .forward10: return "Forward 10 seconds"
        case .lockLinear, .lockBold: return "Lock"
        case .slider: return "Chapters"
        case .videoPlay: return "Video"
        case .folder: return "Folder"
        case .folderAdd: return "New folder"
        case .eye: return "Show"
        case .eyeSlash: return "Hide"
        case .ticketLinear, .ticketBold: return "Subscriptions"
        case .headphoneLinear, .headphoneBold: return "Support"
        case .monitorLinear, .monitorBold: return "Devices"
        case .infoLinear, .infoBold: return "Information"
        case .logoutLinear, .logoutBold: return "Sign out"
        case .closeCircle: return "Clear"
        case .tickCircle, .check: return "Selected"
        case .add: return "Add"
        case .trash: return "Delete"
        case .clock: return "History"
        case .screenmirroring: return "Cast"
        case .maximizeCircle: return "Picture in picture"
        case .fullscreenEnter: return "Enter full screen"
        case .fullscreenExit: return "Exit full screen"
        case .speakerHigh, .speakerLow: return "Volume"
        case .speakerMuted: return "Muted"
        case .moon: return "Dark mode"
        case .sun: return "Light mode"
        case .warning, .warningCircle: return "Warning"
        case .editLinear: return "Edit"
        case .close: return "Close"
        case .more: return "More"
        case .film: return "Movie"
        case .popcorn: return "Movies"
        case .smiley: return "Kids profile"
        case .camera: return "Camera"
        case .photo: return "Photo library"
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .prohibit: return "Unavailable"
        case .appleLogo: return "Apple"
        case .googleLogo: return "Google"
        }
    }

    public var assetName: String {
        switch self {
        case .homeLinear: return "Phosphor/house"
        case .homeBold: return "Phosphor/house-fill"
        case .searchLinear: return "Phosphor/magnifying-glass"
        case .searchBold: return "Phosphor/magnifying-glass-fill"
        case .bookmarkLinear: return "Phosphor/bookmark-simple"
        case .bookmarkBold: return "Phosphor/bookmark-simple-fill"
        case .profileLinear: return "Phosphor/user-circle"
        case .profileBold, .userCircleFill: return "Phosphor/user-circle-fill"
        case .userLinear: return "Phosphor/user"
        case .arrowLeft: return "Phosphor/arrow-left"
        case .arrowRight, .caretRight: return "Phosphor/caret-right"
        case .settingLinear: return "Phosphor/gear-six"
        case .settingBold: return "Phosphor/gear-six-fill"
        case .filter, .filterSquare: return "Phosphor/sliders-horizontal"
        case .heartLinear: return "Phosphor/heart"
        case .heartBold: return "Phosphor/heart-fill"
        case .playLinear: return "Phosphor/play"
        case .playBold: return "Phosphor/play-fill"
        case .playCircleLinear: return "Phosphor/play-circle"
        case .playCircleBold: return "Phosphor/play-circle-fill"
        case .pauseLinear: return "Phosphor/pause-fill"
        case .pauseCircle: return "Phosphor/pause-circle"
        case .downloadLinear, .importLinear: return "Phosphor/download-simple"
        case .downloadBold: return "Phosphor/download-simple-fill"
        case .exportLinear: return "Phosphor/upload-simple"
        case .share: return "Phosphor/share-fat"
        case .starLinear: return "Phosphor/star"
        case .starBold: return "Phosphor/star-fill"
        case .magicStar: return "Phosphor/sparkle"
        case .magicStarBold: return "Phosphor/sparkle-fill"
        case .rotateLeft, .backward10: return "Phosphor/arrow-counter-clockwise"
        case .rotateRight, .forward10: return "Phosphor/arrow-clockwise"
        case .lockLinear: return "Phosphor/lock-simple"
        case .lockBold: return "Phosphor/lock-simple-fill"
        case .slider: return "Phosphor/stack"
        case .videoPlay, .film: return "Phosphor/film-strip"
        case .next: return "Phosphor/skip-forward"
        case .folder: return "Phosphor/folder-simple"
        case .folderAdd: return "Phosphor/folder-simple-plus"
        case .eye: return "Phosphor/eye"
        case .eyeSlash: return "Phosphor/eye-slash"
        case .ticketLinear: return "Phosphor/ticket"
        case .ticketBold: return "Phosphor/ticket-fill"
        case .headphoneLinear: return "Phosphor/headset"
        case .headphoneBold: return "Phosphor/headset-fill"
        case .monitorLinear: return "Phosphor/devices"
        case .monitorBold: return "Phosphor/devices-fill"
        case .infoLinear: return "Phosphor/info"
        case .infoBold: return "Phosphor/info-fill"
        case .logoutLinear: return "Phosphor/sign-out"
        case .logoutBold: return "Phosphor/sign-out-fill"
        case .closeCircle: return "Phosphor/x-circle"
        case .tickCircle: return "Phosphor/check-circle"
        case .add: return "Phosphor/plus"
        case .trash: return "Phosphor/trash"
        case .clock: return "Phosphor/clock"
        case .screenmirroring: return "Phosphor/screencast"
        case .maximizeCircle: return "Phosphor/picture-in-picture"
        case .fullscreenEnter: return "Phosphor/corners-out"
        case .fullscreenExit: return "Phosphor/corners-in"
        case .speakerHigh: return "Phosphor/speaker-high"
        case .speakerLow: return "Phosphor/speaker-low"
        case .speakerMuted: return "Phosphor/speaker-slash"
        case .moon: return "Phosphor/moon"
        case .sun: return "Phosphor/sun"
        case .warning: return "Phosphor/warning"
        case .editLinear: return "Phosphor/pencil-simple-line"
        case .caretLeft: return "Phosphor/caret-left"
        case .close: return "Phosphor/x"
        case .more: return "Phosphor/dots-three"
        case .popcorn: return "Phosphor/popcorn-fill"
        case .check: return "Phosphor/check"
        case .userFill: return "Phosphor/user-fill"
        case .smiley: return "Phosphor/smiley"
        case .camera: return "Phosphor/camera"
        case .photo: return "Phosphor/image"
        case .phone: return "Phosphor/device-mobile"
        case .tablet: return "Phosphor/device-tablet"
        case .prohibit: return "Phosphor/prohibit"
        case .appleLogo: return "Phosphor/apple-logo-fill"
        case .googleLogo: return "Phosphor/google-logo"
        case .warningCircle: return "Phosphor/warning-circle"
        }
    }
}

public struct PhosphorView: View {
    public let icon: PhosphorIcon
    public var size: CGFloat
    public var color: Color?

    public init(_ icon: PhosphorIcon, size: CGFloat = 22, color: Color? = nil) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    public var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .overlay {
                if icon == .backward10 || icon == .forward10 {
                    Text("10").font(.system(size: size * 0.28, weight: .semibold))
                }
            }
            .foregroundColor(color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(icon.accessibilityLabel)
    }
}
