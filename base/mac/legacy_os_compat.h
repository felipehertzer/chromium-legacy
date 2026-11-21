// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef BASE_MAC_LEGACY_OS_COMPAT_H_
#define BASE_MAC_LEGACY_OS_COMPAT_H_

#import <Foundation/Foundation.h>

#include "base/base_export.h"

namespace base::mac {

// Reads ProductVersion without APIs introduced after OS X Lion. Returns nil
// when the file is missing, malformed, or has no nonempty string
// ProductVersion. A path argument keeps the fallback testable without changing
// system files.
BASE_EXPORT NSString* ReadLegacyProductVersion(NSString* plist_path);

}  // namespace base::mac

#endif  // BASE_MAC_LEGACY_OS_COMPAT_H_
