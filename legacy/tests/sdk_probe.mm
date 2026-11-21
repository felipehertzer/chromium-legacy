// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include <cstdio>

// Subclassing requires class and metaclass symbols at link/load time;
// NSClassFromString alone would not exercise the SDK compatibility overlay.
@interface ChromiumLegacySDKProbe : NSObject
@end
@implementation ChromiumLegacySDKProbe
@end

int main() {
  @autoreleasepool {
    ChromiumLegacySDKProbe* object = [[ChromiumLegacySDKProbe alloc] init];
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 20, nullptr);
    bool success = object && font && CTFontGetSize(font) == 20;
    if (font) {
      CFRelease(font);
    }
    std::printf("SDK framework compatibility: %s\n", success ? "PASS" : "FAIL");
    return success ? 0 : 1;
  }
}
