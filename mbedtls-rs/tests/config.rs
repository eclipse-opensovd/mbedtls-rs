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

use mbedtls_rs::{
    ssl::SslConfigBuilder,
    x509::{PrivateKey, X509Certificate},
};

fn pem_with_nul(raw: &str) -> Vec<u8> {
    let mut v = raw.as_bytes().to_vec();
    v.push(0);
    v
}

fn load_pair(cert: &str, key: &str) -> (X509Certificate, PrivateKey) {
    init_psa();
    let cert = X509Certificate::from_pem(&pem_with_nul(cert)).expect("cert parse");
    let key = PrivateKey::from_pem(&pem_with_nul(key), &[]).expect("key parse");
    (cert, key)
}

fn init_psa() {
    let ret = unsafe { mbedtls_rs::ffi::psa_crypto_init() };
    assert_eq!(ret, 0, "psa_crypto_init failed: {ret}");
}

/// Regression test: registering multiple cert/key pairs must keep *all* of
/// them alive inside the built config (mbedtls appends them to an internal
/// linked list). Previously only the last pair was retained, leaving dangling
/// pointers to the earlier ones.
#[test]
fn own_cert_multiple_pairs_kept_alive() {
    let (cert1, key1) = load_pair(
        include_str!("certs/cert1.pem"),
        include_str!("certs/key1.pem"),
    );
    let (cert2, key2) = load_pair(
        include_str!("certs/cert2.pem"),
        include_str!("certs/key2.pem"),
    );

    let config = SslConfigBuilder::new_server()
        .expect("server config")
        .own_cert(cert1, key1)
        .expect("first own_cert")
        .own_cert(cert2, key2)
        .expect("second own_cert")
        .build();

    // Config (and thus the mbedtls key_cert list) must stay usable here.
    drop(config);
}

/// PEM parsing requires the trailing NUL; appending without it must fail
/// instead of handing a non-terminated buffer to mbedtls.
#[test]
fn append_pem_requires_trailing_nul() {
    init_psa();
    let mut chain =
        X509Certificate::from_pem(&pem_with_nul(include_str!("certs/cert1.pem"))).expect("cert");
    let no_nul = include_str!("certs/cert2.pem").as_bytes();
    assert!(chain.append_pem(no_nul).is_err());
    assert!(
        chain
            .append_pem(&pem_with_nul(include_str!("certs/cert2.pem")))
            .is_ok()
    );
}
