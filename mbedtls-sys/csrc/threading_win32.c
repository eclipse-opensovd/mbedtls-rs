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

// MBEDTLS_THREADING_ALT implementation for Windows, based on Win32
// SRWLOCK (used exclusively, i.e. as a plain mutex) and CONDITION_VARIABLE.
//
// mbedtls only requires plain mutex semantics: always unlocked from the
// locking thread, never locked recursively. SRWLOCK in exclusive mode
// satisfies this and needs no destruction.

#include "threading_alt.h"

#include <mbedtls/threading.h>

static int win32_mutex_init(mbedtls_platform_mutex_t *mutex)
{
    InitializeSRWLock(mutex);
    return 0;
}

static void win32_mutex_destroy(mbedtls_platform_mutex_t *mutex)
{
    // SRWLOCKs need no destruction.
    (void) mutex;
}

static int win32_mutex_lock(mbedtls_platform_mutex_t *mutex)
{
    AcquireSRWLockExclusive(mutex);
    return 0;
}

static int win32_mutex_unlock(mbedtls_platform_mutex_t *mutex)
{
    ReleaseSRWLockExclusive(mutex);
    return 0;
}

static int win32_cond_init(mbedtls_platform_condition_variable_t *cond)
{
    InitializeConditionVariable(cond);
    return 0;
}

static void win32_cond_destroy(mbedtls_platform_condition_variable_t *cond)
{
    // CONDITION_VARIABLEs need no destruction.
    (void) cond;
}

static int win32_cond_signal(mbedtls_platform_condition_variable_t *cond)
{
    WakeConditionVariable(cond);
    return 0;
}

static int win32_cond_broadcast(mbedtls_platform_condition_variable_t *cond)
{
    WakeAllConditionVariable(cond);
    return 0;
}

static int win32_cond_wait(mbedtls_platform_condition_variable_t *cond,
                           mbedtls_platform_mutex_t *mutex)
{
    if (!SleepConditionVariableSRW(cond, mutex, INFINITE, 0)) {
        return MBEDTLS_ERR_THREADING_USAGE_ERROR;
    }
    return 0;
}

void mbedtls_rs_threading_setup(void)
{
    mbedtls_threading_set_alt(win32_mutex_init,
                              win32_mutex_destroy,
                              win32_mutex_lock,
                              win32_mutex_unlock,
                              win32_cond_init,
                              win32_cond_destroy,
                              win32_cond_signal,
                              win32_cond_broadcast,
                              win32_cond_wait);
}
