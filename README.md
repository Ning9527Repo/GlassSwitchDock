# GlassSwitchDock

One jailbreak tweak, one package identifier `com.ning.glassswitchdock`, and one PreferenceLoader entry. The package contains both switch replacement and desktop Dock background material. No separate engine package is required.

Exactly three settings:

1. 启用开关 — original Theseus, enabled by default.
2. 启用 Dock 玻璃 — enabled by default.
3. Dock 玻璃样式 — Theseus Clear (default) or Glassify Prominent Clear.

Only the original Theseus switch is used. Its dimensions, materials, colours and animation/physics defaults are unmodified. A sibling overlay keeps its original 63×28 track while forwarding one logical change to the native UISwitch; programmatic updates, disabled state, reparenting and restoration are handled by the integration code. The Glassify switch replacement and selection preference are removed; its archived original source is not compiled into the product.

The Dock integration replaces only its background. Icons, placement, launches and dragging remain system-owned. Starting in 0.1.2, Theseus Clear is a fixed PNG baked by the original Clear shader in the build-host simulator, over a neutral constant background. No user screenshots are inputs. At runtime the Clear Dock creates only a UIView and UIImageView: no TheseusView, Metal renderer, wallpaper capture, timer, initial-device-frame bake or on-device cache. The fixed face and highlights keep the same pixels when wallpaper or appearance changes; system-owned frame and corner radius still follow Dock geometry. It preserves Clear's neutral material treatment rather than the old wallpaper-specific refracted texture. If the asset is unavailable the native background stays visible.

Glassify Prominent Clear retains its previous live Clear plus secondarySystemFillColor path, including the wallpaper-only adapter. Both original libraries remain bundled because the unchanged switch and alternate Glassify style use them. Source hashes of all 89 original vendor files remain unchanged.

Pinned originals:

- [Theseus](https://github.com/valzevul/Theseus): `71ca1c127a4e7fe3387361f160c4890dbd427f66`.
- [Glassify](https://github.com/dotdot911/Glassify): `a8e52aa9c015502fb68d5f81687698f11df6977d`.

All 89 original distribution files are checked against `Vendor/manifest.json`. Source comments, licences and NOTICE files are preserved. Integration by Ning; upstream authors Vadim Drobinin and Hung Phan.

## Build and verification

Use the manual **Native GlassSwitchDock** GitHub Actions workflow. macOS/Xcode compiles the actual Swift, Objective-C++, C++ and Metal code and runs the UIKit simulator harness. The workflow builds and delivers only real arm64e RootHide, with one deb.

Portable checks: `make check`, `make infra-check`, `python3 tools/test-local.py`.
Native checks: `make smoke`, `bash tools/run-ci-simulator.sh`, `make build ARCH=arm64e`, `make verify`.

Final debs are re-extracted and checked for exact installation layout, entry/resource uniqueness, original Metal output, actual CPU subtype, dependency binding, hashes and strict native signatures. The installer does not respring or terminate processes.

Simulator tests exercise original controls, real GPU pipelines and synthetic Dock views. They are not physical-device SpringBoard or real HID/XCUITest validation. Device appearance, wallpaper capture, third-party tweak compatibility and performance still require on-device testing. Never treat a successful compile as proof of those outcomes.
