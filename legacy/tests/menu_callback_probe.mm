// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Exercise actual NSView-associated callback ownership without opening a menu.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include "base/at_exit.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ref.h"
#include "base/memory/ref_counted.h"
#include "content/app_shim_remote_cocoa/web_menu_runner_mac.h"

class TrackedCallback : public base::RefCounted<TrackedCallback> {
 public:
  TrackedCallback(int* destroyed, int* invoked)
      : destroyed_(*destroyed), invoked_(*invoked) {}
  void Run(NSView* view, NSRect bounds, int index) {
    CHECK(view);
    CHECK_EQ(bounds.origin.x, 4);
    CHECK_EQ(bounds.size.width, 32);
    CHECK_EQ(index, 3);
    ++*invoked_;
  }

 private:
  friend class base::RefCounted<TrackedCallback>;
  ~TrackedCallback() { ++*destroyed_; }
  const raw_ref<int> destroyed_;
  const raw_ref<int> invoked_;
};

int main() {
  base::AtExitManager exit;
  int destroyed = 0, invoked = 0;
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 48)];
    std::vector<blink::mojom::MenuItemPtr> items;
    WebMenuRunner* runner = [[WebMenuRunner alloc] initWithItems:items
                                                        fontSize:13
                                                    rightAligned:NO];
    CHECK(runner);
    CHECK(!runner.selectedMenuItemIndex.has_value());
    auto state = base::MakeRefCounted<TrackedCallback>(&destroyed, &invoked);
    MenuWasRunCallback callback =
        base::BindRepeating(&TrackedCallback::Run, state);
    [WebMenuRunner registerForTestingMenuRunCallback:callback forView:view];
    callback.Reset();
    state.reset();
    CHECK_EQ(destroyed, 0);
    [runner runMenuInView:view
               withBounds:NSMakeRect(4, 5, 32, 24)
             initialIndex:3];
    CHECK_EQ(invoked, 1);
    CHECK_EQ(destroyed, 0);
    auto replacement =
        base::MakeRefCounted<TrackedCallback>(&destroyed, &invoked);
    MenuWasRunCallback second =
        base::BindRepeating(&TrackedCallback::Run, replacement);
    [WebMenuRunner registerForTestingMenuRunCallback:second forView:view];
    CHECK_EQ(destroyed, 1);
    replacement.reset();
    second.Reset();
    [runner runMenuInView:view
               withBounds:NSMakeRect(4, 5, 32, 24)
             initialIndex:3];
    CHECK_EQ(invoked, 2);
    CHECK_EQ(destroyed, 1);
    view = nil;
  }
  CHECK_EQ(destroyed, 2);
  printf("Native menu callbacks: retained copies, replacement, invocation and "
         "cleanup passed\n");
}
