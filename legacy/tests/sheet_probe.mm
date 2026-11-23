// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>

#include "legacy/apple/sheet.h"
#include "legacy/apple/window.h"

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
void DrainUntil(bool (^done)()) {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3];
  while (!done() && deadline.timeIntervalSinceNow > 0) {
    @autoreleasepool {
      [[NSRunLoop currentRunLoop]
             runMode:NSDefaultRunLoopMode
          beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
  }
}
NSWindow* Window() {
  NSWindow* window =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 320, 160)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  window.releasedWhenClosed = NO;
  window.animationBehavior = NSWindowAnimationBehaviorNone;
  return window;
}
}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    [NSApp finishLaunching];
    NSWindow* parent = Window();
    NSWindow* sheet = Window();
    const NSUInteger modal_style = chromium_legacy::ModalWindowStyleMask();
    Check((modal_style & NSWindowStyleMaskTitled) != 0,
          "modal windows retain their titled sheet behavior");
    bool full_size = false;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (@available(macOS 10.10, *))
      full_size = true;
#endif
    if (@available(macOS 10.10, *))
      Check(
          bool(modal_style & NSWindowStyleMaskFullSizeContentView) == full_size,
          "full-size content mask follows the actual native capability");
    Check(chromium_legacy::ChildSheets(parent).count == 0,
          "unattached parent has no child sheets");
    Check(chromium_legacy::ChildSheets(nil).count == 0,
          "absent parent has no child sheets");
    Check(chromium_legacy::OverrideWindowAccessibilityLabel(parent,
                                                            @"Legacy title"),
          "native window accepts the explicit accessibility label");
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (@available(macOS 10.10, *))
      Check([parent.accessibilityLabel isEqual:@"Legacy title"],
            "formal native label accessor retains the supplied text");
#endif
    [parent orderBack:nil];
    Check(chromium_legacy::SheetParent(sheet) == nil,
          "unattached sheet has no parent");
    __block int callbacks = 0;
    __block NSInteger response = 0;
    __weak NSObject* captured = nil;
    @autoreleasepool {
      NSObject* token = [[NSObject alloc] init];
      captured = token;
      chromium_legacy::BeginSheet(parent, sheet, ^(NSModalResponse code) {
        (void)[token class];
        ++callbacks;
        response = code;
        [sheet orderOut:nil];
      });
    }
    Check(captured != nil, "completion capture remains alive while modal");
    Check(parent.attachedSheet == sheet, "native sheet attaches");
    Check([chromium_legacy::ChildSheets(parent) isEqual:@[ sheet ]],
          "attached sheet is enumerated as exactly one child");
    Check(chromium_legacy::SheetParent(sheet) == parent,
          "native sheet parent is resolved");
    Check(callbacks == 0, "completion waits for the modal session to end");
    sheet.delegate = nil;
    chromium_legacy::EndSheet(parent, sheet, 37);
    DrainUntil(^bool {
      return callbacks != 0;
    });
    Check(callbacks == 1 && response == 37,
          "completion runs once with the exact return code");
    DrainUntil(^bool {
      return captured == nil;
    });
    Check(captured == nil, "completion releases its captured objects");
    Check(chromium_legacy::SheetParent(sheet) == nil,
          "ended sheet has no parent");
    Check(chromium_legacy::ChildSheets(parent).count == 0,
          "ended sheet is removed from child enumeration");
    chromium_legacy::BeginSheet(parent, sheet, nil);
    Check(parent.attachedSheet == sheet, "nil completion still attaches");
    chromium_legacy::EndSheet(parent, sheet);
    [sheet orderOut:nil];
    DrainUntil(^bool {
      return parent.attachedSheet == nil;
    });
    Check(parent.attachedSheet == nil, "nil completion ends safely");
    [sheet close];
    [parent close];
  }
  std::printf("%d sheet checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
