// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_HTTP_HEADER_H_
#define LEGACY_APPLE_HTTP_HEADER_H_
#import <Foundation/Foundation.h>

namespace chromium_legacy {
inline bool EqualHTTPHeaderName(NSString* left, NSString* right) {
  if (!left || !right || left.length != right.length) {
    return false;
  }
  for (NSUInteger i = 0; i < left.length; ++i) {
    unichar a = [left characterAtIndex:i];
    unichar b = [right characterAtIndex:i];
    if (a > 127 || b > 127) {
      return false;
    }
    if (a >= 'A' && a <= 'Z')
      a += 'a' - 'A';
    if (b >= 'A' && b <= 'Z')
      b += 'a' - 'A';
    if (a != b)
      return false;
  }
  return true;
}
inline NSString* HTTPHeaderField(NSHTTPURLResponse* response, NSString* field) {
  if (!response || !field) {
    return nil;
  }
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.15, *)) {
    return [response valueForHTTPHeaderField:field];
  }
#endif
  NSDictionary* headers = response.allHeaderFields;
  NSString* value = nil;
  bool found = false;
  for (id key in headers) {
    if (![key isKindOfClass:NSString.class] ||
        !EqualHTTPHeaderName(key, field)) {
      continue;
    }
    // Ambiguous case variants must not relax CORS origin/header checks.
    if (found)
      return nil;
    found = true;
    id candidate = [headers objectForKey:key];
    if (![candidate isKindOfClass:NSString.class])
      return nil;
    value = candidate;
  }
  return value;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_HTTP_HEADER_H_
