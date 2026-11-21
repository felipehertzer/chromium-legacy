// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <stdio.h>
#include <time.h>

#include "tensorflow/lite/profiling/time.h"
#include "xla/tsl/platform/env_time.h"

int main() {
  int failures = 0;
  const uint64_t before = tflite::profiling::time::NowMicros();
  tflite::profiling::time::SleepForMicros(20000);
  const uint64_t after = tflite::profiling::time::NowMicros();
  if (!before || after < before || after - before < 10000) {
    fprintf(stderr, "FAIL: profiling clock and microsecond sleep\n");
    ++failures;
  }
  const uint64_t nanos = tsl::EnvTime::NowNanos();
  const uint64_t micros = tsl::EnvTime::NowMicros();
  const uint64_t seconds = static_cast<uint64_t>(time(nullptr));
  if (nanos / 1000000000 + 2 < seconds || nanos / 1000000000 > seconds + 2) {
    fprintf(stderr, "FAIL: nanosecond wall clock uses the Unix epoch\n");
    ++failures;
  }
  if (micros / 1000000 + 2 < seconds || micros / 1000000 > seconds + 2) {
    fprintf(stderr,
            "FAIL: derived microsecond wall clock uses the Unix epoch\n");
    ++failures;
  }
  printf("3 TensorFlow Lite/XLA clock checks, %d failures\n", failures);
  return failures ? 1 : 0;
}
