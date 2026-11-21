// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/mac/legacy_os_compat.h"

#include "legacy/apple/product_version.h"

namespace base::mac {

NSString* ReadLegacyProductVersion(NSString* plist_path) {
  return chromium_legacy::ReadLegacyProductVersion(plist_path);
}

}  // namespace base::mac
