// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include <initializer_list>
#include "legacy/apple/appearance.h"
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
API_AVAILABLE(macos(10.9))
void CheckAppearanceScopes() {
  NSAppearance* original = NSAppearance.currentAppearance;
  NSString* original_drawing_name = nil;
  if (@available(macOS 11.0, *)) {
    original_drawing_name = NSAppearance.currentDrawingAppearance.name;
  }
  __block NSColor* light = nil;
  __block NSColor* dark = nil;
  for (bool use_dark : {false, true}) {
    __block int calls = 0;
    chromium_legacy::WithAppearance(use_dark, ^{
      ++calls;
      NSColor* color = [NSColor.textColor
          colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      if (use_dark)
        dark = color;
      else
        light = color;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
      if (@available(macOS 10.14, *)) {
        NSAppearance* current = NSAppearance.currentAppearance;
        if (@available(macOS 11.0, *)) {
          current = NSAppearance.currentDrawingAppearance;
        }
        Check([current.name isEqual:(use_dark ? NSAppearanceNameDarkAqua
                                              : NSAppearanceNameAqua)],
              "callback uses the requested native appearance");
      }
#endif
    });
    Check(calls == 1 && NSAppearance.currentAppearance == original,
          "appearance callback runs once and restores the caller's context");
  }
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.14, *)) {
    Check(light && dark && dark.redComponent > light.redComponent,
          "native appearance changes resolve dynamic text colors");
  }
#endif
  BOOL caught = NO;
  @try {
    chromium_legacy::WithAppearance(true, ^{
      @throw [NSException exceptionWithName:@"ChromiumLegacyAppearanceTest"
                                     reason:@"owned fixture"
                                   userInfo:nil];
    });
  } @catch (NSException* exception) {
    caught = [exception.name isEqual:@"ChromiumLegacyAppearanceTest"];
  }
  Check(caught && NSAppearance.currentAppearance == original,
        "appearance context is restored when the callback raises");
  if (@available(macOS 11.0, *)) {
    Check([NSAppearance.currentDrawingAppearance.name
              isEqual:original_drawing_name],
          "drawing appearance also returns to its original value");
  }
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
    Check([chromium_legacy::FileTypeForMimeType(@"image/png")
              isEqual:@"public.png"],
          "MIME type retains its registered identifier");
    Check(chromium_legacy::FileTypeForMimeType(nil) == nil, "nil MIME type");
    Check(chromium_legacy::FileTypeForMimeType(@"") == nil, "empty MIME type");
    Check([chromium_legacy::PreferredExtensionForFileType(@"public.png")
              isEqual:@"png"],
          "preferred image extension");
    Check(chromium_legacy::PreferredExtensionForFileType(nil) == nil,
          "nil identifier has no extension");
    Check(chromium_legacy::PreferredExtensionForFileType(
              @"com.chromium.legacy.no-such-file-type") == nil,
          "unknown identifiers do not invent extensions");
    Check(chromium_legacy::FileTypeIsImage(@"public.png"),
          "PNG conforms to image");
    Check(!chromium_legacy::FileTypeIsImage(@"public.plain-text"),
          "text does not conform to image");
    Check(!chromium_legacy::FileTypeIsImage(nil),
          "nil does not conform to image");
    Check(chromium_legacy::FileTypeForURL(nil) == nil, "nil file URL");
    NSString* fixture = [NSTemporaryDirectory()
        stringByAppendingPathComponent:NSProcessInfo.processInfo
                                           .globallyUniqueString];
    NSFileManager* files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:fixture
            withIntermediateDirectories:NO
                             attributes:@{
                               NSFilePosixPermissions : @0700
                             }
                                  error:nil]) {
      return 1;
    }
    NSURL* metadata_url = [NSURL
        fileURLWithPath:[fixture stringByAppendingPathComponent:@"owned.txt"]];
    NSData* contents = [@"owned text" dataUsingEncoding:NSUTF8StringEncoding];
    Check([contents writeToURL:metadata_url
                       options:NSDataWritingAtomic
                         error:nil],
          "create owned metadata fixture");
    NSString* metadata_type = chromium_legacy::FileTypeForURL(metadata_url);
    Check(metadata_type.length &&
              !chromium_legacy::FileTypeIsImage(metadata_type),
          "real file metadata preserves a non-image type");
    NSURL* missing_url = [NSURL
        fileURLWithPath:[fixture
                            stringByAppendingPathComponent:@"missing.txt"]];
    Check(chromium_legacy::FileTypeForURL(missing_url) == nil,
          "missing files do not fabricate metadata");
    [files removeItemAtPath:fixture error:nil];
    chromium_legacy::WithAppearance(false, nil);
    if (@available(macOS 10.9, *)) {
      CheckAppearanceScopes();
    }
  }
  std::printf("%d menu platform checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
