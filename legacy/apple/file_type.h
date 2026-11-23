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
inline NSString* FileTypeForMimeType(NSString* mime_type) {
  if (!mime_type.length)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    return [UTType typeWithMIMEType:mime_type].identifier;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  return CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(
      kUTTagClassMIMEType, (__bridge CFStringRef)mime_type, nullptr));
#else
  return nil;
#endif
}

inline NSString* PreferredExtensionForFileType(NSString* identifier) {
  if (!identifier.length)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    return [UTType typeWithIdentifier:identifier].preferredFilenameExtension;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  return CFBridgingRelease(UTTypeCopyPreferredTagWithClass(
      (__bridge CFStringRef)identifier, kUTTagClassFilenameExtension));
#else
  return nil;
#endif
}

inline bool FileTypeIsImage(NSString* identifier) {
  if (!identifier.length)
    return false;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    return [[UTType typeWithIdentifier:identifier] conformsToType:UTTypeImage];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  return UTTypeConformsTo((__bridge CFStringRef)identifier, kUTTypeImage);
#else
  return false;
#endif
}

inline NSString* FileTypeForURL(NSURL* url) {
  if (!url)
    return nil;
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  if (@available(macOS 11, *)) {
    UTType* type = nil;
    return [url getResourceValue:&type forKey:NSURLContentTypeKey error:nil]
               ? type.identifier
               : nil;
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  NSString* identifier = nil;
  return [url getResourceValue:&identifier
                        forKey:NSURLTypeIdentifierKey
                         error:nil]
             ? identifier
             : nil;
#else
  return nil;
#endif
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FILE_TYPE_H_
