// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef PRINTING_BACKEND_CUPS_COMPAT_H_
#define PRINTING_BACKEND_CUPS_COMPAT_H_
#include "build/build_config.h"
#if BUILDFLAG(IS_MAC)
#include <Availability.h>
#define PRINTING_CUPS_IPP_AVAILABLE API_AVAILABLE(macos(10.9))
#else
#define PRINTING_CUPS_IPP_AVAILABLE
#endif

namespace printing {
inline bool NativeCupsIppAvailable() {
#if BUILDFLAG(IS_MAC)
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) && \
    __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
  return false;
#else
  if (__builtin_available(macOS 10.9, *))
    return true;
  return false;
#endif
#else
  return true;
#endif
}
}  // namespace printing
#endif  // PRINTING_BACKEND_CUPS_COMPAT_H_
