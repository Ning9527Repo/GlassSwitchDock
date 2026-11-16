# GlassSwitchDock

One jailbreak tweak, one package identifier `com.ning.glassswitchdock`, and one PreferenceLoader entry. The package contains both switch replacement and desktop Dock background material. No separate engine package is required.

Exactly four settings:

1. 启用开关 — enabled by default.
2. 开关样式 — original Theseus (default) or original Glassify.
3. 启用 Dock 玻璃 — enabled by default.
4. Dock 玻璃样式 — Theseus Clear (default) or Glassify Prominent Clear.

The two switch implementations, their dimensions, materials, colours and animation/physics defaults are unmodified upstream sources. A sibling overlay keeps their original 63×28 track while forwarding one logical change to the native UISwitch; programmatic updates, disabled state, reparenting and restoration are handled by the integration code. No previous skin implementation is included in this source tree.

The Dock integration replaces only its background. Icons, placement, launches and dragging remain system-owned. The Theseus surface uses `.clear` with container geometry adapted to the system background; Glassify uses its original Clear plus `secondarySystemFillColor`, the background configuration of Prominent Clear. No tab labels or selection lens is added. Both engine source sets and their separate original Metal libraries live in the same package resource bundle.

Pinned originals:

- [Theseus](https://github.com/valzevul/Theseus): `71ca1c127a4e7fe3387361f160c4890dbd427f66`.
- [Glassify](https://github.com/dotdot911/Glassify): `a8e52aa9c015502fb68d5f81687698f11df6977d`.

All 89 original distribution files are checked against `Vendor/manifest.json`. Source comments, licences and NOTICE files are preserved. Integration by Ning; upstream authors Vadim Drobinin and Hung Phan.

## Build and verification

Use the manual **Native GlassSwitchDock** GitHub Actions workflow. macOS/Xcode compiles the actual Swift, Objective-C++, C++ and Metal code and runs the UIKit simulator harness. Default delivery includes ordinary arm64 rootless and real arm64e RootHide, each with exactly one deb. Install only the variant matching your jailbreak.

Portable checks: `make check`, `make infra-check`, `python3 tools/test-local.py`.
Native checks: `make smoke`, `bash tools/run-ci-simulator.sh`, `make build ARCH=all`, `make verify`.

Final debs are re-extracted and checked for exact installation layout, entry/resource uniqueness, original Metal output, actual CPU subtype, dependency binding, hashes and strict native signatures. The installer does not respring or terminate processes.

Simulator tests exercise original controls, real GPU pipelines and synthetic Dock views. They are not physical-device SpringBoard or real HID/XCUITest validation. Device appearance, wallpaper capture, third-party tweak compatibility and performance still require on-device testing. Never treat a successful compile as proof of those outcomes.
