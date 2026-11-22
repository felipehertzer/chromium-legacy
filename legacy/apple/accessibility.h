// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_ACCESSIBILITY_H_
#define LEGACY_APPLE_ACCESSIBILITY_H_

#import <AppKit/AppKit.h>

namespace chromium_legacy {
// Lion accepts announcement text. The public priority key/enum arrived in 10.9.
// Construct data only; the caller still owns posting the native notification.
inline NSDictionary* AccessibilityAnnouncementInfo(NSString* text,
                                                   bool assertive) {
  NSMutableDictionary* info =
      [NSMutableDictionary dictionaryWithObject:text
                                         forKey:NSAccessibilityAnnouncementKey];
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.9, *)) {
    NSAccessibilityPriorityLevel priority =
        assertive ? NSAccessibilityPriorityHigh : NSAccessibilityPriorityMedium;
    [info setObject:@(priority) forKey:NSAccessibilityPriorityKey];
  }
#endif
  (void)assertive;
  return [info copy];
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_ACCESSIBILITY_H_
