// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_FILE_TYPE_H_
#define LEGACY_APPLE_FILE_TYPE_H_
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

namespace chromium_legacy {
inline NSString* FileTypeForExtension(NSString* extension) {
  if (!extension.length)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    return [UTType typeWithFilenameExtension:extension].identifier;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  return CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(
      kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, nullptr));
#else
  return nil;
#endif
}
inline NSString* FileTypeDescription(NSString* extension) {
  if (!extension.length)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    return [UTType typeWithFilenameExtension:extension].localizedDescription;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  NSString* type = FileTypeForExtension(extension);
  return type ? CFBridgingRelease(
                    UTTypeCopyDescription((__bridge CFStringRef)type))
              : nil;
#else
  return nil;
#endif
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FILE_TYPE_H_
