// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>
#include <stdio.h>

#include "ui/display/mac/screen_utils_mac.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, const char* label) {
  ++checks;
  if (!value) {
    ++failures;
    fprintf(stderr, "FAILED: %s\n", label);
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSScreen* screen = NSScreen.screens.firstObject;
    Check(screen != nil, "a display is available");
    CGDirectDisplayID identifier = [[screen.deviceDescription
        objectForKey:@"NSScreenNumber"] unsignedIntValue];
    Check(display::GetNSScreenFromDisplayID(identifier) == screen,
          "display identifier maps to the original screen");
    Check(display::GetCGRefreshInterval(identifier).is_positive(),
          "CoreGraphics mode gives a positive refresh interval");
    Check(display::GetNSScreenRefreshInterval(identifier).is_positive(),
          "screen refresh interval is positive");
    base::TimeDelta minimum, maximum, granularity;
    display::GetNSScreenRefreshIntervalRange(identifier, minimum, maximum,
                                             granularity);
    Check(minimum.is_positive() && maximum.is_positive(),
          "refresh range is positive");
    Check(minimum <= maximum && granularity >= base::TimeDelta(),
          "refresh interval range is ordered");
    Check(display::GetNSScreenFromDisplayID(UINT32_MAX) == nil,
          "unknown display is rejected");
    display::GetNSScreenRefreshIntervalRange(UINT32_MAX, minimum, maximum,
                                             granularity);
    Check(minimum == base::Hertz(60) && maximum == minimum &&
              granularity == minimum &&
              display::GetNSScreenRefreshInterval(UINT32_MAX) == minimum,
          "unknown display uses the existing 60 Hz fallback");
  }
  printf("%d display checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
