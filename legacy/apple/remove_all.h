// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_REMOVE_ALL_H_
#define LEGACY_APPLE_REMOVE_ALL_H_

#include <CoreServices/CoreServices.h>
#include <errno.h>
#include <stdint.h>

namespace chromium_legacy {
namespace internal {

inline bool MissingObject(OSStatus status) {
  return status == fnfErr || status == dirNFErr || status == errFSBadFSRef;
}

inline int FileManagerErrno(OSStatus status) {
  switch (status) {
    case fnfErr:
    case dirNFErr:
    case errFSBadFSRef:
      return ENOENT;
    case permErr:
    case afpAccessDenied:
      return EACCES;
    case fLckdErr:
      return EPERM;
    case wPrErr:
    case vLckdErr:
      return EROFS;
    case afpDirNotEmpty:
      return ENOTEMPTY;
    case fBsyErr:
      return EBUSY;
    case memFullErr:
      return ENOMEM;
    case errFSNotAFolder:
      return ENOTDIR;
    case nsvErr:
      return ENODEV;
    case bdNamErr:
      return ENAMETOOLONG;
    case paramErr:
      return EINVAL;
    case unimpErr:
    case errFSOperationNotSupported:
      return ENOTSUP;
    default:
      return EIO;
  }
}

class FileIterator {
 public:
  FSIterator value = nullptr;
  ~FileIterator() {
    if (value) {
      FSCloseIterator(value);
    }
  }
  FileIterator() = default;
  FileIterator(const FileIterator&) = delete;
  FileIterator& operator=(const FileIterator&) = delete;
};

inline OSStatus RemoveFileReference(const FSRef& ref, uint64_t* count) {
  FSCatalogInfo info{};
  OSStatus status = FSGetCatalogInfo(&ref, kFSCatInfoNodeFlags, &info, nullptr,
                                     nullptr, nullptr);
  if (MissingObject(status)) {
    return noErr;
  }
  if (status != noErr) {
    return status;
  }
  if (info.nodeFlags & kFSNodeIsDirectoryMask) {
    FileIterator iterator;
    status = FSOpenIterator(&ref, kFSIterateFlat | kFSIterateDelete,
                            &iterator.value);
    if (MissingObject(status)) {
      return noErr;
    }
    if (status != noErr) {
      return status;
    }
    for (;;) {
      FSRef child{};
      ItemCount actual = 0;
      status = FSGetCatalogInfoBulk(iterator.value, 1, &actual, nullptr,
                                    kFSCatInfoNone, nullptr, &child, nullptr,
                                    nullptr);
      if (status != noErr && status != errFSNoMoreItems) {
        return MissingObject(status) ? noErr : status;
      }
      const bool finished = status == errFSNoMoreItems;
      if (actual > 1) {
        return paramErr;
      }
      if (actual == 1) {
        status = RemoveFileReference(child, count);
        if (status != noErr) {
          return status;
        }
      }
      if (finished || actual == 0) {
        break;
      }
    }
  }
  status = FSDeleteObject(&ref);
  if (status == noErr) {
    ++*count;
  }
  return MissingObject(status) ? noErr : status;
}
}  // namespace internal

// The root is resolved once without following a leaf symlink. Descendants and
// deletions use FSRefs, never rebuilt paths, so renames cannot redirect a walk
// through an attacker-supplied symlink. These APIs are thread-safe on Lion.
inline int LegacyRemoveAll(const char* path, uint64_t* count) {
  if (!path || !count) {
    errno = EINVAL;
    return -1;
  }
  *count = 0;
  if (!*path) {
    return 0;
  }
  FSRef ref{};
  OSStatus status = FSPathMakeRefWithOptions(
      reinterpret_cast<const UInt8*>(path),
      kFSPathMakeRefDoNotFollowLeafSymlink, &ref, nullptr);
  if (internal::MissingObject(status)) {
    return 0;
  }
  if (status == noErr) {
    status = internal::RemoveFileReference(ref, count);
  }
  if (status == noErr) {
    return 0;
  }
  errno = internal::FileManagerErrno(status);
  return -1;
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_REMOVE_ALL_H_
