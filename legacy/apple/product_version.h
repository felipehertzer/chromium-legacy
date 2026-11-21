// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_PRODUCT_VERSION_H_
#define LEGACY_APPLE_PRODUCT_VERSION_H_
#include <Foundation/Foundation.h>
#include <stdint.h>

namespace chromium_legacy {
inline NSString* ReadLegacyProductVersion(NSString* plist_path) {
  if (!plist_path) {
    return nil;
  }
  NSData* data = [NSData dataWithContentsOfFile:plist_path options:0 error:nil];
  if (!data) {
    return nil;
  }
  id plist =
      [NSPropertyListSerialization propertyListWithData:data
                                                options:NSPropertyListImmutable
                                                 format:nullptr
                                                  error:nil];
  if (![plist isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  // Object subscripting requires 10.8; use the original dictionary selector.
  id version = [(NSDictionary*)plist objectForKey:@"ProductVersion"];
  if (![version isKindOfClass:[NSString class]] ||
      ![(NSString*)version length]) {
    return nil;
  }
  return (NSString*)version;
}

inline NSOperatingSystemVersion LegacySystemVersion(
    NSString* path = @"/System/Library/CoreServices/SystemVersion.plist") {
  @autoreleasepool {
    NSOperatingSystemVersion result{};
    NSString* text = ReadLegacyProductVersion(path);
    NSArray<NSString*>* parts = [text componentsSeparatedByString:@"."];
    if (parts.count < 2 || parts.count > 3) {
      return result;
    }
    for (NSUInteger index = 0; index < parts.count; ++index) {
      NSString* part = [parts objectAtIndex:index];
      if (!part.length) {
        return {};
      }
      NSInteger value = 0;
      for (NSUInteger character = 0; character < part.length; ++character) {
        unichar digit = [part characterAtIndex:character];
        if (digit < '0' || digit > '9') {
          return {};
        }
        digit -= '0';
        if (value > (INT32_MAX - digit) / 10) {
          return {};
        }
        value = value * 10 + digit;
      }
      if (index == 0) {
        result.majorVersion = value;
      } else if (index == 1) {
        result.minorVersion = value;
      } else {
        result.patchVersion = value;
      }
    }
    return result;
  }
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_PRODUCT_VERSION_H_
