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

def mbedtls_rs_library(name, tokio, tracing, aliases = {}, visibility = None):
    """Instantiates mbedtls-rs with the consumer's Rust dependency universe."""
    rust_library(
        name = name,
        aliases = aliases,
        srcs = [Label("//mbedtls-rs:srcs")],
        crate_name = "mbedtls_rs",
        crate_root = Label("//mbedtls-rs:src/lib.rs"),
        edition = "2024",
        rustc_flags = ["--cfg=feature=\"tokio\""],
        visibility = visibility,
        deps = [
            Label("//mbedtls-sys:mbedtls_sys"),
            tokio,
            tracing,
        ] + crate_deps(
            ["ed25519-dalek"],
            package_name = "mbedtls-rs",
        ),
    )
