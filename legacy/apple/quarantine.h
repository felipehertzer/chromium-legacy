// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_QUARANTINE_H_
#define LEGACY_APPLE_QUARANTINE_H_
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>

namespace chromium_legacy {
inline BOOL GetQuarantineProperties(NSURL* file, id* value, NSError** error) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101000
  if (@available(macOS 10.10, *)) {
    return [file getResourceValue:value
                           forKey:NSURLQuarantinePropertiesKey
                            error:error];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000
  CFTypeRef result = nullptr;
  FSRef file_ref;
  if (!file || !CFURLGetFSRef((__bridge CFURLRef)file, &file_ref)) {
    if (error) {
      *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                   code:NSFileNoSuchFileError
                               userInfo:nil];
    }
    return NO;
  }
  OSStatus status = LSCopyItemAttribute(&file_ref, kLSRolesAll,
                                        kLSItemQuarantineProperties, &result);
  // LSCopyItemAttribute follows the Copy rule even if a future implementation
  // returns an object together with an error.
  id object = CFBridgingRelease(result);
  if (status == noErr) {
    if (value)
      *value = object;
    return YES;
  }
  if (error) {
    *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                 code:status
                             userInfo:nil];
  }
#endif
  return NO;
}
inline BOOL SetQuarantineProperties(NSURL* file,
                                    NSDictionary* value,
                                    NSError** error) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101000
  if (@available(macOS 10.10, *)) {
    return [file setResourceValue:value
                           forKey:NSURLQuarantinePropertiesKey
                            error:error];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000
  FSRef file_ref;
  if (!file || !CFURLGetFSRef((__bridge CFURLRef)file, &file_ref)) {
    if (error) {
      *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                   code:NSFileNoSuchFileError
                               userInfo:nil];
    }
    return NO;
  }
  OSStatus status =
      LSSetItemAttribute(&file_ref, kLSRolesAll, kLSItemQuarantineProperties,
                         (__bridge CFDictionaryRef)value);
  if (status == noErr)
    return YES;
  if (error) {
    *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                 code:status
                             userInfo:nil];
  }
#endif
  return NO;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_QUARANTINE_H_
