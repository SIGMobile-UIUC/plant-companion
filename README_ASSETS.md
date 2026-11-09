# Plant Companion assets

The application uses the original Plant Companion Figma artwork. [asset_manifest.json](asset_manifest.json) records filenames, source nodes, dimensions and SHA-256 hashes for the original 24-PNG pack and three additional original images: the blue cold thermometer, excess-condition slash and AppLogo. The additional records retain the existing `phase_f_assets` manifest key for compatibility and provenance.

Current visual references are [screen 9](https://www.figma.com/design/VKBrJuR8eTByeOF7gppbPz?node-id=264-2), [screen 10](https://www.figma.com/design/VKBrJuR8eTByeOF7gppbPz?node-id=264-451) and [screen 11](https://www.figma.com/design/VKBrJuR8eTByeOF7gppbPz?node-id=280-2).

## Application artwork

Runtime PNGs are in `app/assets/plant_companion/`:

| Directory | Contents |
|---|---|
| `plants/` | The three plant/pot portraits |
| `faces/` | Happy, sad and sleeping faces |
| `needs/` | Thought bubble, healthy heart, full blue cold thermometer and excess slash |
| `sensors/` | Moisture, light, original red thermometer, humidity and rail marker |
| `actions/` | Navigation, menu, refresh and editing artwork |
| `branding/` | Original horizontal Home/selection and Details wordmarks |

The asset directories are already declared in [pubspec.yaml](app/pubspec.yaml). Flutter paths are relative to `app/`, for example `assets/plant_companion/plants/pothos.png`.

Portraits compose plant, face, bubble and need images as independent layers. Preserve their anchors, transparency and nearest-neighbor filtering (`FilterQuality.none`). Text, badges, rail fills, ideal separators and layout are Flutter widgets, not flattened screenshots.

Happy has no Home bubble and uses the original heart in Details. Low light uses the sleeping face; other measured problems use the sad face. Excess moisture/light/humidity add the shared red slash. Cold uses the complete blue thermometer only in its bubble; every standard temperature-row icon remains red. Plants without devices use sleeping/no-bubble presentation without fabricated measurements or timestamps.

## Fonts and launcher resources

Pixelify Sans and Inter are in `app/assets/fonts/`, with their original OFL licenses and declarations in `pubspec.yaml`.

The original launcher source is [artwork/AppLogo.png](artwork/AppLogo.png), outside the in-app bundle. Generated Android, iOS and web icons preserve its composition on `#163F2E`; the original horizontal in-app wordmarks remain unchanged. See [launcher instructions](artwork/README.md) and [platform_icons.json](artwork/platform_icons.json) for regeneration and output hashes.
