# Launcher artwork

[AppLogo.png](AppLogo.png) is the original Figma screen 11 image fill, node `302:2`: 634 × 472 RGBA pixels, SHA-256 `6a37d349ed249b8545c0c3e583405094eb6efe609abbc5f23629ad675c7a15bd`. Preserve the full composition without redrawing, cropping or recoloring. The in-app horizontal wordmarks are separate assets and remain unchanged.

The launcher source stays outside Flutter's in-app asset bundle because Android, iOS and the web host package their own resources. All generated icons are checked in; ordinary Flutter builds do not require the generator.

## Regeneration

From the repository root on Windows, using Windows PowerShell and System.Drawing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File app/tool/generate_launcher_icons.ps1
```

The script uses nearest-neighbor sampling of the original composition on **#163F2E**. Standard square icons use a 450/512 artwork-width ratio. Adaptive and maskable outputs use safe insets; round masks reject cropping visible artwork. No lettering is reconstructed and no monochrome variant is invented.

[platform_icons.json](platform_icons.json) records all 36 platform images, dimensions, placement, masks and SHA-256 hashes:

- Android: five legacy icons, five round fallbacks and five adaptive foregrounds, with background/adaptive XML resources in `app/android/app/src/main/res/`.
- iOS: fifteen unique opaque RGB PNGs covering every existing AppIcon catalog entry, including the 1024px marketing icon.
- Web: 192/512 standard and maskable icons, a 48px favicon and a 180px apple-touch icon.

The application needs the actual platform resources, not separate exported preview images. iOS exports have no alpha; system icon masks supply rounding. Production signing, store publishing and Apple runtime validation require their respective environments.
