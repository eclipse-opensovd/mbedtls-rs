#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Copyright (c) Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Apache License Version 2.0 which is available at
# https://www.apache.org/licenses/LICENSE-2.0
#
# SPDX-License-Identifier: Apache-2.0
#
# regenerate-bindings.sh
#
# Regenerates mbedtls-sys/src/bindings.rs from the vendored mbedtls headers.
# The output is written directly to the source tree so it can be committed.
#
# Usage:
#   scripts/regenerate-bindings.sh
#
# Requirements:
#   - clang (for bindgen's libclang)
#   - Rust 1.88 toolchain (cargo)
#   - pinned nightly Rust toolchain with rustfmt
#   - vendor/mbedtls-4.0.0/ must exist (run refresh-vendor.sh first)
#
# Cross-compilation:
#   Set BINDGEN_SYSROOT to your SDK sysroot before running this script.

set -euo pipefail

NIGHTLY_TOOLCHAIN="nightly-2025-07-14"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[regenerate-bindings] $*"; }
err() { echo "[regenerate-bindings] ERROR: $*" >&2; exit 1; }

VENDOR="${REPO_ROOT}/vendor/mbedtls-4.0.0"
if [ ! -f "${VENDOR}/CMakeLists.txt" ]; then
    err "vendor/mbedtls-4.0.0/ not found. Run scripts/refresh-vendor.sh first."
fi

if ! command -v clang >/dev/null 2>&1; then
    err "clang not found. Install clang before regenerating bindings."
fi

if ! rustup run "${NIGHTLY_TOOLCHAIN}" rustfmt --version >/dev/null 2>&1; then
    err "Pinned nightly rustfmt not found. Install the nightly toolchain with rustfmt."
fi

log "Regenerating src/bindings.rs (this triggers a full mbedtls build)..."
cargo build \
    --manifest-path "${REPO_ROOT}/mbedtls-sys/Cargo.toml" \
    --features generate-bindings

log "Formatting generated bindings with nightly rustfmt..."
rustup run "${NIGHTLY_TOOLCHAIN}" rustfmt \
    --edition 2024 \
    --config-path "${REPO_ROOT}/.rustfmt.toml" \
    "${REPO_ROOT}/mbedtls-sys/src/bindings.rs"

log "Done. mbedtls-sys/src/bindings.rs updated."
log "Review the diff and commit if correct."
