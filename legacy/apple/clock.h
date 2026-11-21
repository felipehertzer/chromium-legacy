// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_CLOCK_H_
#define LEGACY_APPLE_CLOCK_H_

#include <errno.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <sys/time.h>
#include <time.h>

namespace chromium_legacy {

inline bool MachTicksToNanos(uint64_t ticks,
                             uint32_t numerator,
                             uint32_t denominator,
                             uint64_t* result) {
  if (!result || !numerator || !denominator) {
    return false;
  }
  __uint128_t nanos = static_cast<__uint128_t>(ticks) * numerator / denominator;
  if (nanos > UINT64_MAX) {
    return false;
  }
  *result = static_cast<uint64_t>(nanos);
  return true;
}

inline int LegacyRealtime(timespec* result) {
  if (!result) {
    errno = EINVAL;
    return -1;
  }
  timeval now{};
  if (gettimeofday(&now, nullptr)) {
    return -1;
  }
  result->tv_sec = now.tv_sec;
  result->tv_nsec = now.tv_usec * 1000;
  return 0;
}

inline int LegacyMonotonic(timespec* result) {
  if (!result) {
    errno = EINVAL;
    return -1;
  }
  mach_timebase_info_data_t scale{};
  uint64_t nanos;
  if (mach_timebase_info(&scale) != KERN_SUCCESS ||
      !MachTicksToNanos(mach_absolute_time(), scale.numer, scale.denom,
                        &nanos)) {
    errno = EOVERFLOW;
    return -1;
  }
  // Like older libc++ implementations, this clock excludes system sleep.
  result->tv_sec = nanos / 1000000000;
  result->tv_nsec = nanos % 1000000000;
  return 0;
}

inline int Realtime(timespec* result) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.12, *)) {
    return clock_gettime(CLOCK_REALTIME, result);
  }
#endif
  return LegacyRealtime(result);
}

inline int Monotonic(timespec* result) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.12, *)) {
    return clock_gettime(CLOCK_MONOTONIC_RAW, result);
  }
#endif
  return LegacyMonotonic(result);
}

inline int ClockGettime(clockid_t clock, timespec* result) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.12, *)) {
    return clock_gettime(clock, result);
  }
#endif
  // Darwin clock IDs are an ABI. Referencing the annotated SDK constants
  // outside an availability guard would itself require macOS 10.12.
  switch (static_cast<unsigned>(clock)) {
    case 0:  // CLOCK_REALTIME
      return LegacyRealtime(result);
    case 4:  // CLOCK_MONOTONIC_RAW
    case 6:  // CLOCK_MONOTONIC
    case 8:  // CLOCK_UPTIME_RAW
      return LegacyMonotonic(result);
    default:
      errno = EINVAL;
      return -1;
  }
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_CLOCK_H_
