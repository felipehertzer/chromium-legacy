// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_FONT_CASCADE_H_
#define LEGACY_APPLE_FONT_CASCADE_H_
#include <CoreText/CoreText.h>

// The original one-argument API is exported by Lion's CoreText and the current
// SDK. Its ABI was also used by Chromium before the 10.8 API became required:
// https://chromium.googlesource.com/chromium/src/+/c8cf02a2b8d39e0f70c255e4d68f51da2b39cc49/ui/gfx/font_fallback_mac.mm
extern "C" CFArrayRef CTFontCopyDefaultCascadeList(CTFontRef);
namespace chromium_legacy {
inline CFArrayRef CopyFontCascade(CTFontRef font, CFArrayRef languages) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.8, *)) {
    return CTFontCopyDefaultCascadeListForLanguages(font, languages);
  }
#endif
  (void)languages;  // The original API uses the system language preferences.
  return CTFontCopyDefaultCascadeList(font);
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FONT_CASCADE_H_
