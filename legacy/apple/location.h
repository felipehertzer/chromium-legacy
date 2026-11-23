// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_LOCATION_H_
#define LEGACY_APPLE_LOCATION_H_
#import <CoreLocation/CoreLocation.h>
#include <TargetConditionals.h>

namespace chromium_legacy {
inline bool ExplicitLocationAuthorizationAvailable() {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.15, iOS 8.0, *))
    return true;
#endif
  return false;
}

inline bool IsLocationAuthorized(CLAuthorizationStatus status) {
#if TARGET_OS_OSX
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101200
  if (@available(macOS 10.12, *))
    return status == kCLAuthorizationStatusAuthorizedAlways;
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101200
  return status == kCLAuthorizationStatusAuthorized;
#else
  return false;
#endif
#else
  return status == kCLAuthorizationStatusAuthorizedAlways ||
         status == kCLAuthorizationStatusAuthorizedWhenInUse;
#endif
}

// Older Core Location retains its traditional altitude measurement; only use
// the ellipsoidal measurement when the native getter is actually available.
inline CLLocationDistance LocationAltitude(CLLocation* location,
                                           bool prefer_ellipsoidal) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 12.0, iOS 15.0, *)) {
    if (prefer_ellipsoidal)
      return location.ellipsoidalAltitude;
  }
#endif
  (void)prefer_ellipsoidal;
  return location.altitude;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_LOCATION_H_
