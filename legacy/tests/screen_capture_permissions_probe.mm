// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Exercise the actual production implementation. No image is captured and the
// permission-request function is deliberately never called by this probe.
#include <stdio.h>
#include <unistd.h>

#include "base/check.h"
#include "ui/base/cocoa/permissions_utils.mm"

namespace {
unsigned checks;
void Check(bool result, const char* description) {
  CHECK(result) << description;
  ++checks;
}
}  // namespace

int main() {
  @autoreleasepool {
    const pid_t current = getpid();
    NSString* owner_key = base::apple::CFToNSPtrCast(kCGWindowOwnerPID);
    NSString* name_key = base::apple::CFToNSPtrCast(kCGWindowName);
    NSString* layer_key = base::apple::CFToNSPtrCast(kCGWindowLayer);
    NSDictionary* foreign = @{
      owner_key : @(current + 1),
      name_key : @"fixture",
      layer_key : @(CGWindowLevelForKey(kCGNormalWindowLevelKey))
    };
    auto allowed = [&](NSArray* windows) {
      return ui::IsScreenCaptureAllowedForWindowList(windows, current);
    };
    Check(!allowed(nil), "missing window list fails closed");
    Check(!allowed(@[]), "empty window list fails closed");
    Check(allowed(@[ foreign ]), "foreign normal window with visible name");
    NSMutableDictionary* item = [foreign mutableCopy];
    [item setObject:@(current) forKey:owner_key];
    Check(!allowed(@[ item ]),
          "own named window does not imply capture permission");
    item = [foreign mutableCopy];
    [item removeObjectForKey:owner_key];
    Check(!allowed(@[ item ]), "unknown owner fails closed");
    item = [foreign mutableCopy];
    [item removeObjectForKey:name_key];
    Check(!allowed(@[ item ]), "hidden foreign title means no permission");
    item = [foreign mutableCopy];
    [item removeObjectForKey:layer_key];
    Check(!allowed(@[ item ]), "unknown layer fails closed");
    item = [foreign mutableCopy];
    [item setObject:@(CGWindowLevelForKey(kCGFloatingWindowLevelKey))
             forKey:layer_key];
    Check(!allowed(@[ item ]), "unrelated layer is not permission evidence");
    [item setObject:@(CGWindowLevelForKey(kCGDockWindowLevelKey))
             forKey:layer_key];
    Check(allowed(@[ item ]), "foreign dock window with visible name");
    [item setObject:@(current) forKey:owner_key];
    Check(!allowed(@[ item ]), "own dock window is not permission evidence");
    Check(allowed(@[ item, foreign ]), "valid foreign window after own window");
    // This is the real preflight API, on the actual OS. It must not crash on
    // Catalina, where CGPreflightScreenCaptureAccess is absent despite the SDK.
    bool native = ui::IsScreenCaptureAllowed();
    ++checks;
    printf("%u checks passed; native preflight returned %s; no prompt or "
           "capture\n",
           checks, native ? "true" : "false");
  }
  return 0;
}
