// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_WINDOW_H_
#define LEGACY_APPLE_WINDOW_H_

#import <AppKit/AppKit.h>

namespace chromium_legacy {
inline NSUInteger ModalWindowStyleMask() {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.10, *))
    return NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView;
#endif
  return NSWindowStyleMaskTitled;
}

inline NSArray<NSWindow*>* ChildSheets(NSWindow* window) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.9, *))
    return window.sheets;
#endif
  NSWindow* sheet = window.attachedSheet;
  return sheet ? @[ sheet ] : @[];
}

inline bool OverrideWindowAccessibilityLabel(NSObject* window,
                                             NSString* label) {
  if (!window)
    return false;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.10, *)) {
    [(id<NSAccessibility>)window setAccessibilityLabel:label];
    return true;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000 || \
    defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  // AppKit applies overrides outside its direct attribute getters. See:
  // https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilitysetoverridevalue(_:forattribute:)
  return [window
      accessibilitySetOverrideValue:label
                       forAttribute:NSAccessibilityDescriptionAttribute];
#endif
  return false;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_WINDOW_H_
