#!/bin/bash
# Builds the Drebol VPN macOS app and packs it into a DMG.
# Run on a Mac (or in CI on macos-latest):
#   scripts/build-drebol-dmg.sh
#
# What it does:
#   1. `make macos-prepare` — flutter pub get, build_runner codegen
#      (translations + freezed/riverpod), slang translations, and the
#      prebuilt sing-box core (hiddify-core releases); no Go toolchain or
#      submodule needed on the builder.
#   2. `flutter build macos --release` with the Unsigned config: the app is
#      signed ad hoc, no Apple Developer account needed. The VPN then runs
#      through the root helper the user installs on first connect.
#   3. Packs dist/0.1.0/DrebolVPN-0.1.0.dmg — first with fastforge/appdmg
#      (uses macos/packaging/dmg/make_config.yaml: Drebol background +
#      Applications link), falling back to a plain hdiutil DMG when appdmg
#      cannot run on the current Node (known upstream issue).
#
# Without a paid Apple Developer account the DMG is NOT notarized: on first
# launch Gatekeeper complains and the app is opened with right-click → Open.
# With a Developer ID, run macos/scripts/dist.sh developer-id instead (it
# signs + notarizes) and rename its output to DrebolVPN-<version>.dmg.
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"

task_version="$(grep '^version:' pubspec.yaml | sed -E 's/version: *//; s/\+.*//')"
task_out="$task_root/dist/$task_version"
task_app="build/macos/Build/Products/Release/Drebol VPN.app"
task_dmg="$task_out/DrebolVPN-$task_version.dmg"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: this script builds on macOS only (needs Xcode + Flutter for macOS)." >&2
  exit 2
fi

export XCODE_XCCONFIG_FILE="$task_root/macos/Runner/Configs/Unsigned.xcconfig"

make macos-prepare
"${FLUTTER:-flutter}" build macos --release

mkdir -p "$task_out"
rm -f "$task_dmg"

# Pretty DMG first (background + Applications link from make_config.yaml).
if fastforge package --platform macos --targets dmg 2>/dev/null; then
  task_fastforge_dmg="$(find "$task_out" -name '*.dmg' -type f | head -1)"
  if [[ -n "${task_fastforge_dmg:-}" ]]; then
    mv "$task_fastforge_dmg" "$task_dmg"
    echo "Built $task_dmg (fastforge, with background)"
    exit 0
  fi
fi

# Fallback: plain hdiutil DMG (no custom background, always works).
task_stage="$(mktemp -d)"
trap 'rm -rf "$task_stage"' EXIT
ditto "$task_app" "$task_stage/Drebol VPN.app"
ln -s /Applications "$task_stage/Applications"
hdiutil create -volname "Drebol VPN" -srcfolder "$task_stage" -format UDZO -ov "$task_dmg" >/dev/null
echo "Built $task_dmg (hdiutil fallback, no background)"
