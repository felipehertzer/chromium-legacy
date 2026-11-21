// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// C ABI adapters used only by the locally rebuilt Rust standard library.
#include "legacy/apple/rust_posix.h"

#include <Security/SecRandom.h>
#include <stdio.h>
#include <stdlib.h>

#include "legacy/apple/clock.h"
#include "legacy/apple/fd_io.h"
#include "legacy/apple/file_times.h"

extern "C" {
int ChromiumLegacyRustClockGettime(clockid_t clock, timespec* result) {
  return chromium_legacy::ClockGettime(clock, result);
}
void ChromiumLegacyRustRandom(unsigned char* output, size_t size) {
  if (SecRandomCopyBytes(kSecRandomDefault, size, output) != errSecSuccess) {
    abort();
  }
}
int ChromiumLegacyRustOpenAt(int parent,
                             const char* path,
                             int flags,
                             mode_t mode) {
  return chromium_legacy::openat(parent, path, flags, mode);
}
int ChromiumLegacyRustFstatAt(int parent,
                              const char* path,
                              struct stat* result,
                              int flags) {
  return chromium_legacy::fstatat(parent, path, result, flags);
}
int ChromiumLegacyRustMkdirAt(int parent, const char* path, mode_t mode) {
  return chromium_legacy::mkdirat(parent, path, mode);
}
int ChromiumLegacyRustUnlinkAt(int parent, const char* path, int flags) {
  return chromium_legacy::unlinkat(parent, path, flags);
}
DIR* ChromiumLegacyRustFdOpenDir(int fd) {
  return chromium_legacy::fdopendir(fd);
}
int ChromiumLegacyRustDirFd(DIR* directory) {
  // The SDK expands dirfd to the old DIR layout for pre-10.8 deployments.
  return dirfd(directory);
}
int ChromiumLegacyRustRenameAt(int source_parent,
                               const char* source,
                               int target_parent,
                               const char* target) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::renameat(source_parent, source, target_parent, target);
  }
#endif
  if (!source || !target) {
    errno = EFAULT;
    return -1;
  }
  if (*source == '/') {
    return chromium_legacy::internal::RelativeFileOperation(
        target_parent, target,
        [=](const char*) { return ::rename(source, target); }, -1);
  }
  if (*target == '/' || source_parent == target_parent) {
    return chromium_legacy::internal::RelativeFileOperation(
        source_parent, source,
        [=](const char*) { return ::rename(source, target); }, -1);
  }
  struct stat from{}, to{};
  if (::fstat(source_parent, &from) == 0 && ::fstat(target_parent, &to) == 0 &&
      from.st_dev == to.st_dev && from.st_ino == to.st_ino) {
    return chromium_legacy::internal::RelativeFileOperation(
        source_parent, source,
        [=](const char*) { return ::rename(source, target); }, -1);
  }
  // Lion has no atomic two-directory renameat. Never reconstruct paths and
  // risk acting in a replaced directory. std::fs::rename uses rename directly.
  errno = ENOTSUP;
  return -1;
}
int ChromiumLegacyRustFchmodAt(int parent,
                               const char* path,
                               mode_t mode,
                               int flags) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::fchmodat(parent, path, mode, flags);
  }
#endif
  if (flags & ~AT_SYMLINK_NOFOLLOW) {
    errno = EINVAL;
    return -1;
  }
  return chromium_legacy::internal::RelativeFileOperation(
      parent, path,
      [=](const char* value) {
        return flags & AT_SYMLINK_NOFOLLOW ? ::lchmod(value, mode)
                                           : ::chmod(value, mode);
      },
      -1);
}
int ChromiumLegacyRustLinkAt(int source_parent,
                             const char* source,
                             int target_parent,
                             const char* target,
                             int flags) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::linkat(source_parent, source, target_parent, target, flags);
  }
#endif
  // Older link() implementations differ in symlink behavior. Fail explicitly
  // rather than weaken the linkat contract or rebuild paths from descriptors.
  errno = ENOTSUP;
  return -1;
}
int ChromiumLegacyRustFutimens(int fd,
                               const timespec* access,
                               const timespec* modification) {
  const timespec now{0, UTIME_NOW};
  if (!access && !modification) {
    access = modification = &now;
  }
  if (!access || !modification) {
    errno = EINVAL;
    return -1;
  }
  return chromium_legacy::LegacySetFDFileTimes(fd, *access, *modification);
}
int ChromiumLegacyRustUtimensAt(int parent,
                                const char* path,
                                const timespec* access,
                                const timespec* modification,
                                int flags) {
  if (flags & ~AT_SYMLINK_NOFOLLOW) {
    errno = EINVAL;
    return -1;
  }
  const timespec now{0, UTIME_NOW};
  if (!access && !modification) {
    access = modification = &now;
  }
  if (!access || !modification) {
    errno = EINVAL;
    return -1;
  }
  return chromium_legacy::internal::RelativeFileOperation(
      parent, path,
      [=](const char* value) {
        return chromium_legacy::LegacySetFileTimes(
            value, *access, *modification,
            flags & AT_SYMLINK_NOFOLLOW ? FSOPT_NOFOLLOW : 0);
      },
      -1);
}
}  // extern "C"
