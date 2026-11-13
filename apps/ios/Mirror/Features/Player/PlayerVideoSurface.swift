import AVKit
import SwiftUI

/// Owns the native video layer and the Picture in Picture controller tied to it.
@MainActor
final class PlayerVideoSurface: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var canStartPictureInPicture = false
    @Published private(set) var isInPictureInPicture = false
    @Published private(set) var pictureInPictureError = false

    private var controller: AVPictureInPictureController?
    private var possibility: NSKeyValueObservation?
    private var readiness: NSKeyValueObservation?
    private weak var layer: AVPlayerLayer?

    func attach(_ layer: AVPlayerLayer, player: AVPlayer, onFrameReady: @escaping () -> Void) {
        guard self.layer !== layer || layer.player !== player else { return }
        detach()
        self.layer = layer
        layer.videoGravity = .resizeAspect
        layer.player = player
        readiness = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak player] layer, _ in
            Task { @MainActor in
                guard self?.layer === layer, let player, layer.player === player, layer.isReadyForDisplay else { return }
                onFrameReady()
            }
        }
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        self.controller = controller
        controller.delegate = self
        possibility = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor in
                guard self?.controller === controller else { return }
                self?.canStartPictureInPicture = controller.isPictureInPicturePossible
            }
        }
    }

    func detach() {
        readiness = nil
        possibility = nil
        controller?.delegate = nil
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        controller = nil
        layer?.player = nil
        layer = nil
        canStartPictureInPicture = false
        isInPictureInPicture = false
    }

    func dismissPictureInPictureError() { pictureInPictureError = false }

    func togglePictureInPicture() {
        guard let controller else { return }
        pictureInPictureError = false
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if !isInPictureInPicture, controller.isPictureInPicturePossible {
            isInPictureInPicture = true
            controller.startPictureInPicture()
        }
    }

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            guard controller === pictureInPictureController else { return }
            isInPictureInPicture = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            guard controller === pictureInPictureController else { return }
            isInPictureInPicture = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            guard controller === pictureInPictureController else { return }
            isInPictureInPicture = false
            pictureInPictureError = true
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // The fullscreen player stays presented while PiP is active.
        Task { @MainActor in
            completionHandler(controller === pictureInPictureController && layer?.player != nil)
        }
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let surface: PlayerVideoSurface
    let onFrameReady: () -> Void

    final class VideoView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        weak var expectedPlayer: AVPlayer?
        var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> VideoView { VideoView() }

    func updateUIView(_ view: VideoView, context: Context) {
        view.expectedPlayer = player
        // Publish capability changes outside SwiftUI's view update.
        Task { @MainActor [weak view, weak player] in
            guard let view, let player, view.expectedPlayer === player else { return }
            surface.attach(view.videoLayer, player: player, onFrameReady: onFrameReady)
        }
    }
    static func dismantleUIView(_ view: VideoView, coordinator: ()) { view.expectedPlayer = nil }
}

struct PlayerAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
