# Smiley

Tiny native macOS app to cover kids' faces with smiley emoji before sharing photos.

## Use

1. Open a photo: drag it onto the window, ⌘O, or Finder → Open With → Smiley. All faces are auto-detected and stamped with the current emoji on open (on-device Vision framework — nothing leaves the Mac), and the app switches to the arrow tool for tweaking.
2. Tweak: with the arrow tool, click a stamp to select it, drag its circle's edge inward or outward to resize it, or drag its center to move it. ⌘+ / ⌘− also resize it; ⌫ deletes it. The toolbar **Undo** button (or ⌘Z) removes the last stamp; **Auto Smiley** (⌘D) re-runs detection.
3. To stamp manually, pick an emoji in the toolbar and click a face (a ghost preview follows the cursor; the Size slider sets the default size, which ⌘+/⌘− also adjust when nothing is selected).
4. ⌘S replaces the original photo with the smiley version, keeping the same filename and image format.
5. ⌘W closes the photo and returns to the drop screen for the next one.

## Build

```sh
./build.sh   # swiftc + ad-hoc codesign → Smiley.app
```

Single-file SwiftUI app (`main.swift`), no Xcode project. iPhone photos with EXIF rotation are normalized on open via ImageIO.
