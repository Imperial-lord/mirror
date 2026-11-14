# Offline downloads

Both apps download the selected source through OCI's HTTP byte-range endpoint. The app assembles one local MP4, plus the chosen subtitle files. Completed offline playback reads those local files; it does not need the streaming server. Account and history synchronization are separate network operations.

## On-device processing

After all source bytes arrive, the OCI session is closed and the download enters **Processing**. One movie is processed at a time. It is not shown as completed until processing and validation reach a terminal state.

The shared local optimizer converts eligible SDR H.264 video to hardware-encoded HEVC at a target of 70% of the original video bitrate. It preserves dimensions, timestamps, rotation, color information, and AAC audio without re-encoding the audio. Subtitle files and watch position are untouched. This is lossy video compression; savings and visual quality depend on the source.

The result must be playable, retain duration, dimensions, frame rate and audio-track count, and decode frames near the beginning, middle and end. Only a result at least 5% smaller is retained. Already HEVC/HDR sources, unsupported audio codecs or devices without a hardware encoder keep the original as a terminal no-conversion result. iOS hardware probing requires iOS 17.4 or later; older supported iOS versions retain the original. Conversion or validation errors mark the download failed, retaining the source for a local-only retry.

A manifest update commits the new file before the source is retired. An existing player may finish using its retained original file. Pause, deletion, account changes and shutdown cancel processing; stale work cannot commit. Interrupted processing restores as paused. On iOS, backgrounding suspends processing and foregrounding resumes it; OS-managed network transfers continue independently. Conversion requires temporary free space for both source and output.

Existing completed downloads are not bulk-converted on upgrade. Re-enqueuing their download settings can process an unprocessed saved source without fetching the video again. This change does not add automatic deletion, lower-resolution choices, or server transcoding.
