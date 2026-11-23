// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "legacy/apple/sheet.h"

#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
@interface ChromiumLegacySheetCompletion : NSObject
@property(copy) void (^completion)(NSModalResponse);
- (void)sheetDidEnd:(NSWindow*)sheet
         returnCode:(NSInteger)response
        contextInfo:(void*)context;
@end

@implementation ChromiumLegacySheetCompletion
@synthesize completion = _completion;
- (void)sheetDidEnd:(NSWindow*)sheet
         returnCode:(NSInteger)response
        contextInfo:(void*)context {
  (void)sheet;
  // Balance the retain passed to AppKit, keeping the delegate alive throughout
  // the callback. AppKit does not own the contextInfo pointer.
  ChromiumLegacySheetCompletion* lifetime =
      (__bridge_transfer ChromiumLegacySheetCompletion*)context;
  void (^completion)(NSModalResponse) = lifetime.completion;
  lifetime.completion = nil;
  if (completion) {
    completion(response);
  }
}
@end
#endif

namespace chromium_legacy {
void BeginSheet(NSWindow* parent,
                NSWindow* sheet,
                void (^completion)(NSModalResponse)) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
  if (@available(macOS 10.9, *)) {
    [parent beginSheet:sheet completionHandler:completion];
    return;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
  ChromiumLegacySheetCompletion* delegate =
      [[ChromiumLegacySheetCompletion alloc] init];
  delegate.completion = completion;
  void* context = (__bridge_retained void*)delegate;
  [NSApp beginSheet:sheet
      modalForWindow:parent
       modalDelegate:delegate
      didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
         contextInfo:context];
#endif
}

void EndSheet(NSWindow* parent, NSWindow* sheet, NSModalResponse response) {
  (void)parent;  // The original NSApplication API identifies the sheet alone.
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
  if (@available(macOS 10.9, *)) {
    [parent endSheet:sheet returnCode:response];
    return;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
  [NSApp endSheet:sheet returnCode:response];
#endif
}

NSWindow* SheetParent(NSWindow* sheet) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
  if (@available(macOS 10.9, *)) {
    return sheet.sheetParent;
  }
#endif
  for (NSWindow* candidate in NSApp.windows) {
    if (candidate.attachedSheet == sheet) {
      return candidate;
    }
  }
  return nil;
}
}  // namespace chromium_legacy
