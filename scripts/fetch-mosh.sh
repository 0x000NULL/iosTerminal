#!/usr/bin/env bash
# Fetches the prebuilt mosh ios-controller xcframework (GPL-3.0) + its Protobuf_C_ dependency
# into Vendor/. These are NOT committed (see .gitignore) — personal, non-distributed builds only.
# After running this, regenerate the project: `xcodegen generate`.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor && cd Vendor

MOSH_URL="https://github.com/blinksh/mosh-apple/releases/download/v1.4.0%2Bblink-18.4.5/mosh.xcframework.zip"
PB_URL="https://github.com/blinksh/protobuf-apple/releases/download/v3.21.1/Protobuf_C_-static.xcframework.zip"
MOSH_SHA="d6dce7664ecce1b15931d6b0b8aaf3b1cacebe390669df960fe47318cb0dda05"
PB_SHA="a74e23890cf2093047544e18e999f493cf90be42a0ebd1bf5d4c0252d7cf377a"

echo "Downloading mosh.xcframework + Protobuf_C_ ..."
curl -fsSL -o mosh.xcframework.zip "$MOSH_URL"
curl -fsSL -o Protobuf_C_.xcframework.zip "$PB_URL"

echo "Verifying checksums ..."
echo "$MOSH_SHA  mosh.xcframework.zip" | shasum -a 256 -c -
echo "$PB_SHA  Protobuf_C_.xcframework.zip" | shasum -a 256 -c -

echo "Unzipping ..."
unzip -oq mosh.xcframework.zip && unzip -oq Protobuf_C_.xcframework.zip
rm -f mosh.xcframework.zip Protobuf_C_.xcframework.zip

echo "Done → Vendor/mosh.xcframework, Vendor/Protobuf_C_.xcframework"
echo "Next: xcodegen generate"
