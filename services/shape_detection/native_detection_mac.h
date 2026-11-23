// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef SERVICES_SHAPE_DETECTION_NATIVE_DETECTION_MAC_H_
#define SERVICES_SHAPE_DETECTION_NATIVE_DETECTION_MAC_H_

// Restore the missing scalar math inlines before Vision includes SIMD headers.
#include "legacy/apple/simd_math.h"

#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>

namespace shape_detection {
inline bool VisionAvailable() {
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  return false;
#else
  if (@available(macOS 10.13, *))
    return true;
  return false;
#endif
}

inline CIDetector* CreateNativeTextDetector() {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.11, *)) {
    return [CIDetector
        detectorOfType:CIDetectorTypeText
               context:nil
               options:@{CIDetectorAccuracy : CIDetectorAccuracyHigh}];
  }
#endif
  return nil;
}

inline NSArray<NSString*>* NativeBarcodeSymbologies(NSError** error) {
  if (error)
    *error = nil;
  if (!VisionAvailable())
    return @[];
  if (@available(macOS 10.13, *)) {
    if (@available(macOS 12.0, *)) {
      VNDetectBarcodesRequest* request = [[VNDetectBarcodesRequest alloc] init];
      return [request supportedSymbologiesAndReturnError:error];
    }
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 120000
    return [VNDetectBarcodesRequest supportedSymbologies];
#endif
  }
  return @[];
}
}  // namespace shape_detection

#endif  // SERVICES_SHAPE_DETECTION_NATIVE_DETECTION_MAC_H_
