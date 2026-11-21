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

namespace internal {
// Attribute values follow bitmap order: modification before access. Setting
// only the requested attributes preserves omitted timestamps atomically.
template <class Setter>
inline int SetLegacyFileTimes(const timespec& access,
                              const timespec& modification,
                              Setter set) {
  timespec accessed = access;
  timespec modified = modification;
  timespec now{};
  if ((accessed.tv_nsec == UTIME_NOW || modified.tv_nsec == UTIME_NOW) &&
      LegacyRealtime(&now)) {
    return -1;
  }
  auto prepare = [&now](timespec& value) {
    if (value.tv_nsec == UTIME_OMIT) {
      return 0;
    }
    if (value.tv_nsec == UTIME_NOW) {
      value = now;
      return 0;
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
  return set(&attributes, &values, length);
}
}  // namespace internal

inline int LegacySetFileTimes(const char* path,
                              const timespec& access,
                              const timespec& modification,
                              unsigned options = 0) {
  if (!path) {
    errno = EINVAL;
    return -1;
  }
  return internal::SetLegacyFileTimes(
      access, modification,
      [=](attrlist* attributes, void* values, size_t length) {
        return setattrlist(path, attributes, values, length, options);
      });
}
inline int LegacySetFDFileTimes(int fd,
                                const timespec& access,
                                const timespec& modification) {
  return internal::SetLegacyFileTimes(
      access, modification,
      [=](attrlist* attributes, void* values, size_t length) {
        return fsetattrlist(fd, attributes, values, length, 0);
      });
}

}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FILE_TIMES_H_
