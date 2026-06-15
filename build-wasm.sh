#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="just-life"
CARGO_TARGET="wasm32-unknown-unknown"
WASM_DIR="${SCRIPT_DIR}/web"
WASM_FILE="${WASM_DIR}/${PROJECT_NAME}.wasm"

echo "Building ${PROJECT_NAME} for WASM..."
RUSTFLAGS="-C opt-level=s" cargo build --profile wasm-release --target "${CARGO_TARGET}"

mkdir -p "${WASM_DIR}"

echo "Running wasm-bindgen..."
"${HOME}/.cargo/bin/wasm-bindgen" \
    --out-dir "${WASM_DIR}" \
    --target web \
    --no-typescript \
    "${SCRIPT_DIR}/target/${CARGO_TARGET}/wasm-release/${PROJECT_NAME}.wasm"

echo "WASM build complete. Output in ${WASM_DIR}"
