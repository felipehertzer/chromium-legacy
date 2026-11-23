// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <dlfcn.h>
#include <cstdio>

#import "legacy/apple/user_activity.h"

int main() {
  int checks = 0;
  int failures = 0;
  auto check = [&](bool ok, const char* name) {
    ++checks;
    if (!ok) {
      ++failures;
      std::fprintf(stderr, "FAIL: %s\n", name);
    }
  };
  @autoreleasepool {
    NSString* type = chromium_legacy::BrowsingWebActivityType();
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    check(type == nil, "unsupported activity type remains absent");
#else
    auto* native = static_cast<CFStringRef*>(
        dlsym(RTLD_DEFAULT, "NSUserActivityTypeBrowsingWeb"));
    check((type != nil) == (native != nullptr),
          "optional data binding follows the actual Foundation export");
    check(
        !native || [type isEqual:(__bridge NSString*)*native],
        "compatibility value is the OS value rather than a fabricated string");
#endif
    check(!type || [type isKindOfClass:NSString.class],
          "an available type remains a real NSString");
    check(!type || type.length > 0, "available type is not empty");
  }
  std::printf("%d activity-type checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
