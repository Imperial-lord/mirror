# Icon system

All app-owned interface icons use Phosphor 2.1.1, from the official
[@phosphor-icons/core package](https://www.npmjs.com/package/@phosphor-icons/core).
The selected SVG vectors are bundled in `apps/ios/Mirror/Assets.xcassets/Phosphor` and render
as templates, so they inherit the existing monochrome palette and work offline.
The MIT license is in `docs/licenses/Phosphor-MIT.txt`.

Use `PhosphorView(.downloadLinear, size: 20)` and the typed `PhosphorIcon` vocabulary
in `apps/ios/Mirror/Core/DesignSystem/Phosphor.swift` for interface icons. Do not add SF Symbols,
Iconsax assets, emoji, or text approximations for actions. Regular outlines are the
default; the selected Home tab and primary play/pause actions use fill variants. Search and
Library keep their outline shapes and use white to indicate selection, as in Behance. The seek
icons add a typographic 10-second label over Phosphor's rotation arrows.

Profile photos and character avatars remain images. System-owned interfaces such as
the photo picker, camera, share sheet, and native menu indicators retain iOS controls.
Existing colors, control sizes, and actions are preserved.

`PhosphorAssetTests` checks that every icon resolves from the app bundle and renders
visible pixels. When adding icons, copy the matching SVG from the same official
release, add a template image set, and extend the typed mapping and accessibility label.
