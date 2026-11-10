# ChibiPix

An iOS app that turns a photo of a person or animal into a **Japanese chibi character** or a **pixel-art sprite**.

- **On-device mode** (default, free, private): Apple Vision lifts the subject off the background, finds the face and eyes (people) or head joints (cats and dogs), and Core Image does the styling. Nothing is uploaded.
- **ChatGPT mode** (optional, free): opens Apple's Image Playground with the **ChatGPT** style and your photo as the reference. It uses the ChatGPT account set up on the iPhone (the free plan works), so there's no API key and no cost. For pixel art, ChatGPT's drawing is then snapped to a true pixel grid and palette on the device.

## Requirements

- Xcode 16 or newer (the project uses folder-synchronised groups)
- iOS 17 or newer
- A **real iPhone or iPad** for the best results. Vision's subject lifting doesn't run in the Simulator, so there the whole photo is used without removing the background (the app tells you when this happens).

## Build & run

1. Open `ChibiPix.xcodeproj`.
2. Select the **ChibiPix** target → *Signing & Capabilities* → choose your Team. Change the bundle ID (`com.example.ChibiPix`) to something unique.
3. Plug in your device, pick it as the run destination, and press ⌘R.

If Xcode ever complains about the project file, you can regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen` in this folder (uses `project.yml`).

## Using it

1. Tap **Choose photo** or **Camera**.
2. Pick **Chibi** or **Pixel Art**. On-device results update live as you change the settings.
3. Press and hold the preview to compare it with the original.
4. **Share** or **Save to Photos**. Images are saved as PNG, and transparent backgrounds stay transparent.

### Chibi controls
| Control | Effect |
|---|---|
| Head size | How much the head is enlarged |
| Height | Overall height measured in heads (classic chibi is 2–3) |
| Big eyes | Strength of the anime eye enlargement |
| Ink lines / Rosy cheeks / Eye sparkles | Line art, blush and catchlights |
| Sticker outline | White sticker border with a drop shadow |
| Background | Pastel gradients, or transparent |

### Pixel art controls
| Control | Effect |
|---|---|
| Resolution | Sprite size on its longest side (24–96 px) |
| Palette | Auto (k-means palette built from the photo), PICO-8, Sweetie 16, Game Boy, Pastel Dream, Mono |
| Colours | Number of colours in the Auto palette |
| Remove background / Sprite outline | Cuts out the subject and adds a 1-pixel outline |
| Retro dithering | 4×4 Bayer ordered dithering |

## ChatGPT mode setup (free)

Needs **iOS 26 or later** on an Apple Intelligence iPhone or iPad (iPhone 15 Pro or newer, or an M-series iPad). The app must be built with Xcode 26 or later.

1. In the Settings app, turn on **Apple Intelligence**.
2. Go to **Settings › Apple Intelligence & Siri › ChatGPT** and turn on the extension. It works without an account, or you can sign in to a free ChatGPT account for higher limits.
3. In ChibiPix, switch the engine to **ChatGPT (free)** and tap **Generate with ChatGPT**. Image Playground opens with your photo and a chibi or pixel-art prompt. Check that the **ChatGPT** style is selected, then pick the result you like.

How it works: `Views/ChatGPTSection.swift` presents `imagePlaygroundSheet(...)` with `sourceImage` set to your photo, and `imagePlaygroundGenerationStyle(.externalProvider, ...)` so it opens on the ChatGPT style. The prompts are in `StudioModel.playgroundPrompt`. Image generation is free, but ChatGPT's daily image limits apply.

## Building an .ipa

Building an iOS app needs Apple's toolchain, so this has to run on macOS. There are two ways:

**On a Mac** (Xcode 16+):
```bash
./scripts/build_ipa.sh                        # unsigned → build/ChibiPix.ipa
TEAM_ID=ABCDE12345 ./scripts/build_ipa.sh     # signed development build for your registered devices
```
To get a signed build for TestFlight or the App Store, add `EXPORT_METHOD=app-store-connect` (this needs a paid Apple Developer account).

**Without a Mac (GitHub Actions)**: push this folder to a GitHub repo, open **Actions → Build IPA → Run workflow**, and download `ChibiPix-ipa` from the run's artifacts. This runs on GitHub's macOS machines; public repos use them for free, and private repos use up minutes.

**Installing an unsigned .ipa**: iOS won't install it as-is. Sign it with your Apple ID using [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). With a free Apple ID the app expires after 7 days and has to be re-signed. A paid developer account avoids this.

## How the on-device chibi works

`Processing/ChibiRenderer.swift`
1. **Big eyes**: a `CIBumpDistortion` centred on each detected eye.
2. **Cel shading**: median filter, blur, saturation boost and posterise for flat colour, then `CILineOverlay` for brown ink lines.
3. **Accents**: blush under the eyes and white catchlights on the pupils.
4. **Re-proportioning**: the cut-out is split at the neck. The head is scaled up around the neck point, the body is shortened to match the chosen height, and the seam is feathered.
5. **Sticker finish**: dilated silhouettes give the ink outline, white border and shadow, all placed on a pastel bokeh background in a 1024×1024 square.

## How the pixel art works

`Processing/PixelArtRenderer.swift`: the subject is cut out and pre-filtered, rendered at 4× the grid, and box-averaged into cells. Mostly transparent cells are dropped. Each remaining cell is mapped to the nearest palette colour (with optional Bayer dithering), a 1-pixel outline is drawn around the silhouette, and the sprite is enlarged with nearest-neighbour scaling so every pixel stays crisp.

## Project layout

```
ChibiPix/
├── ChibiPixApp.swift
├── Models/       StyleOptions.swift (options, palettes, backgrounds) · StudioModel.swift (state & rendering pipeline)
├── Processing/   SubjectAnalyzer.swift (Vision) · ChibiRenderer.swift · PixelArtRenderer.swift · ImageUtils.swift
├── Views/        ContentView.swift · OptionsPanel.swift · ChatGPTSection.swift · SettingsView.swift · CameraPicker.swift
└── Assets.xcassets
```

## Limitations

- The on-device chibi works by warping the photo, not by redrawing it. It's fast, free and private, and you can always tell who it is, but it looks more like a "chibified photo sticker" than a hand-drawn anime illustration. ChatGPT mode gives the true hand-drawn look.
- Animal head detection uses Vision's cat/dog body-pose model. For other animals, ChibiPix assumes the head is at the top of the subject.
- With several people in a photo, all of them are cut out, but only the largest face gets the chibi head treatment.
