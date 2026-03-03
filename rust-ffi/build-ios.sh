#!/usr/bin/env bash
# build-ios.sh — compile Typst FFI static library for iOS & iOS Simulator,
# then package into a fat lib under Typist/Libs/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBS_DIR="$REPO_ROOT/Frameworks"
mkdir -p "$LIBS_DIR"

# ── Check prerequisites ──────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
  echo "ERROR: cargo not found. Install Rust: https://rustup.rs" >&2
  exit 1
fi

echo "▸ Installing required Rust targets..."
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim

# ── Build ────────────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"

export IPHONEOS_DEPLOYMENT_TARGET=17.0

echo "▸ Building for aarch64-apple-ios (device)..."
cargo build --release --target aarch64-apple-ios

echo "▸ Building for aarch64-apple-ios-sim (simulator)..."
cargo build --release --target aarch64-apple-ios-sim

DEVICE_LIB="$SCRIPT_DIR/target/aarch64-apple-ios/release/libtypst_ios.a"
SIM_LIB="$SCRIPT_DIR/target/aarch64-apple-ios-sim/release/libtypst_ios.a"

# ── XCFramework ──────────────────────────────────────────────────────────────
XCFW_DIR="$LIBS_DIR/typst_ios.xcframework"
rm -rf "$XCFW_DIR"

echo "▸ Creating XCFramework..."
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" \
  -library "$SIM_LIB" \
  -output "$XCFW_DIR"

echo ""
echo "✅ Done! XCFramework at: $XCFW_DIR"
echo ""
echo "Next steps:"
echo "  1. In Xcode → Typist target → General → Frameworks, Libraries,"
echo "     and Embedded Content → click + → Add Other → Add Files..."
echo "     and select Typist/Libs/typst_ios.xcframework"
echo "  2. Or open Typist.xcodeproj and the xcframework will be"
echo "     linked automatically if OTHER_LDFLAGS already contains -ltypst_ios"
