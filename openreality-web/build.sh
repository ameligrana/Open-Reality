#!/bin/bash
# Build the OpenReality WASM runtime.
# Requires: wasm-pack (install via: cargo install wasm-pack)
#
# Usage: ./build.sh [--release]
#
# Output: pkg/ directory with .wasm, .js, and .d.ts files

set -e

cd "$(dirname "$0")"

if ! command -v wasm-pack &> /dev/null; then
    echo "wasm-pack not found. Install it with: cargo install wasm-pack"
    exit 1
fi

MODE=${1:---dev}
if [ "$MODE" = "--release" ]; then
    echo "Building in release mode..."
    wasm-pack build --target web --release
else
    echo "Building in development mode..."
    wasm-pack build --target web --dev
fi

echo ""
echo "Build complete! Output in pkg/"
echo "To test: python3 -m http.server 8080 && open http://localhost:8080"
