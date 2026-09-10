# Disk Checker icon

`AppIcon-source.png` is the original generated artwork, saved in the repository. Created using the built-in image generation tool. Transparent pixels around the tile are preserved when producing icon sizes.

The packaging script runs `scripts/build-icon.sh` to create all ten standard macOS icon representations (16–1024 pixels) and assembles `.build/AppIcon.icns`. It copies the icon to `Disk Checker.app/Contents/Resources/AppIcon.icns` and sets `CFBundleIconFile` in the bundle's Info.plist. The sidebar uses the application's bundled icon as well.

Generation prompt:

> Use case: logo-brand. Create a finished macOS application icon for Disk Checker, a local storage analyzer and cleanup utility. Single icon, square 1024x1024 canvas, genuinely transparent outside the icon. A softly rounded-square deep midnight navy tile with subtle premium satin shading, occupying about 88% of the canvas, centered. On the tile a bold dimensional circular disk-storage chart: thick segmented ring in luminous teal, turquoise and a smaller blue segment, with a clean white checkmark centered in the dark circular opening. Simple large shapes, crisp silhouette and outstanding readability at 32px. Restrained polished macOS desktop-app aesthetic, subtle bevels and soft depth, straight-on view. No lettering, no numbers, no caption, no watermark, no additional objects, no mockup scene, no fake checkerboard background. Teal palette matches the existing app interface.
