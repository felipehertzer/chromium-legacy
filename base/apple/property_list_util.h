// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef BASE_APPLE_PROPERTY_LIST_UTIL_H_
#define BASE_APPLE_PROPERTY_LIST_UTIL_H_

#import <Foundation/Foundation.h>

namespace base::apple {

// NSData and NSPropertyListSerialization preserve read/parse errors on systems
// predating NSDictionary's URL methods with NSError output parameters.
inline NSDictionary* ReadPropertyListDictionary(NSURL* url,
                                                NSError** error = nullptr) {
  NSData* data = [NSData dataWithContentsOfURL:url options:0 error:error];
  if (!data) {
    return nil;
  }
  id value =
      [NSPropertyListSerialization propertyListWithData:data
                                                options:NSPropertyListImmutable
                                                 format:nullptr
                                                  error:error];
  if (!value) {
    return nil;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                   code:NSPropertyListReadCorruptError
                               userInfo:nil];
    }
    return nil;
  }
  return value;
}

inline NSMutableDictionary* ReadMutablePropertyListDictionary(
    NSURL* url,
    NSError** error = nullptr) {
  return [ReadPropertyListDictionary(url, error) mutableCopy];
}

// Match NSDictionary's XML property-list output and atomic replacement.
inline bool WritePropertyListDictionary(NSDictionary* dictionary,
                                        NSURL* url,
                                        NSError** error = nullptr) {
  if (!dictionary) {
    return false;
  }
  if (![NSPropertyListSerialization
              propertyList:dictionary
          isValidForFormat:NSPropertyListXMLFormat_v1_0]) {
    if (error) {
      *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                   code:NSPropertyListWriteStreamError
                               userInfo:nil];
    }
    return false;
  }
  NSData* data = [NSPropertyListSerialization
      dataWithPropertyList:dictionary
                    format:NSPropertyListXMLFormat_v1_0
                   options:0
                     error:error];
  return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

}  // namespace base::apple

#endif  // BASE_APPLE_PROPERTY_LIST_UTIL_H_
