// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/mac/legacy_os_compat.h"

#include <stdio.h>

namespace {
int failures = 0;
int checks = 0;

void Check(NSString* path, NSString* expected, const char* name) {
  NSString* actual = base::mac::ReadLegacyProductVersion(path);
  ++checks;
  if (!((!actual && !expected) || [actual isEqualToString:expected])) {
    fprintf(stderr, "FAIL: %s\n", name);
    ++failures;
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    NSString* directory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSProcessInfo processInfo]
                                           globallyUniqueString]];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil]) {
      return 2;
    }
    NSString* path =
        [directory stringByAppendingPathComponent:@"SystemVersion.plist"];
    Check(nil, nil, "nil path");
    Check(path, nil, "missing file");
    [@"invalid plist" writeToFile:path
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:nil];
    Check(path, nil, "malformed plist");
    NSArray* values = @[
      @{@"ProductVersion" : @"10.7.5"}, @{@"ProductVersion" : @"10.15.7"},
      @{@"ProductVersion" : @"27.3"},
      @{@"ProductVersion" : @42}, @{@"ProductVersion" : @""},
      @{@"OtherKey" : @"10.7.5"}, @[ @"10.7.5" ]
    ];
    for (NSUInteger i = 0; i < [values count]; ++i) {
      id value = [values objectAtIndex:i];
      NSString* expected = i < 3 ? [value objectForKey:@"ProductVersion"] : nil;
      for (NSUInteger format = 0; format < 2; ++format) {
        NSData* data = [NSPropertyListSerialization
            dataWithPropertyList:value
                          format:format ? NSPropertyListBinaryFormat_v1_0
                                        : NSPropertyListXMLFormat_v1_0
                         options:0
                           error:nil];
        if (!data || ![data writeToFile:path atomically:YES]) {
          return 2;
        }
        Check(path, expected, format ? "binary plist" : "XML plist");
      }
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    printf("%d OS version fallback checks, %d failures\n", checks, failures);
  }
  return failures ? 1 : 0;
}
