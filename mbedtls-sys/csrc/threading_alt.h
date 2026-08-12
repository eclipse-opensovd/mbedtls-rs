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

// MBEDTLS_THREADING_ALT platform types for Windows.
//
// Included by <mbedtls/threading.h> when MBEDTLS_THREADING_ALT is defined
// (the `multithread` cargo feature on Windows targets, where pthread is not
// available). Backed by Win32 slim reader/writer locks and condition
// variables. The function pointer implementations live in threading_win32.c
// and are registered at runtime via mbedtls_rs_threading_setup().

#ifndef THREADING_ALT_H
#define THREADING_ALT_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

typedef SRWLOCK mbedtls_platform_mutex_t;
typedef CONDITION_VARIABLE mbedtls_platform_condition_variable_t;

#ifdef __cplusplus
extern "C" {
#endif

/**
 * \brief  Register the Win32 threading implementation with mbedtls.
 *
 * Calls mbedtls_threading_set_alt() with SRWLOCK/CONDITION_VARIABLE based
 * implementations. Must be called once in the main thread before any other
 * Mbed TLS function.
 */
void mbedtls_rs_threading_setup(void);

#ifdef __cplusplus
}
#endif

#endif /* THREADING_ALT_H */
