// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_USER_ACTIVITY_H_
#define LEGACY_APPLE_USER_ACTIVITY_H_

#import <Foundation/Foundation.h>

#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && \
    __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 101000
// The SDK does not annotate this global. Keep its actual Foundation symbol
// optional on deployments predating NSUserActivity; do not invent its value.
extern "C" NSString* const ChromiumLegacyBrowsingWebActivityType __asm(
    "_NSUserActivityTypeBrowsingWeb") __attribute__((weak_import));
#endif

namespace chromium_legacy {
inline NSString* BrowsingWebActivityType() {
#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && \
    __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 101000
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (&ChromiumLegacyBrowsingWebActivityType) {
    return ChromiumLegacyBrowsingWebActivityType;
  }
#endif
  return nil;
#else
  return NSUserActivityTypeBrowsingWeb;
#endif
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_USER_ACTIVITY_H_
