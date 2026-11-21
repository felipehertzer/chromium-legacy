// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_ATOMIC_WAIT_H_
#define LEGACY_APPLE_ATOMIC_WAIT_H_

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>

#include <array>

namespace chromium_legacy {
namespace internal {
struct AtomicWaitBucket {
  pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
  pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
};
[[clang::require_constant_initialization]] inline std::array<AtomicWaitBucket,
                                                             256>
    atomic_wait_buckets;

inline AtomicWaitBucket& WaitBucket(const void* address) {
  return atomic_wait_buckets[(reinterpret_cast<uintptr_t>(address) >> 3) & 255];
}

template <size_t Size>
inline bool AtomicEquals(const void* address, uint64_t expected) {
  // LLVM atomics supply aligned 4/8-byte storage. may_alias permits inspecting
  // the representation of non-integer atomic types without type-punning UB.
  static_assert(Size == 4 || Size == 8);
  typedef uint32_t Alias32 __attribute__((may_alias));
  typedef uint64_t Alias64 __attribute__((may_alias));
  if constexpr (Size == 4) {
    return __atomic_load_n(static_cast<const Alias32*>(address),
                           __ATOMIC_ACQUIRE) == static_cast<uint32_t>(expected);
  } else {
    return __atomic_load_n(static_cast<const Alias64*>(address),
                           __ATOMIC_ACQUIRE) == expected;
  }
}
}  // namespace internal

template <size_t Size>
inline int LegacyAtomicWait(const void* address,
                            uint64_t expected,
                            uint64_t timeout_ns,
                            bool timed) {
  auto& bucket = internal::WaitBucket(address);
  int result = pthread_mutex_lock(&bucket.mutex);
  if (result) {
    return result;
  }
  if (internal::AtomicEquals<Size>(address, expected)) {
    if (timed) {
      timespec timeout{};
      timeout.tv_sec = timeout_ns / 1000000000;
      timeout.tv_nsec = timeout_ns % 1000000000;
      result = pthread_cond_timedwait_relative_np(&bucket.condition,
                                                  &bucket.mutex, &timeout);
    } else {
      result = pthread_cond_wait(&bucket.condition, &bucket.mutex);
    }
  }
  int unlocked = pthread_mutex_unlock(&bucket.mutex);
  return result ? result : unlocked;
}

inline int LegacyAtomicNotify(const void* address) {
  auto& bucket = internal::WaitBucket(address);
  int result = pthread_mutex_lock(&bucket.mutex);
  if (result) {
    return result;
  }
  // Addresses share buckets. Broadcasting prevents notify_one from waking
  // only an unrelated address; atomic waiters recheck their own predicates.
  result = pthread_cond_broadcast(&bucket.condition);
  int unlocked = pthread_mutex_unlock(&bucket.mutex);
  return result ? result : unlocked;
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_ATOMIC_WAIT_H_
