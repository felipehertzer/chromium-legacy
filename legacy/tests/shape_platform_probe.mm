// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <stdio.h>
#include "services/shape_detection/native_detection_mac.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    ++failures;
    fprintf(stderr, "FAIL: %s\n", message);
  }
}
}  // namespace
int main() {
  @autoreleasepool {
    bool native_vision = false;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (@available(macOS 10.13, *))
      native_vision = true;
#endif
    Check(shape_detection::VisionAvailable() == native_vision,
          "native Vision capability follows the OS floor and forced fallback");
    NSError* error = [NSError errorWithDomain:@"org.chromium.legacy.probe"
                                         code:1
                                     userInfo:nil];
    NSArray<NSString*>* symbologies =
        shape_detection::NativeBarcodeSymbologies(&error);
    Check(!error, "native symbology enumeration clears stale errors");
    Check(symbologies != nil, "symbology enumeration returns a real array");
    if (native_vision) {
      Check(symbologies.count > 0,
            "supported native backend advertises formats");
      if (@available(macOS 10.13, *))
        Check([symbologies containsObject:VNBarcodeSymbologyQR],
              "native backend advertises its actual QR format");
    } else {
      Check(symbologies.count == 0,
            "unavailable backend advertises no formats");
    }
    Check([shape_detection::NativeBarcodeSymbologies(nullptr)
              isEqual:symbologies],
          "symbology enumeration accepts an omitted error output");
    CIDetector* text = shape_detection::CreateNativeTextDetector();
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    Check(text == nil, "forced unavailable text backend creates no detector");
#else
    if (@available(macOS 10.11, *))
      Check(text != nil,
            "supported OS creates its actual native text detector");
    else
      Check(text == nil, "older OS creates no native text detector");
#endif
    CIImage* blank = [[CIImage imageWithColor:[CIColor colorWithRed:1
                                                              green:1
                                                               blue:1]]
        imageByCroppingToRect:CGRectMake(0, 0, 64, 64)];
    Check(blank != nil, "owned synthetic image is valid");
    if (text)
      Check([text featuresInImage:blank].count == 0,
            "native text detector returns no text for a blank image");
    CIDetector* face = [CIDetector
        detectorOfType:CIDetectorTypeFace
               context:nil
               options:@{CIDetectorAccuracy : CIDetectorAccuracyLow}];
    Check(face != nil, "original Core Image face fallback is available");
    Check([face featuresInImage:blank].count == 0,
          "Core Image face fallback returns no faces for a blank image");
  }
  printf("%d shape platform checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
