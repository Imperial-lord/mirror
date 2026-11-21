import CoreAudio
import Foundation

/// Pause when the default output changes, avoiding unexpected playback through speakers.
@MainActor final class DesktopAudioRouteMonitor {
  private var listener: AudioObjectPropertyListenerBlock?
  private var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  func start(_ changed: @escaping @MainActor () -> Void) {
    stop()
    let block: AudioObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in changed() }
    }
    if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
      listener = block
    }
  }
  func stop() {
    if let listener {
      AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    listener = nil
  }
}
