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
# refresh-vendor.sh
#
# Downloads mbedtls, applies our patches, and replaces vendor/mbedtls-{VERSION}/.
# Run this when upgrading mbedtls or after modifying patches.
#
# Usage:
#   scripts/refresh-vendor.sh
#
# Requirements:
#   - curl or wget
#   - sha256sum (or shasum on macOS)
#   - patch(1)
#   - tar, bzip2
#
# The script will:
#   1. Download mbedtls-{VERSION}.tar.bz2 from GitHub releases
#   2. Verify SHA-256
#   3. Extract to vendor/mbedtls-{VERSION}-staging/
#   4. Remove files not used by the library-only build
#   5. Apply all patches from mbedtls-sys/patches/ in order
#   6. Replace vendor/mbedtls-{VERSION}/ with the staging tree

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MBEDTLS_VERSION="4.0.0"
TARBALL_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/mbedtls-${MBEDTLS_VERSION}.tar.bz2"
TARBALL_SHA="2f3a47f7b3a541ddef450e4867eeecb7ce2ef7776093f3a11d6d43ead6bf2827"

VENDOR_DIR="${REPO_ROOT}/vendor"
PATCHES_DIR="${REPO_ROOT}/mbedtls-sys/patches"
STAGING="${VENDOR_DIR}/mbedtls-${MBEDTLS_VERSION}-staging"
TARGET="${VENDOR_DIR}/mbedtls-${MBEDTLS_VERSION}"
TARBALL="${VENDOR_DIR}/mbedtls-${MBEDTLS_VERSION}.tar.bz2"

# Helpers
log() { echo "[refresh-vendor] $*"; }
err() {
    printf '[refresh-vendor] ERROR: %s\n' "$@" >&2
    exit 1
}

sha256_check() {
    local file="$1"
    local expected="$2"
    local actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        err "Neither sha256sum nor shasum found. Cannot verify download."
    fi
    if [ "$actual" != "$expected" ]; then
        err "SHA-256 mismatch for $file" "  expected: $expected" "  got:      $actual"
    fi
    log "SHA-256 OK: $file"
}

download() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --output "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        err "Neither curl nor wget found."
    fi
}

prune_vendor_tree() {
    local root="$1"

    rm -rf \
        "${root}/.github" \
        "${root}/3rdparty" \
        "${root}/ChangeLog.d" \
        "${root}/configs" \
        "${root}/docs" \
        "${root}/doxygen" \
        "${root}/programs" \
        "${root}/scripts" \
        "${root}/tests" \
        "${root}/tf-psa-crypto/.github" \
        "${root}/tf-psa-crypto/ChangeLog.d" \
        "${root}/tf-psa-crypto/configs" \
        "${root}/tf-psa-crypto/docs" \
        "${root}/tf-psa-crypto/programs" \
        "${root}/tf-psa-crypto/scripts" \
        "${root}/tf-psa-crypto/tests"

    find "${root}/framework" -mindepth 1 ! -name CMakeLists.txt -delete
    find "${root}/tf-psa-crypto/framework" -mindepth 1 ! -name CMakeLists.txt -delete
    find "${root}" -name .gitignore -delete

    rm -f \
        "${root}/tf-psa-crypto/doxygen/tfpsacrypto.doxyfile" \
        "${root}/tf-psa-crypto/doxygen/input/doc_mainpage.h"

    rm -f \
        "${root}/.gitattributes" \
        "${root}/.gitignore" \
        "${root}/.gitmodules" \
        "${root}/.globalrc" \
        "${root}/.mypy.ini" \
        "${root}/.pylintrc" \
        "${root}/.readthedocs.yaml" \
        "${root}/.travis.yml" \
        "${root}/.uncrustify.cfg" \
        "${root}/BRANCHES.md" \
        "${root}/BUGS.md" \
        "${root}/ChangeLog" \
        "${root}/CONTRIBUTING.md" \
        "${root}/DartConfiguration.tcl" \
        "${root}/README.md" \
        "${root}/SECURITY.md" \
        "${root}/SUPPORT.md" \
        "${root}/dco.txt" \
        "${root}/library/Makefile" \
        "${root}/tf-psa-crypto/drivers/everest/Makefile.inc" \
        "${root}/tf-psa-crypto/drivers/everest/README.md" \
        "${root}/tf-psa-crypto/drivers/p256-m/Makefile.inc" \
        "${root}/tf-psa-crypto/drivers/p256-m/README.md" \
        "${root}/tf-psa-crypto/drivers/p256-m/p256-m/README.md" \
        "${root}/tf-psa-crypto/.gitattributes" \
        "${root}/tf-psa-crypto/.gitignore" \
        "${root}/tf-psa-crypto/.gitmodules" \
        "${root}/tf-psa-crypto/.globalrc" \
        "${root}/tf-psa-crypto/.mypy.ini" \
        "${root}/tf-psa-crypto/.pylintrc" \
        "${root}/tf-psa-crypto/.uncrustify.cfg" \
        "${root}/tf-psa-crypto/BRANCHES.md" \
        "${root}/tf-psa-crypto/BUGS.md" \
        "${root}/tf-psa-crypto/ChangeLog" \
        "${root}/tf-psa-crypto/CONTRIBUTING.md" \
        "${root}/tf-psa-crypto/DartConfiguration.tcl" \
        "${root}/tf-psa-crypto/README.md" \
        "${root}/tf-psa-crypto/SECURITY.md" \
        "${root}/tf-psa-crypto/SUPPORT.md"
}

# Main

if [ ! -f "${TARGET}/BUILD.bazel" ]; then
    err "Missing project-owned Bazel file: ${TARGET}/BUILD.bazel"
fi

mkdir -p "$VENDOR_DIR"

# 1. Download tarball
log "Downloading mbedtls ${MBEDTLS_VERSION}..."
download "$TARBALL_URL" "$TARBALL"

# 2. SHA-256 verify
sha256_check "$TARBALL" "$TARBALL_SHA"

# 3. Extract to staging dir (clean slate)
log "Extracting to ${STAGING}..."
if [ -d "$STAGING" ]; then
    rm -rf "$STAGING"
fi
mkdir -p "$STAGING"
# The tarball contains a top-level mbedtls-{VERSION}/ directory; strip it.
tar -xjf "$TARBALL" -C "$STAGING" --strip-components=1
rm -f "$TARBALL"

# 4. Keep only inputs used by the library-only build. This also removes the
# unused BSD-3-Clause-only TF-PSA configuration profile.
log "Pruning files unused by the library-only build..."
prune_vendor_tree "$STAGING"

# 5. Apply required patches
log "Applying patches from ${PATCHES_DIR}..."
for patch_file in \
    "${PATCHES_DIR}/record-size-limit-tls12.patch" \
    "${PATCHES_DIR}/ed25519-psa-driver.patch" \
    "${PATCHES_DIR}/embed-ed25519-extract-header.patch" \
    "${PATCHES_DIR}/cmake-build-dir-generated-files.patch" \
    "${PATCHES_DIR}/preserve-toolchain-archiver.patch"; do
    if [ ! -f "$patch_file" ]; then
        err "Required patch not found: $patch_file"
    fi
    log "  Applying $(basename "$patch_file")..."
    # Patches use paths like `a/mbedtls-4.0.0/library/...` so -p2 strips
    # the leading `a/mbedtls-4.0.0/` prefix correctly.
    patch -p2 -d "$STAGING" < "$patch_file" || err "Patch failed: $(basename "$patch_file")"
done
log "Applied required patches."

# 6. Preserve project-owned Bazel metadata.
cp "${TARGET}/BUILD.bazel" "${STAGING}/BUILD.bazel"

# 7. Atomic replace
log "Replacing ${TARGET}..."
if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
fi
mv "$STAGING" "$TARGET"

log "Done. vendor/mbedtls-${MBEDTLS_VERSION} updated."
log "If bindings need regeneration, run: scripts/regenerate-bindings.sh"
