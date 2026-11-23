// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include "legacy/apple/simd_math.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    ++failures;
    fprintf(stderr, "FAIL: %s\n", message);
  }
}
void Compare(double x) {
  double s, c;
  chromium_legacy::SinCosPiFallback(x, &s, &c);
  if (!__builtin_isfinite(x)) {
    Check(__builtin_isnan(s) && __builtin_isnan(c),
          "nonfinite edge yields NaNs");
    return;
  }
  Check(fabs(s * s + c * c - 1) <= 4 * DBL_EPSILON,
        "fallback retains the unit circle");
  if (__builtin_available(macOS 10.9, *)) {
    const double native_s = __sinpi(x);
    const double native_c = __cospi(x);
    Check(fabs(s - native_s) <= 2 * DBL_EPSILON,
          "fallback sine agrees with native range reduction");
    Check(fabs(c - native_c) <= 2 * DBL_EPSILON,
          "fallback cosine agrees with native range reduction");
    if (native_s == 0)
      Check(s == 0 && __builtin_signbit(s) == __builtin_signbit(native_s),
            "integer sine retains its signed zero");
    if (native_c == 0)
      Check(c == 0 && !__builtin_signbit(c),
            "half-integer cosine is positive zero");
  }
}
}  // namespace

int main() {
  const double values[] = {0.,       -0.,     0.5,      -0.5,      1.,
                           -1.,      1.5,     -1.5,     2.,        -2.,
                           3.,       -3.,     0x1p52,   -0x1p52,   DBL_MAX,
                           -DBL_MAX, DBL_MIN, -DBL_MIN, 0x1p-1074, -0x1p-1074};
  for (double x : values) {
    Compare(x);
    Compare(nextafter(x, INFINITY));
    Compare(nextafter(x, -INFINITY));
  }
  uint64_t state = 1;
  for (int i = 0; i < 512; ++i) {
    state = state * UINT64_C(6364136223846793005) + 1;
    const double x = ldexp(static_cast<double>(static_cast<int64_t>(state)),
                           -64 + (i % 100) - 50);
    Compare(x);
  }
  const double nonfinite[] = {NAN, INFINITY, -INFINITY};
  for (double x : nonfinite) {
    double s, c;
    chromium_legacy::SinCosPiFallback(x, &s, &c);
    Check(__builtin_isnan(s) && __builtin_isnan(c),
          "nonfinite input yields NaNs");
  }
  double sdk_s, sdk_c;
  simd::sincospi(0.5, &sdk_s, &sdk_c);
  Check(sdk_s == 1 && sdk_c == 0,
        "SDK double scalar overload uses the restored math inlines");
  float sdk_fs, sdk_fc;
  simd::sincospi(-0.5f, &sdk_fs, &sdk_fc);
  Check(sdk_fs == -1 && sdk_fc == 0,
        "SDK float scalar overload uses the restored math inlines");
  double scalar_s, scalar_c;
  __sincospi(-1., &scalar_s, &scalar_c);
  Check(scalar_s == 0 && __builtin_signbit(scalar_s) && scalar_c == -1,
        "restored double scalar inline retains exact signed results");
  float scalar_fs, scalar_fc;
  __sincospif(-0.5f, &scalar_fs, &scalar_fc);
  Check(scalar_fs == -1 && scalar_fc == 0,
        "restored float scalar inline retains exact half-integer results");
  printf("%d SIMD math checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
