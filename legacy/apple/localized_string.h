// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_LOCALIZED_STRING_H_
#define LEGACY_APPLE_LOCALIZED_STRING_H_

#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

namespace chromium_legacy {
enum class StringCase { kUpper, kLower, kTitle };

// CoreFoundation's locale-aware casing predates NSString's 10.8/10.11 helpers.
// Work on an owned mutable copy, then return an immutable result to the caller.
inline NSString* LocalizedCaseString(
    NSString* text,
    StringCase operation,
    NSLocale* locale = NSLocale.currentLocale) {
  if (!text) {
    return nil;
  }
  NSMutableString* result = [text mutableCopy];
  CFMutableStringRef string = (__bridge CFMutableStringRef)result;
  CFLocaleRef cf_locale = (__bridge CFLocaleRef)locale;
  switch (operation) {
    case StringCase::kUpper:
      CFStringUppercase(string, cf_locale);
      break;
    case StringCase::kLower:
      CFStringLowercase(string, cf_locale);
      break;
    case StringCase::kTitle:
      CFStringCapitalize(string, cf_locale);
      break;
  }
  return [result copy];
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_LOCALIZED_STRING_H_
