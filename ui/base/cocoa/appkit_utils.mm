// Copyright 2013 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/base/cocoa/appkit_utils.h"

#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cmath>
#include <limits>

namespace {

// Values of com.apple.trackpad.forceClick corresponding to "Look up & data
// detectors" in System Preferences -> Trackpad -> Point & Click.
enum class ForceTouchAction {
  NONE = 0,        // Unchecked or set to "Tap with three fingers".
  QUICK_LOOK = 1,  // Set to "Force Click with one finger".
};

}  // namespace

namespace ui {

bool ForceClickInvokesQuickLook() {
  return [NSUserDefaults.standardUserDefaults
             integerForKey:@"com.apple.trackpad.forceClick"] ==
         static_cast<NSInteger>(ForceTouchAction::QUICK_LOOK);
}

bool IsCGFloatEqual(CGFloat a, CGFloat b) {
  return std::fabs(a - b) <= std::numeric_limits<CGFloat>::epsilon();
}

bool IsActiveApplication() {
  return NSRunningApplication.currentApplication.active;
}

bool PasteMightBlockWithPrivacyAlert() {
  if (@available(macOS 15.4, *)) {
    NSPasteboardAccessBehavior behavior =
        NSPasteboard.generalPasteboard.accessBehavior;
    return behavior == NSPasteboardAccessBehaviorDefault ||
           behavior == NSPasteboardAccessBehaviorAsk;
  } else {
    return false;
  }
}

NSString* UTIForServicesType(NSString* type) {
  if (!type) {
    return nil;
  }
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 11.0, *)) {
    UTType* result = [UTType typeWithIdentifier:type];
    if (!result) {
      result = [UTType typeWithTag:type
                          tagClass:@"com.apple.nspboard-type"
                  conformingToType:nil];
    }
    return result.identifier;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000 || \
    defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  // The original string-based UTI API supports Lion through Catalina.
  // Resolve known identifiers first, then obsolete NS*PboardType tags.
  CFDictionaryRef declaration =
      UTTypeCopyDeclaration((__bridge CFStringRef)type);
  if (declaration) {
    CFTypeRef identifier =
        CFDictionaryGetValue(declaration, kUTTypeIdentifierKey);
    NSString* result = nil;
    if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()) {
      result = [(__bridge NSString*)identifier copy];
    }
    CFRelease(declaration);
    return result;
  }
  if ([type hasPrefix:@"dyn."]) {
    return type;
  }
  return CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(
      CFSTR("com.apple.nspboard-type"), (__bridge CFStringRef)type, nullptr));
#else
  return nil;
#endif
}

NSSet<NSString*>* UTIsForServicesTypeArray(NSArray* types) {
  NSMutableSet* result = [NSMutableSet set];
  for (NSString* type in types) {
    if (NSString* identifier = UTIForServicesType(type)) {
      [result addObject:identifier];
    }
  }
  return result;
}

}  // namespace ui
