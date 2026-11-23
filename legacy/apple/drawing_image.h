// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_DRAWING_IMAGE_H_
#define LEGACY_APPLE_DRAWING_IMAGE_H_
#import <AppKit/AppKit.h>
#include <cmath>

namespace chromium_legacy {
// Lion renders an owned raster representation immediately. Later systems keep
// the lazy, resolution-aware NSImage drawing handler.
inline NSImage* DrawingImage(NSSize size, BOOL flipped, BOOL (^draw)(NSRect)) {
  if (!draw)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 1080
  if (@available(macOS 10.8, *)) {
    return [NSImage imageWithSize:size flipped:flipped drawingHandler:draw];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1080
  if (!std::isfinite(size.width) || !std::isfinite(size.height) ||
      size.width < 0 || size.height < 0)
    return nil;
  NSImage* image = [[NSImage alloc] initWithSize:size];
  if (size.width == 0 || size.height == 0)
    return image;
  [image lockFocusFlipped:flipped];
  @try {
    draw(NSMakeRect(0, 0, size.width, size.height));
  } @finally {
    [image unlockFocus];
  }
  return image;
#else
  return nil;
#endif
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_DRAWING_IMAGE_H_
