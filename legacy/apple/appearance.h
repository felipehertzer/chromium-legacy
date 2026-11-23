// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_APPEARANCE_H_
#define LEGACY_APPLE_APPEARANCE_H_

#import <AppKit/AppKit.h>

namespace chromium_legacy {
inline void WithAppearance(bool dark, void (^action)()) {
  if (!action)
    return;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
  if (@available(macOS 10.9, *)) {
    NSAppearanceName name = NSAppearanceNameAqua;
    if (@available(macOS 10.14, *)) {
      if (dark)
        name = NSAppearanceNameDarkAqua;
    }
    NSAppearance* appearance = [NSAppearance appearanceNamed:name];
    if (!appearance) {
      action();
      return;
    }
    if (@available(macOS 11.0, *)) {
      [appearance performAsCurrentDrawingAppearance:action];
      return;
    }
    NSAppearance* previous = NSAppearance.currentAppearance;
    @try {
      NSAppearance.currentAppearance = appearance;
      action();
    } @finally {
      NSAppearance.currentAppearance = previous;
    }
    return;
  }
#endif
  // Before appearance objects exist, both slots use the native Aqua palette.
  (void)dark;
  action();
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_APPEARANCE_H_
