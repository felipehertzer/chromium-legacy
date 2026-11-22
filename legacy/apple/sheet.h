// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_SHEET_H_
#define LEGACY_APPLE_SHEET_H_

#import <AppKit/AppKit.h>

namespace chromium_legacy {
// The completion remains alive until AppKit ends the modal session, even if
// the sheet's own window delegate has already been cleared.
void BeginSheet(NSWindow* parent,
                NSWindow* sheet,
                void (^completion)(NSModalResponse));
// -1000 is the original NSStopResponse, now named NSModalResponseStop.
void EndSheet(NSWindow* parent,
              NSWindow* sheet,
              NSModalResponse response = -1000);
NSWindow* SheetParent(NSWindow* sheet);
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_SHEET_H_
