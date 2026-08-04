<!--
SPDX-FileCopyrightText: 2026 Copyright (c) Contributors to the Eclipse Foundation

See the NOTICE file(s) distributed with this work for additional
information regarding copyright ownership.

This program and the accompanying materials are made available under the
terms of the Apache License Version 2.0 which is available at
https://www.apache.org/licenses/LICENSE-2.0

SPDX-License-Identifier: Apache-2.0
-->

# mbedtls-rs

Rust FFI bindings and safe wrapper for [Mbed-TLS 4.0.0](https://github.com/Mbed-TLS/mbedtls),
with async (Tokio) TLS stream support.

Mbed-TLS patched to support RFC 8449 on TLS 1.2 and Ed25519 crypto as required by CDA.

## Crates

| Crate | Description |
|---|---|
| `mbedtls-sys` | Raw FFI bindings (pre-generated, no clang required for builds) |
| `mbedtls-rs` | Safe Rust wrapper with async `tokio::io` TLS stream support |

## Workspace layout

```
mbedtls-rs/
|-- Cargo.toml                 workspace root
|-- mbedtls-sys/
|   |-- Cargo.toml
|   |-- build.rs               cmake build + optional bindgen regen
|   |-- wrapper.h              bindgen input header
|   |-- src/
|   |   |-- lib.rs
|   |   `-- bindings.rs        pre-generated, committed
|   |-- csrc/                  ed25519 PSA driver shim (C)
|   `-- patches/               unified diffs applied to vendor source
|-- mbedtls-rs/
|   |-- Cargo.toml
|   `-- src/                   safe wrapper + async TLS stream
|-- vendor/
|   `-- mbedtls-4.0.0/         pre-patched mbedtls source (committed)
`-- scripts/
    |-- refresh-vendor.sh      upgrade vendor source + re-apply patches
    `-- regenerate-bindings.sh regenerate src/bindings.rs (requires clang)
```

## Patches

Two patches live in `mbedtls-sys/patches/` and are applied to the vendored source:

| Patch | Description |
|---|---|
| `record-size-limit-tls12.patch` | Extends RFC 8449 `record_size_limit` to TLS 1.2 |
| `ed25519-psa-driver.patch` | Adds Ed25519 / PureEdDSA support via PSA accelerator |

The Ed25519 math is implemented in Rust (`ed25519-dalek`) and bridged into the PSA
driver layer via the `rust_ed25519_verify` FFI call.

## Vendored source

The vendored tree contains only inputs needed by the static library build.
Upstream tests, programs, documentation, CI metadata, development scripts, and
unused configuration profiles are removed by `scripts/refresh-vendor.sh`.
Upstream license files and required CMake metadata remain in the tree.

## Building

Normal build:

```sh
cargo build
```

Bindings are pre-generated in `mbedtls-sys/src/bindings.rs` and compiled directly.

## Upgrading mbedtls

```sh
# 1. Edit MBEDTLS_VERSION + TARBALL_SHA in scripts/refresh-vendor.sh
# 2. Run the refresh script
scripts/refresh-vendor.sh

# 3. If patches no longer apply cleanly the script will fail.
#    Update the patches manually, then re-run.

# 4. Regenerate bindings (requires clang)
scripts/regenerate-bindings.sh

# 5. Build and test
cargo build
cargo test
```

## Regenerating bindings

After updating vendor source or patches:

```sh
scripts/regenerate-bindings.sh
```

⚠️ Requires clang! The script runs `cargo build --features generate-bindings` for
`mbedtls-sys`, which writes the updated `src/bindings.rs` in-place.

## Using in downstream workspaces

Add as a git dependency:

```toml
[dependencies]
mbedtls-rs = { git = "https://github.com/eclipse-opensovd/mbedtls-rs", rev = "GIT_REV" }
```

For local development, add a `[patch]` override in the downstream
workspace's `.cargo/config.toml`:

```toml
[patch."https://github.com/eclipse-opensovd/mbedtls-rs"]
mbedtls-sys = { path = "../mbedtls-rs/mbedtls-sys" }
mbedtls-rs  = { path = "../mbedtls-rs/mbedtls-rs" }
```

License: Apache-2.0
