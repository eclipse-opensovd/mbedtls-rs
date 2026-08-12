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

"""Consumer-instantiated mbedtls-rs targets."""

load("@mbedtls_crates//:defs.bzl", "crate_deps")
load("@rules_rust//rust:defs.bzl", "rust_library")

def mbedtls_rs_library(name, tokio = None, tracing = None, multithread = True, aliases = {}, visibility = None):
    """Instantiates mbedtls-rs with the consumer's Rust dependency universe.

    Args:
        name: target name.
        tokio: label of the consumer's tokio crate, or None to build without
            the `tokio` feature (disables the async_stream module).
        tracing: label of the consumer's tracing crate.
        multithread: whether to enable the `multithread` feature.
        aliases: forwarded to rust_library.
        visibility: forwarded to rust_library.
    """
    rustc_flags = []
    deps = [Label("//mbedtls-sys:mbedtls_sys")]
    if tokio:
        rustc_flags.append("--cfg=feature=\"tokio\"")
        deps.append(tokio)
    if tracing:
        deps.append(tracing)
    if multithread:
        rustc_flags.append("--cfg=feature=\"multithread\"")
    rust_library(
        name = name,
        aliases = aliases,
        srcs = [Label("//mbedtls-rs:srcs")],
        crate_name = "mbedtls_rs",
        crate_root = Label("//mbedtls-rs:src/lib.rs"),
        edition = "2024",
        rustc_flags = rustc_flags,
        visibility = visibility,
        deps = deps + crate_deps(
            ["ed25519-dalek"],
            package_name = "mbedtls-rs",
        ),
    )
