# Settings

Autoplay uses the persistent `autoplay` preference, defaulting to true when unset.
The shared player reads it on entry for both remote and downloaded movies. Turning
it off prepares/seeks the movie without starting playback, leaving controls visible.

Notifications, Wi-Fi-only downloads, and video-quality preference are visual
placeholders. They do not register push notifications, restrict network access,
or choose movie quality.
Actual download quality continues to be chosen in each movie's Download Settings.

Storage reads the current account's download files (including partial transfers),
plus volume used/free space. Other used space excludes Mirror downloads to avoid
double counting. Delete all downloads requires confirmation and refreshes storage.
The monochrome switches have contrasting thumbs; the slider uses the same circular
thumb treatment as Filters, and the scroll content clears the bottom navigation.

Appearance is saved in `appThemeMode`. Dark is the default and retains the original
palette. Light uses adaptive surfaces, text, controls, and navigation. System clears
the app override and follows the device live. There is no forced appearance in the
app plist. Fullscreen playback and its settings remain dark. Literal hex colors
(such as profile avatar colors) are unchanged; `Color(mirrorHex:)` is reserved for
adaptive design colors.
