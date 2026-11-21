// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_FILE_TIMES_H_
#define LEGACY_APPLE_FILE_TIMES_H_

#include <errno.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "legacy/apple/clock.h"

namespace chromium_legacy {

// setattrlist predates Lion and can update only mtime, atomically preserving
// atime. Attribute values must follow bitmap order: modification before access.
inline int LegacySetFileTimes(const char* path,
                              const timespec& access,
                              const timespec& modification) {
  if (!path) {
    errno = EINVAL;
    return -1;
  }
  timespec accessed = access;
  timespec modified = modification;
  auto prepare = [](timespec& value) {
    if (value.tv_nsec == UTIME_OMIT) {
      return 0;
    }
    if (value.tv_nsec == UTIME_NOW) {
      return LegacyRealtime(&value);
    }
    if (value.tv_nsec < 0 || value.tv_nsec >= 1000000000) {
      errno = EINVAL;
      return -1;
    }
    return 0;
  };
  if (prepare(accessed) || prepare(modified)) {
    return -1;
  }
  attrlist attributes{};
  attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
  struct {
    timespec first;
    timespec second;
  } values{};
  size_t length;
  if (modified.tv_nsec == UTIME_OMIT) {
    if (accessed.tv_nsec == UTIME_OMIT) {
      return 0;
    }
    attributes.commonattr = ATTR_CMN_ACCTIME;
    values.first = accessed;
    length = sizeof(timespec);
  } else {
    attributes.commonattr = ATTR_CMN_MODTIME;
    values.first = modified;
    length = sizeof(timespec);
    if (accessed.tv_nsec != UTIME_OMIT) {
      attributes.commonattr |= ATTR_CMN_ACCTIME;
      values.second = accessed;
      length += sizeof(timespec);
    }
  }
  return setattrlist(path, &attributes, &values, length, 0);
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FILE_TIMES_H_
