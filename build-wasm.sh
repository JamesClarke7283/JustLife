#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="just-life"
CARGO_TARGET="wasm32-unknown-unknown"
WASM_DIR="${SCRIPT_DIR}/web"
WASM_FILE="${WASM_DIR}/${PROJECT_NAME}.wasm"
# First arg selects the cargo profile: `wasm-release` (default, optimized) or
# `wasm-dev` (fast, no LTO - use for quick verification builds).
PROFILE="${1:-wasm-release}"

echo "Building ${PROJECT_NAME} for WASM (profile: ${PROFILE})..."
cargo build --profile "${PROFILE}" --target "${CARGO_TARGET}"

mkdir -p "${WASM_DIR}"

echo "Running wasm-bindgen..."
"${HOME}/.cargo/bin/wasm-bindgen" \
    --out-dir "${WASM_DIR}" \
    --target web \
    --no-typescript \
    "${SCRIPT_DIR}/target/${CARGO_TARGET}/${PROFILE}/${PROJECT_NAME}.wasm"

# Size optimization: run wasm-opt -Oz on release builds when binaryen is
# available. Skipped for wasm-dev (favours build speed) and when wasm-opt is
# absent (the build still succeeds, just larger).
BG_WASM="${WASM_DIR}/${PROJECT_NAME}_bg.wasm"
if [ "${PROFILE}" = "wasm-release" ]; then
    if command -v wasm-opt >/dev/null 2>&1; then
        BEFORE=$(stat -c%s "${BG_WASM}" 2>/dev/null || echo 0)
        echo "Optimizing with wasm-opt -Oz..."
        wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
            -o "${BG_WASM}.opt" "${BG_WASM}"
        mv "${BG_WASM}.opt" "${BG_WASM}"
        AFTER=$(stat -c%s "${BG_WASM}" 2>/dev/null || echo 0)
        echo "wasm-opt: ${BEFORE} -> ${AFTER} bytes."
    else
        echo "wasm-opt not found on PATH - skipping -Oz size pass."
        echo "  Install binaryen (provides wasm-opt) for a smaller release binary."
    fi
fi

echo "WASM build complete. Output in ${WASM_DIR}"
