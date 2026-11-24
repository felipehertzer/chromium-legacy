// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_CAPTURE_REGION_H_
#define LEGACY_APPLE_CAPTURE_REGION_H_

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

// Real CoreGraphics SPIs. The old constructor returns a retained CGS region
// through its second argument. Its matching release handles the empty
// singleton.
extern "C" {
CFTypeRef CGRegionCreateWithRect(CGRect rect) __attribute__((weak_import));
CGError CGSNewRegionWithRect(const CGRect* rect, CFTypeRef* region);
CGError CGSReleaseRegion(CFTypeRef region);
}

namespace chromium_legacy {
class ScopedCaptureRegion {
 public:
  ScopedCaptureRegion() = default;
  ScopedCaptureRegion(const ScopedCaptureRegion&) = delete;
  ScopedCaptureRegion& operator=(const ScopedCaptureRegion&) = delete;
  ~ScopedCaptureRegion() { Reset(); }

  bool Create(CGRect rect) {
    Reset();
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (CGRegionCreateWithRect) {
      modern_ = CGRegionCreateWithRect(rect);
      return modern_ != nullptr;
    }
#endif
    CGError status = CGSNewRegionWithRect(&rect, &legacy_);
    if (status != kCGErrorSuccess) {
      Reset();
      return false;
    }
    return legacy_ != nullptr;
  }
  void Reset() {
    if (modern_) {
      CFRelease(modern_);
      modern_ = nullptr;
    }
    if (legacy_) {
      CGSReleaseRegion(legacy_);
      legacy_ = nullptr;
    }
  }
  CFTypeRef get() const { return modern_ ? modern_ : legacy_; }

 private:
  CFTypeRef modern_ = nullptr;
  CFTypeRef legacy_ = nullptr;
};
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_CAPTURE_REGION_H_
