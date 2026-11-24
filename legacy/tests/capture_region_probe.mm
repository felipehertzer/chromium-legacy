// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#include "legacy/apple/capture_region.h"

extern "C" {
int CGSMainConnectionID(void);
CGError CGSSetWindowCaptureExcludeShape(int connection,
                                        unsigned int window,
                                        CFTypeRef region);
}

namespace {
int checks = 0;
void Check(bool condition, const char* message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
  ++checks;
}
}  // namespace

int main() {
  @autoreleasepool {
    chromium_legacy::ScopedCaptureRegion region;
    Check(region.get() == nullptr, "initial region is empty");
    Check(region.Create(CGRectMake(0, 0, 64, 48)), "create rectangular region");
    CFTypeID type = CFGetTypeID(region.get());
    Check(type != 0, "region is a real CoreFoundation runtime object");
    CFTypeRef retained = CFRetain(region.get());
    region.Reset();
    Check(region.get() == nullptr, "reset releases owned region");
    Check(CFGetTypeID(retained) == type, "independent retain survives reset");
    CFRelease(retained);
    Check(region.Create(CGRectZero), "construct empty region singleton");
    region.Reset();
    region.Reset();
    Check(region.get() == nullptr, "empty singleton release and repeat reset");
    for (int i = 0; i < 128; ++i) {
      Check(region.Create(CGRectMake(i, i, 32, 24)), "replace previous region");
    }

    [NSApplication sharedApplication];
    NSWindow* window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 64, 48)
                                    styleMask:NSWindowStyleMaskBorderless
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    Check(window != nil && window.windowNumber > 0, "create own hidden window");
    Check(!window.visible, "test window remains hidden");
    Check(region.Create(CGRectMake(0, 0, 64, 48)), "create exclusion shape");
    Check(CGSSetWindowCaptureExcludeShape(CGSMainConnectionID(),
                                          window.windowNumber,
                                          region.get()) == kCGErrorSuccess,
          "apply real capture exclusion to own hidden window");
    Check(CGSSetWindowCaptureExcludeShape(CGSMainConnectionID(),
                                          window.windowNumber,
                                          nullptr) == kCGErrorSuccess,
          "remove exclusion from own test window");
    window.releasedWhenClosed = NO;
    [window close];
    printf("capture-region: %d checks passed\n", checks);
  }
}
