# Fonts

Drop the bundled brand TTFs here so the app uses the real type (canon §2). If they're
missing, `Typography.swift` automatically falls back to **SF Pro Rounded**, so the app
still looks clean without them.

Expected files (PostScript names must match `WYDFont.Name` in `Typography.swift`):

- `SpaceGrotesk-Medium.ttf`   (weight 500)
- `SpaceGrotesk-SemiBold.ttf` (weight 600)
- `SpaceGrotesk-Bold.ttf`     (weight 700)
- `Inter-Regular.ttf`         (weight 400)
- `Inter-Medium.ttf`          (weight 500)
- `Inter-SemiBold.ttf`        (weight 600)

Get them from Google Fonts:
- Space Grotesk: https://fonts.google.com/specimen/Space+Grotesk
- Inter:         https://fonts.google.com/specimen/Inter

They are already declared under `UIAppFonts` in `project.yml`. After adding the files,
re-run `xcodegen generate`.
