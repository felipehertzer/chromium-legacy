// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/mac/legacy_os_compat.h"

namespace base::mac {

NSString* ReadLegacyProductVersion(NSString* plist_path) {
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

}  // namespace base::mac
