// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_CV_BUFFER_H_
#define LEGACY_APPLE_CV_BUFFER_H_
#include <CoreVideo/CoreVideo.h>

namespace chromium_legacy {
inline CFTypeRef CopyBufferAttachment(CVBufferRef buffer,
                                      CFStringRef key,
                                      CVAttachmentMode* mode) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 12.0, iOS 15.0, tvOS 15.0, *)) {
    return CVBufferCopyAttachment(buffer, key, mode);
  }
#endif
#if (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) &&   \
     __MAC_OS_X_VERSION_MIN_REQUIRED < 120000) ||  \
    (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) &&  \
     __IPHONE_OS_VERSION_MIN_REQUIRED < 150000) || \
    (defined(__TV_OS_VERSION_MIN_REQUIRED) &&      \
     __TV_OS_VERSION_MIN_REQUIRED < 150000) ||     \
    defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  CFTypeRef value = CVBufferGetAttachment(buffer, key, mode);
  // The old getter borrows its result. Match the new Copy function's ownership.
  return value ? CFRetain(value) : nullptr;
#else
  return nullptr;
#endif
}

inline bool HasBufferAttachment(CVBufferRef buffer, CFStringRef key) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 12.0, iOS 15.0, tvOS 15.0, *)) {
    return CVBufferHasAttachment(buffer, key);
  }
#endif
#if (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) &&   \
     __MAC_OS_X_VERSION_MIN_REQUIRED < 120000) ||  \
    (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) &&  \
     __IPHONE_OS_VERSION_MIN_REQUIRED < 150000) || \
    (defined(__TV_OS_VERSION_MIN_REQUIRED) &&      \
     __TV_OS_VERSION_MIN_REQUIRED < 150000) ||     \
    defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  return CVBufferGetAttachment(buffer, key, nullptr) != nullptr;
#else
  return false;
#endif
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_CV_BUFFER_H_
