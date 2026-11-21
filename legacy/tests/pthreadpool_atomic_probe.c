/* Copyright 2026 The Chromium Legacy Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file. */
#include <stdio.h>

#include "src/threadpool-atomics.h"

static pthreadpool_atomic_size_t count;
static pthreadpool_atomic_uint32_t ready;
static pthreadpool_atomic_int32_t signed_value;
static pthreadpool_atomic_void_p pointer_value;
static int payload;
static int checks, failures;
static void Check(int success, const char* name) {
  ++checks;
  if (!success) {
    ++failures;
    fprintf(stderr, "FAIL: %s\n", name);
  }
}
static void* Add(void* unused) {
  (void)unused;
  for (size_t i = 0; i < 8192; ++i) {
    pthreadpool_fetch_add_relaxed_size_t(&count, 1);
  }
  return NULL;
}
static void* Publish(void* unused) {
  (void)unused;
  payload = 37;
  pthreadpool_store_release_uint32_t(&ready, 1);
  return NULL;
}
int main(void) {
  Check(_Alignof(pthreadpool_atomic_size_t) >= 64 &&
            _Alignof(pthreadpool_atomic_uint32_t) >= 64 &&
            _Alignof(pthreadpool_atomic_int32_t) >= 64 &&
            _Alignof(pthreadpool_atomic_void_p) >= 64,
        "cache-line alignment is retained");
  pthread_t workers[4];
  size_t created = 0;
  int joined = 1;
  for (; created < 4; ++created) {
    if (pthread_create(&workers[created], NULL, Add, NULL)) {
      break;
    }
  }
  Check(created == 4, "create contending threads");
  for (size_t i = 0; i < created; ++i) {
    joined &= pthread_join(workers[i], NULL) == 0;
  }
  Check(joined, "join contending threads");
  Check(pthreadpool_load_acquire_size_t(&count) == 4 * 8192,
        "contended increments preserve every update");
  pthread_t publisher;
  int published = pthread_create(&publisher, NULL, Publish, NULL) == 0;
  Check(published, "create producer");
  int observed = 0;
  if (published) {
    for (size_t i = 0; i < 1000000; ++i) {
      if (pthreadpool_load_acquire_uint32_t(&ready)) {
        observed = 1;
        break;
      }
      sched_yield();
    }
    Check(observed && payload == 37, "release/acquire publishes ordinary data");
    pthread_join(publisher, NULL);
  } else {
    Check(0, "release/acquire publishes ordinary data");
  }
  pthreadpool_store_release_int32_t(&signed_value, 42);
  int_least32_t expected = 42;
  Check(pthreadpool_compare_exchange_acquire_release_int32_t(&signed_value,
                                                             &expected, 43),
        "successful compare/exchange");
  expected = 1;
  Check(!pthreadpool_compare_exchange_acquire_release_int32_t(&signed_value,
                                                              &expected, 44) &&
            expected == 43,
        "failed compare/exchange reports the observed value");
  pthreadpool_store_relaxed_void_p(&pointer_value, &payload);
  Check(pthreadpool_load_relaxed_void_p(&pointer_value) == &payload,
        "pointer atomics preserve the address");
  pthreadpool_store_release_size_t(&count, 1);
  Check(pthreadpool_try_decrement_relaxed_size_t(&count) &&
            pthreadpool_load_acquire_size_t(&count) == 0,
        "conditional decrement");
  Check(!pthreadpool_try_decrement_relaxed_size_t(&count) &&
            pthreadpool_load_acquire_size_t(&count) == 0,
        "zero does not underflow");
  Check(pthreadpool_exchange_release_int32_t(&signed_value, -5) == 43 &&
            pthreadpool_load_relaxed_int32_t(&signed_value) == -5,
        "signed exchange retains its value");
  printf("%d pthreadpool atomic checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
