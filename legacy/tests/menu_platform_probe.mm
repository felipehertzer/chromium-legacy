// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include "legacy/apple/drawing_image.h"
#include "legacy/apple/file_type.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, const char* message) {
  ++checks;
  if (!success) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", message);
  }
}
NSColor* Pixel(NSBitmapImageRep* bitmap, NSInteger y) {
  return [[bitmap colorAtX:bitmap.pixelsWide / 2 y:y]
      colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
}
}  // namespace
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    Check(chromium_legacy::DrawingImage(NSMakeSize(8, 8), NO, nil) == nil,
          "nil drawing callback");
    NSColor* tops[2] = {nil, nil};
    for (int index = 0; index < 2; ++index) {
      BOOL flipped = index == 1;
      __block BOOL called = NO;
      __block BOOL correct_context = YES;
      NSImage* image = chromium_legacy::DrawingImage(
          NSMakeSize(8, 8), flipped, ^BOOL(NSRect bounds) {
            called = YES;
            correct_context &=
                NSGraphicsContext.currentContext.isFlipped == flipped;
            [NSColor.redColor setFill];
            NSRectFill(
                NSMakeRect(0, 0, bounds.size.width, bounds.size.height / 2));
            [NSColor.blueColor setFill];
            NSRectFill(NSMakeRect(0, bounds.size.height / 2, bounds.size.width,
                                  bounds.size.height / 2));
            return YES;
          });
      Check(NSEqualSizes(image.size, NSMakeSize(8, 8)), "image logical size");
      NSBitmapImageRep* bitmap =
          [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
      Check(called && correct_context,
            "callback receives the requested flipped context");
      Check(bitmap.pixelsWide >= 8 && bitmap.pixelsHigh >= 8,
            "real raster representation");
      NSColor* top = Pixel(bitmap, bitmap.pixelsHigh / 4);
      NSColor* bottom = Pixel(bitmap, bitmap.pixelsHigh * 3 / 4);
      Check((top.redComponent > 0.9 && bottom.blueComponent > 0.9) ||
                (top.blueComponent > 0.9 && bottom.redComponent > 0.9),
            "both colored halves render without overlap");
      tops[index] = top;
      [image setTemplate:YES];
      Check(image.isTemplate, "template metadata can be retained by callers");
    }
    Check((tops[0].redComponent > 0.9) != (tops[1].redComponent > 0.9),
          "flipped drawing reverses vertical placement");
    Check(chromium_legacy::FileTypeForExtension(nil) == nil, "nil extension");
    Check(chromium_legacy::FileTypeForExtension(@"") == nil, "empty extension");
    Check([chromium_legacy::FileTypeForExtension(@"txt")
              isEqual:@"public.plain-text"],
          "text extension identifier");
    Check([chromium_legacy::FileTypeForExtension(@"pdf")
              isEqual:@"com.adobe.pdf"],
          "PDF extension identifier");
    Check([chromium_legacy::FileTypeForExtension(@"png") isEqual:@"public.png"],
          "PNG extension identifier");
    Check([chromium_legacy::FileTypeForExtension(@"PNG") isEqual:@"public.png"],
          "extension casing");
    Check(chromium_legacy::FileTypeForExtension(@"chromium-legacy-unknown-type")
                  .length > 0,
          "unknown extension retains a dynamic identifier");
    Check(chromium_legacy::FileTypeDescription(@"pdf").length > 0,
          "native localized type description");
    Check(chromium_legacy::FileTypeDescription(nil) == nil,
          "nil type description");
  }
  std::printf("%d menu platform checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
