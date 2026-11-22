// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>

#include <cstdio>

#include "legacy/apple/accessibility.h"
#include "legacy/apple/localized_string.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, const char* description) {
  ++checks;
  if (!success) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", description);
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    NSDictionary* polite =
        chromium_legacy::AccessibilityAnnouncementInfo(@"hello %n", false);
    NSDictionary* urgent =
        chromium_legacy::AccessibilityAnnouncementInfo(@"urgent", true);
    Check([[polite objectForKey:NSAccessibilityAnnouncementKey]
              isEqual:@"hello %n"],
          "announcement text is retained verbatim");
    bool has_priority = false;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (@available(macOS 10.9, *)) {
      has_priority = true;
      Check([[polite objectForKey:NSAccessibilityPriorityKey] integerValue] ==
                NSAccessibilityPriorityMedium,
            "polite native priority");
      Check([[urgent objectForKey:NSAccessibilityPriorityKey] integerValue] ==
                NSAccessibilityPriorityHigh,
            "assertive native priority");
    }
#endif
    Check(polite.count == (has_priority ? 2u : 1u),
          "announcement fields match OS support");
    Check(urgent.count == polite.count, "both priorities use the same schema");
    if (@available(macOS 10.12, *)) {
      // Validate the historical Chromium wire names against real AppKit values.
      Check([NSAccessibilitySearchCurrentElementKey isEqual:@"AXStartElement"],
            "search start key ABI");
      Check([NSAccessibilitySearchDirectionKey isEqual:@"AXDirection"],
            "search direction key ABI");
      Check([NSAccessibilitySearchDirectionNext isEqual:@"AXDirectionNext"],
            "forward search ABI");
      Check([NSAccessibilitySearchDirectionPrevious
                isEqual:@"AXDirectionPrevious"],
            "backward search ABI");
      Check([NSAccessibilitySearchResultsLimitKey isEqual:@"AXResultsLimit"],
            "search limit ABI");
      Check([NSAccessibilitySearchTextKey isEqual:@"AXSearchText"],
            "search text ABI");
      Check([NSAccessibilitySearchIdentifiersKey isEqual:@"AXSearchKey"],
            "search predicate ABI");
      Check([NSAccessibilityRequiredAttribute isEqual:@"AXRequired"],
            "required attribute ABI");
    }
    NSArray* texts = @[
      @"", @"hello WORLD", @"straße café", @"i I İ ı", @"ΟΣ Σίσυφος", @"𐐀 𐐨 😀"
    ];
    for (NSString* language in @[ @"en_US", @"tr_TR", @"lt_LT" ]) {
      NSLocale* locale = [NSLocale localeWithLocaleIdentifier:language];
      for (NSString* text in texts) {
        NSString* upper = chromium_legacy::LocalizedCaseString(
            text, chromium_legacy::StringCase::kUpper, locale);
        NSString* lower = chromium_legacy::LocalizedCaseString(
            text, chromium_legacy::StringCase::kLower, locale);
        NSString* title = chromium_legacy::LocalizedCaseString(
            text, chromium_legacy::StringCase::kTitle, locale);
        if (@available(macOS 10.8, *)) {
          Check([upper isEqual:[text uppercaseStringWithLocale:locale]],
                "Unicode uppercase matches Foundation");
          Check([lower isEqual:[text lowercaseStringWithLocale:locale]],
                "Unicode lowercase matches Foundation");
          Check([title isEqual:[text capitalizedStringWithLocale:locale]],
                "Unicode capitalization matches Foundation");
        }
      }
    }
    NSLocale* turkish = [NSLocale localeWithLocaleIdentifier:@"tr_TR"];
    Check([chromium_legacy::LocalizedCaseString(
              @"i", chromium_legacy::StringCase::kUpper, turkish) isEqual:@"İ"],
          "Turkish dotted I");
    Check([chromium_legacy::LocalizedCaseString(
              @"I", chromium_legacy::StringCase::kLower, turkish) isEqual:@"ı"],
          "Turkish dotless i");
    Check(chromium_legacy::LocalizedCaseString(
              nil, chromium_legacy::StringCase::kTitle) == nil,
          "nil text");
    NSMutableString* input = [NSMutableString stringWithString:@"hello"];
    NSString* converted = chromium_legacy::LocalizedCaseString(
        input, chromium_legacy::StringCase::kUpper);
    Check([input isEqual:@"hello"], "casing preserves source object");
    [input setString:@"changed"];
    Check([converted isEqual:@"HELLO"],
          "casing returns an owned independent result");
  }
  std::printf("%d accessibility platform checks, %d failures\n", checks,
              failures);
  return failures ? 1 : 0;
}
