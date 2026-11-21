// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>

#include "legacy/apple/font_cascade.h"
#import "ui/base/cocoa/appkit_utils.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool result, const char* name) {
  ++checks;
  if (!result) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", name);
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    NSString* plain = @"public.utf8-plain-text";
    NSString* rtf = @"public.rtf";
    Check(!ui::UTIForServicesType(nil), "nil service type");
    Check([ui::UTIForServicesType(plain) isEqual:plain], "plain identifier");
    Check([ui::UTIForServicesType(rtf) isEqual:rtf], "RTF identifier");
    Check([ui::UTIForServicesType(NSPasteboardTypeString) isEqual:plain],
          "current plain pasteboard type");
    Check([ui::UTIForServicesType(NSPasteboardTypeRTF) isEqual:rtf],
          "current RTF pasteboard type");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Check([ui::UTIForServicesType(NSStringPboardType) isEqual:plain],
          "obsolete plain pasteboard type");
    Check([ui::UTIForServicesType(NSRTFPboardType) isEqual:rtf],
          "obsolete RTF pasteboard type");
    NSSet* collapsed = ui::UTIsForServicesTypeArray(
        @[ NSPasteboardTypeString, NSStringPboardType ]);
#pragma clang diagnostic pop
    Check(collapsed.count == 1 && [collapsed containsObject:plain],
          "aliases collapse to one type");
    NSSet* both = ui::UTIsForServicesTypeArray(
        @[ NSPasteboardTypeString, NSPasteboardTypeRTF ]);
    Check(both.count == 2 && [both containsObject:plain] &&
              [both containsObject:rtf],
          "multiple service types");
    Check(ui::UTIsForServicesTypeArray(nil).count == 0, "nil type array");
    Check(![ui::UTIForServicesType(@"org.chromium.legacy.unknown-pboard")
              isEqual:plain],
          "unknown types do not enable plain-text services");
    Check([ui::UTIForServicesType(@"PUBLIC.UTF8-PLAIN-TEXT") isEqual:plain],
          "case-insensitive identifiers remain canonical");
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 20, nullptr);
    Check(font != nullptr, "create CoreText font");
    Check(font && CTFontGetSize(font) == 20, "font size");
    CFArrayRef cascade =
        font ? chromium_legacy::CopyFontCascade(font, nullptr) : nullptr;
    bool is_array = cascade && CFGetTypeID(cascade) == CFArrayGetTypeID();
    Check(is_array, "cascade array ownership and type");
    bool nonempty = is_array && CFArrayGetCount(cascade) > 0;
    Check(nonempty, "system fallback cascade is nonempty");
    CFTypeRef first = nonempty ? CFArrayGetValueAtIndex(cascade, 0) : nullptr;
    bool is_descriptor =
        first && CFGetTypeID(first) == CTFontDescriptorGetTypeID();
    Check(is_descriptor, "cascade holds font descriptors");
    CTFontRef fallback =
        is_descriptor ? CTFontCreateWithFontDescriptor(
                            static_cast<CTFontDescriptorRef>(first), 0, nullptr)
                      : nullptr;
    Check(fallback != nullptr, "cascade descriptor creates a fallback font");
    if (fallback) {
      CFRelease(fallback);
    }
    if (cascade) {
      CFRelease(cascade);
    }
    if (font) {
      CFRelease(font);
    }
    std::printf("%d macOS Services/font checks, %d failures\n", checks,
                failures);
    return failures ? 1 : 0;
  }
}
