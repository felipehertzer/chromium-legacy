// Copyright 2015 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "content/renderer/theme_helper_mac.h"

#include <Cocoa/Cocoa.h>

#include "base/strings/sys_string_conversions.h"

extern "C" {
bool CGFontRenderingGetFontSmoothingDisabled(void) API_AVAILABLE(macos(10.14));
}

namespace content {

bool IsSubpixelAntialiasingAvailable() {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.14, *)) {
    // See https://trac.webkit.org/changeset/239306/webkit for more info.
    return !CGFontRenderingGetFontSmoothingDisabled();
  }
#endif
  // Earlier systems retain the pre-Mojave subpixel-rendering path.
  return true;
}

}  // namespace content
