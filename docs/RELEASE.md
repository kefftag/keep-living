# Releasing Keep Living (Steam)

## Builds
```bash
tools/release/build.sh            # macOS (universal), Windows x64, Linux x64 -> build/
tools/release/build.sh macOS      # one platform
```
- **Templates:** you need the Godot export templates for the editor version (now 4.7.2) in
  `~/Library/Application Support/Godot/export_templates/<version>.stable/`.
- **Presets** are in `export_presets.cfg`, which is committed. It holds no secrets, so keep it
  that way: signing identities go in `.godot/export_credentials.cfg`, which is not committed.
- **Smoke check:** the script unzips the macOS build and runs `--smoke-test` inside the shipped
  app, so a broken export fails loudly.
- **Steam Deck:** it runs the Linux x86_64 build natively. It also runs the Windows build through
  Proton.

## Steamworks setup (manual, needs the publisher account)
1. Pay the Steam Direct fee. Create the app and note the App ID and its depot IDs, one per OS.
2. Fill in the store page:
   - Short and long descriptions, tags (Survival, Roguelite, Horror, First-Person, Atmospheric).
   - Content descriptors: violence, gore.
   - Store and library art. The capsule art starts in `docs/steam/` (made by
     `tools/brand/make_icon.py`). Steam also needs a library hero (3840x1240), a library logo
     and a page background. Make those from real game screenshots once lighting and textures
     are final.
   - Screenshots: at least 5 at 1920x1080. A trailer is strongly recommended.
3. Upload with **SteamPipe** (steamcmd or ContentBuilder): one depot per platform, with each
   depot's content root at `build/<platform>/`. Launch options:
   - Windows `KeepLiving.exe`
   - macOS `Keep Living.app`
   - Linux `KeepLiving.x86_64`
4. **macOS:** Steam requires notarized builds for a good first-launch experience. Set
   `codesign/codesign=3` (rcodesign) or `=2` (Xcode), plus `notarization/*` in the macOS
   preset, with a Developer ID certificate and an App Store Connect API key. Until then the
   build is ad-hoc signed and Gatekeeper warns on first launch.
5. **Windows icon:** set `application/modify_resources=true` and point Godot at `rcedit`
   (Editor Settings > Export > Windows) to embed `icon.png` in the .exe.
6. **Steamworks SDK features** (achievements, cloud saves, overlay) need the GodotSteam
   GDExtension. Cloud saves can simply sync `user://keep_living_meta.json` and
   `user://settings.cfg` with Steam Auto-Cloud, with no code needed: the user data dir is
   `KeepLiving` (`config/use_custom_user_dir`).
7. **Release review:** submit the store page and build for review a few days before launch.
   "Coming Soon" needs to be live for at least 2 weeks.

## Pre-launch checklist
- [ ] Smoke test passes headless and in the exported app.
- [ ] Clean playthroughs of every scenario on Windows, macOS and Steam Deck.
- [ ] 60 fps at 1080p on mid hardware (GTX 1060 / M1). Check with the in-game FPS readout.
- [ ] Settings persist: volume, sensitivity, FOV, fullscreen, resolution scale.
- [ ] No placeholder text and no debug prints.
- [ ] Credits list every CC0/OFL asset (`assets/textures/CREDITS.md`, `assets/models/CREDITS.md`,
  `assets/fonts/OFL_*.txt`).
- [ ] Controller support (Steam Deck verification needs it).
