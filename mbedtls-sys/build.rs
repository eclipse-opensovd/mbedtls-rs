/*
 * SPDX-FileCopyrightText: 2026 Copyright (c) Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) distributed with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0
 */

//! Build script for mbedtls-sys.
//!
//! Normal build (`cargo build`):
//!   - Locates pre-patched mbedtls source in `vendor/mbedtls-4.0.0/` (workspace root).
//!   - Compiles mbedtls via cmake.
//!   - Compiles the ed25519 PSA driver shim via cc.
//!   - Links the three static archives: mbedtls, mbedx509, tfpsacrypto.
//!   - Uses the pre-generated `src/bindings.rs` checked into the repository.
//!     No clang / bindgen required.
//!
//! Regenerating bindings (`cargo build --features generate-bindings`):
//!   - All of the above, plus runs bindgen against the vendor headers.
//!   - Writes the result to `src/bindings.rs` in the crate source tree
//!     (not OUT_DIR) so the file can be committed.
//!   - Requires clang to be installed.
//!   - Use `scripts/regenerate-bindings.sh` as a convenience wrapper.
//!
//! Environment variables:
//!   - `MBEDTLS_DIR`: override mbedtls source path (skips vendor/ lookup).
//!   - `BINDGEN_SYSROOT`: passed as `--sysroot` to clang (cross-compilation).

#[cfg(feature = "generate-bindings")]
use std::fs;
use std::{
    env,
    path::{Path, PathBuf},
};

const MBEDTLS_VERSION: &str = "4.0.0";
const MBEDTLS_SOURCE_OVERRIDE_VAR: &str = "MBEDTLS_DIR";
#[cfg(feature = "generate-bindings")]
const GENERATED_FILE_HEADER: &str = r"/*
 * SPDX-FileCopyrightText: 2026 Copyright (c) Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) distributed with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0
 */

";

fn main() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

    // vendor/ is at workspace root, two levels up from mbedtls-sys/
    let mbedtls_src = resolve_mbedtls_src(&manifest_dir);

    // Re-run triggers
    println!("cargo:rerun-if-changed=wrapper.h");
    println!("cargo:rerun-if-changed=csrc");
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed={}", MBEDTLS_SOURCE_OVERRIDE_VAR);

    let out_dir =
        PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR not set - must be run by Cargo"));

    // Build mbedtls via cmake
    cmake::Config::new(&mbedtls_src)
        .define("USE_STATIC_MBEDTLS_LIBRARY", "ON")
        .define("USE_SHARED_MBEDTLS_LIBRARY", "OFF")
        .define("ENABLE_TESTING", "OFF")
        .define("ENABLE_PROGRAMS", "OFF")
        .define("MBEDTLS_FATAL_WARNINGS", "OFF")
        // Disable GEN_FILES - the release tarball ships pre-generated files.
        .define("GEN_FILES", "OFF")
        // Enable RFC 8449 record_size_limit extension (our TLS 1.2 patch).
        .cflag("-DMBEDTLS_SSL_RECORD_SIZE_LIMIT")
        // Enable NULL cipher (required for ECDHE_ECDSA_WITH_NULL_SHA etc.)
        .cflag("-DMBEDTLS_SSL_NULL_CIPHERSUITES")
        // Enable our Ed25519 PSA accelerator driver.
        .cflag("-DMBEDTLS_ED25519_PSA_DRIVER")
        // Include path for ed25519_extract.h used by ed25519_psa_driver.c
        .cflag(format!("-I{}", manifest_dir.join("csrc").display()))
        .build();

    // Link search paths emitted by cmake
    for lib in ["lib", "build/library"] {
        let build_lib = out_dir.join(lib);
        if build_lib.exists() {
            println!("cargo:rustc-link-search=native={}", build_lib.display());
        }
    }

    // Link order matters: mbedtls -> mbedx509 -> tfpsacrypto (PSA crypto).
    println!("cargo:rustc-link-lib=static=mbedtls");
    println!("cargo:rustc-link-lib=static=mbedx509");
    println!("cargo:rustc-link-lib=static=tfpsacrypto");

    // Compile the ed25519 PSA accelerator shim (bridges PSA -> rust_ed25519_verify)
    cc::Build::new()
        .file(manifest_dir.join("csrc").join("ed25519_psa_driver.c"))
        .include(manifest_dir.join("csrc"))
        .include(mbedtls_src.join("tf-psa-crypto").join("include"))
        .include(
            mbedtls_src
                .join("tf-psa-crypto")
                .join("drivers")
                .join("builtin")
                .join("include"),
        )
        .include(mbedtls_src.join("include"))
        .warnings(false)
        .compile("ed25519_psa_driver");

    // Optionally regenerate bindings (requires `generate-bindings` feature + clang).
    #[cfg(feature = "generate-bindings")]
    regenerate_bindings(&manifest_dir, &mbedtls_src);
}

/// Resolve the mbedtls source directory.
///
/// Priority:
/// 1. `MBEDTLS_DIR` env var (absolute or relative to cwd).
/// 2. `../../vendor/mbedtls-{VERSION}/` relative to the crate manifest (i.e. workspace root).
fn resolve_mbedtls_src(manifest_dir: &Path) -> PathBuf {
    if let Ok(dir) = env::var(MBEDTLS_SOURCE_OVERRIDE_VAR) {
        let p = PathBuf::from(dir);
        assert!(
            p.join("CMakeLists.txt").exists(),
            "MBEDTLS_DIR does not contain CMakeLists.txt: {}",
            p.display()
        );
        return p;
    }

    // workspace root/vendor/mbedtls-{VERSION}
    let vendor_path = manifest_dir
        .join("..")
        .join("vendor")
        .join(format!("mbedtls-{MBEDTLS_VERSION}"));

    assert!(
        vendor_path.join("CMakeLists.txt").exists(),
        "mbedtls source not found at {}. Run scripts/refresh-vendor.sh or set MBEDTLS_DIR.",
        vendor_path.display()
    );

    vendor_path
}

/// Regenerate `src/bindings.rs` using bindgen.
///
/// Only compiled when the `generate-bindings` feature is active.
/// Writes directly to the crate source tree (not OUT_DIR) so the result
/// can be committed and used by downstream without clang installed.
#[cfg(feature = "generate-bindings")]
fn regenerate_bindings(manifest_dir: &Path, mbedtls_src: &Path) {
    let include_paths: Vec<PathBuf> = vec![
        mbedtls_src.join("include"),
        mbedtls_src.join("tf-psa-crypto").join("include"),
        mbedtls_src
            .join("tf-psa-crypto")
            .join("drivers")
            .join("builtin")
            .join("include"),
        mbedtls_src.join("library"),
        mbedtls_src.join("tf-psa-crypto").join("core"),
        mbedtls_src
            .join("tf-psa-crypto")
            .join("drivers")
            .join("builtin")
            .join("src"),
    ];

    let mut builder = bindgen::Builder::default()
        .header(manifest_dir.join("wrapper.h").to_string_lossy())
        .allowlist_function("mbedtls_.*")
        .allowlist_function("psa_.*")
        .allowlist_type("mbedtls_.*")
        .allowlist_type("psa_.*")
        .allowlist_var("MBEDTLS_.*")
        .allowlist_var("PSA_.*")
        .allowlist_var("TF_PSA_CRYPTO_.*")
        .blocklist_var("MBEDTLS_MPI_UINT_MAX")
        .blocklist_var("MBEDTLS_PRINTF_MS_TIME")
        .derive_debug(true)
        .derive_default(true)
        .derive_copy(true)
        .generate_comments(true)
        .prepend_enum_name(true)
        .opaque_type("mbedtls_time_t")
        .opaque_type("time_t")
        .opaque_type("tm")
        .formatter(bindgen::Formatter::None)
        .layout_tests(false);

    for inc in &include_paths {
        builder = builder.clang_arg(format!("-I{}", inc.display()));
    }

    builder = builder
        .clang_arg("-DMBEDTLS_SSL_RECORD_SIZE_LIMIT")
        .clang_arg("-DMBEDTLS_SSL_NULL_CIPHERSUITES")
        .clang_arg("-DMBEDTLS_ED25519_PSA_DRIVER");

    if let Ok(sysroot) = env::var("BINDGEN_SYSROOT") {
        builder = builder.clang_arg(format!("--sysroot={sysroot}"));
    }

    let bindings = builder
        .generate()
        .expect("bindgen failed to generate bindings");

    // Write to src/bindings.rs in the crate source tree so it can be committed.
    let out = manifest_dir.join("src").join("bindings.rs");
    bindings
        .write_to_file(&out)
        .expect("Failed to write src/bindings.rs");

    let generated = fs::read_to_string(&out).expect("Failed to read generated bindings");
    let content = format!("{GENERATED_FILE_HEADER}{}\n", generated.trim_end());
    fs::write(&out, content).expect("Failed to prepend SPDX header to generated bindings");

    eprintln!("Bindings written to {}", out.display());
}
