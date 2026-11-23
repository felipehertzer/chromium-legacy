// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_FSEVENTS_H_
#define LEGACY_APPLE_FSEVENTS_H_

#include <CoreServices/CoreServices.h>

#include <cstdint>
#include <optional>

namespace chromium_legacy {
inline FSEventStreamCreateFlags FSEventsExtendedDataFlag() {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101300
  if (__builtin_available(macOS 10.13, *)) {
    return kFSEventStreamCreateFlagUseExtendedData;
  }
#endif
  return 0;
}

// The path is borrowed from the callback's array. Earlier streams supply
// CFString paths and no file IDs; extended streams supply dictionaries.
struct FSEventsPathData {
  CFStringRef path = nullptr;
  std::optional<uint64_t> inode;
};
inline FSEventsPathData ReadFSEventsPath(CFTypeRef value) {
  FSEventsPathData data;
  if (!value) {
    return data;
  }
  if (CFGetTypeID(value) == CFStringGetTypeID()) {
    data.path = static_cast<CFStringRef>(value);
  } else if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
    auto dictionary = static_cast<CFDictionaryRef>(value);
    CFTypeRef path = CFDictionaryGetValue(
        dictionary, kFSEventStreamEventExtendedDataPathKey);
    if (path && CFGetTypeID(path) == CFStringGetTypeID()) {
      data.path = static_cast<CFStringRef>(path);
    }
    CFTypeRef inode =
        CFDictionaryGetValue(dictionary, kFSEventStreamEventExtendedFileIDKey);
    SInt64 number;
    if (inode && CFGetTypeID(inode) == CFNumberGetTypeID() &&
        CFNumberGetValue(static_cast<CFNumberRef>(inode), kCFNumberSInt64Type,
                         &number) &&
        number >= 0) {
      data.inode = static_cast<uint64_t>(number);
    }
  }
  return data;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FSEVENTS_H_
