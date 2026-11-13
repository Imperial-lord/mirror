# macOS app

Reserved for a future native macOS app, its own UI, assets, configuration, Xcode project and tests.
Keep those files here rather than adding platform conditionals to the iOS UI.
The streaming service remains an independently deployed HTTP service under `services/streaming`.
There is no macOS target yet, and sharing Swift UI code is not required by this layout.
