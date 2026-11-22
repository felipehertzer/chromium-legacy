// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include "legacy/apple/weak_key_map.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, const char* message) {
  ++checks;
  if (!success) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", message);
  }
}
}  // namespace
int main() {
  @autoreleasepool {
    ChromiumLegacyWeakKeyMap* map = [[ChromiumLegacyWeakKeyMap alloc] init];
    NSObject* first = [[NSObject alloc] init];
    NSObject* second = [[NSObject alloc] init];
    Check([map objectForKey:first] == nil, "missing key");
    [map setObject:@1 forKey:first];
    [map setObject:@2 forKey:second];
    Check([[map objectForKey:first] isEqual:@1] &&
              [[map objectForKey:second] isEqual:@2],
          "independent keys");
    [map setObject:@3 forKey:first];
    Check([[map objectForKey:first] isEqual:@3], "replacement");
    [map removeObjectForKey:second];
    Check([map objectForKey:second] == nil &&
              [[map objectForKey:first] isEqual:@3],
          "removal preserves other key");
    __weak NSObject* weak_key = nil;
    __weak NSObject* weak_value = nil;
    @autoreleasepool {
      NSObject* key = [[NSObject alloc] init];
      NSObject* value = [[NSObject alloc] init];
      weak_key = key;
      weak_value = value;
      [map setObject:value forKey:key];
      Check([map objectForKey:key] == value, "value retained for live key");
    }
    Check(weak_key == nil, "map never retains its key");
    @autoreleasepool {
      (void)[map objectForKey:first];
    }
    Check(weak_value == nil, "expired key releases value when pruned");
    [map setObject:nil forKey:first];
    Check([map objectForKey:first] == nil, "nil value removes key");
    [map setObject:@4 forKey:nil];
    Check([map objectForKey:nil] == nil, "nil key is ignored");
    NSMutableString* equal_a = [NSMutableString stringWithString:@"same"];
    NSMutableString* equal_b = [NSMutableString stringWithString:@"same"];
    [map setObject:@7 forKey:equal_a];
    Check(equal_a != equal_b && [[map objectForKey:equal_b] isEqual:@7],
          "object equality agrees with NSMapTable");
  }
  std::printf("%d weak-key map checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
