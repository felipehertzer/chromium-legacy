// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Compile the original compositor helpers in the same translation unit.
#include <stdio.h>

#include <iostream>
#include <string_view>

#include "ui/accelerated_widget_mac/ca_renderer_layer_tree.mm"

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, std::string_view label) {
  ++checks;
  if (!value) {
    ++failures;
    std::cerr << "FAILED: " << label << '\n';
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    CALayer* layer = [[CALayer alloc] init];
    const gfx::RectF bounds(20, 40, 200, 100);
    const gfx::RRectF uniform(bounds, 20);
    if (@available(macOS 10.13, iOS 11.0, tvOS 11.0, *)) {
      float radius = 0;
      CACornerMask corners = 0;
      Check(ui::GetCALayerCornerRadius(uniform, &radius, &corners) &&
                radius == 20 && corners != 0,
            "native corner analysis retains uniform radius and mask");
    }
    ui::ClipCALayerToRRectF(layer, uniform, 2);
    Check(CGRectEqualToRect(layer.bounds, CGRectMake(0, 0, 100, 50)),
          "clipping bounds use device-independent size");
    Check(CGPointEqualToPoint(layer.position, CGPointMake(10, 20)),
          "clipping retains the scaled origin");
    Check(layer.masksToBounds && layer.cornerRadius == 10 && !layer.mask,
          "uniform circular corners use the original layer property");

    gfx::RRectF partial(bounds, 0);
    partial.SetCornerRadii(gfx::RRectF::Corner::kUpperLeft, 20, 20);
    ui::ClipCALayerToRRectF(layer, partial, 2);
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    Check(layer.mask != nil && layer.cornerRadius == 0,
          "partial corners use a shape mask on old systems");
#else
    if (@available(macOS 10.13, *)) {
      Check(!layer.mask && layer.cornerRadius == 10,
            "modern partial corners retain hardware clipping");
    }
#endif

    const gfx::RRectF elliptical(bounds, 20, 10);
    ui::ClipCALayerToRRectF(layer, elliptical, 2);
    Check([layer.mask isKindOfClass:[CAShapeLayer class]],
          "elliptical corners use a shape mask");
    CAShapeLayer* mask = (CAShapeLayer*)layer.mask;
    Check(CGRectEqualToRect(CGPathGetBoundingBox(mask.path), layer.bounds),
          "shape path covers the scaled layer bounds");
    Check(CGPathContainsPoint(mask.path, nullptr, CGPointMake(50, 25), false),
          "shape path includes its center");
    Check(!CGPathContainsPoint(mask.path, nullptr, CGPointMake(0, 0), false),
          "shape path excludes the rounded corner");
    Check(layer.cornerRadius == 0, "shape clipping resets an earlier radius");

    ui::ClipCALayerToRRectF(layer, uniform, 2);
    Check(!layer.mask && layer.cornerRadius == 10,
          "returning to uniform corners clears the old shape mask");
    ui::ClipCALayerToRRectF(layer, gfx::RRectF(bounds), 2);
    Check(!layer.mask && layer.cornerRadius == 0,
          "returning to a rectangle clears all corner clipping");

    gfx::RRectF unequal(bounds, 0);
    unequal.SetCornerRadii(gfx::RRectF::Corner::kUpperLeft, 10, 10);
    unequal.SetCornerRadii(gfx::RRectF::Corner::kLowerRight, 30, 30);
    ui::ClipCALayerToRRectF(layer, unequal, 1);
    Check(layer.mask &&
              CGRectEqualToRect(layer.bounds, CGRectMake(0, 0, 200, 100)),
          "distinct corner radii retain the existing path fallback");
  }
  printf("%d CoreAnimation checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
