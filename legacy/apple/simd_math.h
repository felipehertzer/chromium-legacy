// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LEGACY_APPLE_SIMD_MATH_H_
#define LEGACY_APPLE_SIMD_MATH_H_

#include <AvailabilityMacros.h>
#include <math.h>

namespace chromium_legacy {

// Reduce in half-integer units before multiplying by pi. This retains exact
// integer/half-integer results, including large inputs and signed sine zeros.
inline void SinCosPiFallback(double x, double* sine, double* cosine) {
  if (!__builtin_isfinite(x)) {
    *sine = *cosine = sin(x);
    return;
  }
  int quotient = 0;
  const double remainder = remquo(x, 0.5, &quotient);
  const unsigned quadrant = static_cast<unsigned>(quotient) & 3;
  if (remainder == 0) {
    *sine = (quadrant & 1) ? (quadrant == 1 ? 1 : -1) : copysign(0., x);
    *cosine = (quadrant & 1) ? 0 : (quadrant == 0 ? 1 : -1);
    return;
  }
  const double angle = remainder * 0x1.921fb54442d18p+1;
  const double s = sin(angle);
  const double c = cos(angle);
  switch (quadrant) {
    case 0:
      *sine = s;
      *cosine = c;
      break;
    case 1:
      *sine = c;
      *cosine = -s;
      break;
    case 2:
      *sine = -s;
      *cosine = -c;
      break;
    case 3:
      *sine = -c;
      *cosine = s;
      break;
  }
}

}  // namespace chromium_legacy

// math.h hides these header inlines for pre-10.9 targets, while the current
// simd headers still parse calls to them. Supply real calculations, retaining
// the native functions on systems that have them; do not add library exports.
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && \
    __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
inline void __sincospi(double x, double* sine, double* cosine) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.9, *)) {
    *sine = __sinpi(x);
    *cosine = __cospi(x);
    return;
  }
#endif
  chromium_legacy::SinCosPiFallback(x, sine, cosine);
}

inline void __sincospif(float x, float* sine, float* cosine) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.9, *)) {
    *sine = __sinpif(x);
    *cosine = __cospif(x);
    return;
  }
#endif
  double s, c;
  chromium_legacy::SinCosPiFallback(x, &s, &c);
  *sine = s;
  *cosine = c;
}
#endif

// The declarations above must precede the SDK SIMD function definitions.
#include <simd/simd.h>

#endif  // LEGACY_APPLE_SIMD_MATH_H_
