// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_FD_IO_H_
#define LEGACY_APPLE_FD_IO_H_
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include <utility>

// Lion's XNU 1699 implements per-thread fchdir (syscall 349). Keep the
// private entry point optional, so an unsupported runtime fails the operation
// rather than loading a missing symbol or changing the process-wide cwd.
extern "C" int __pthread_fchdir(int) __attribute__((weak_import));

namespace chromium_legacy {
namespace internal {
template <class Operation, class Result>
inline Result RelativeFileOperation(int parent,
                                    const char* path,
                                    Operation operation,
                                    Result failure) {
  if (!path) {
    errno = EFAULT;
    return failure;
  }
  if (*path == '/' || parent == AT_FDCWD) {
    return operation(path);
  }
  if (parent < 0) {
    errno = EBADF;
    return failure;
  }
  if (!__pthread_fchdir) {
    errno = ENOTSUP;
    return failure;
  }
  struct Call {
    Operation operation;
    const char* path;
    int parent;
    Result result;
    int error;
  } call{std::move(operation), path, parent, failure, 0};
  int cancellation_state;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cancellation_state);
  pthread_t worker;
  int error = pthread_create(
      &worker, nullptr,
      [](void* argument) -> void* {
        auto& state = *static_cast<Call*>(argument);
        if (__pthread_fchdir(state.parent) == 0) {
          state.result = state.operation(state.path);
        }
        state.error = errno;
        return nullptr;
      },
      &call);
  if (!error) {
    // Joining this freshly created, private thread cannot legitimately fail.
    // Never return while it still borrows the caller's stack and output data.
    if (pthread_join(worker, nullptr) != 0) {
      abort();
    }
    error = call.error;
  }
  pthread_setcancelstate(cancellation_state, nullptr);
  errno = error;
  return call.result;
}
}  // namespace internal

inline int LegacyOpenAt(int parent,
                        const char* path,
                        int flags,
                        mode_t mode = 0) {
  return internal::RelativeFileOperation(
      parent, path,
      [=](const char* value) { return ::open(value, flags, mode); }, -1);
}
inline int LegacyMkdirAt(int parent, const char* path, mode_t mode) {
  return internal::RelativeFileOperation(
      parent, path, [=](const char* value) { return ::mkdir(value, mode); },
      -1);
}
inline int LegacyFstatAt(int parent,
                         const char* path,
                         struct stat* output,
                         int flags) {
  if (flags & ~AT_SYMLINK_NOFOLLOW) {
    errno = EINVAL;
    return -1;
  }
  return internal::RelativeFileOperation(
      parent, path,
      [=](const char* value) {
        return flags & AT_SYMLINK_NOFOLLOW ? ::lstat(value, output)
                                           : ::stat(value, output);
      },
      -1);
}
inline int LegacyUnlinkAt(int parent, const char* path, int flags) {
  if (flags & ~AT_REMOVEDIR) {
    errno = EINVAL;
    return -1;
  }
  return internal::RelativeFileOperation(
      parent, path,
      [=](const char* value) {
        return flags & AT_REMOVEDIR ? ::rmdir(value) : ::unlink(value);
      },
      -1);
}
// Consumes fd on success. The stream may use a different descriptor; callers
// must use dirfd(stream), not the transferred fd, for further relative I/O.
inline DIR* LegacyFdOpenDir(int fd) {
  if (fd < 0) {
    errno = EBADF;
    return nullptr;
  }
  DIR* result = internal::RelativeFileOperation(
      fd, ".", [](const char* value) { return ::opendir(value); },
      static_cast<DIR*>(nullptr));
  if (result) {
    ::close(fd);
  }
  return result;
}

inline int openat(int parent, const char* path, int flags, mode_t mode = 0) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::openat(parent, path, flags, mode);
  }
#endif
  return LegacyOpenAt(parent, path, flags, mode);
}
inline int mkdirat(int parent, const char* path, mode_t mode) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::mkdirat(parent, path, mode);
  }
#endif
  return LegacyMkdirAt(parent, path, mode);
}
inline int fstatat(int parent,
                   const char* path,
                   struct stat* output,
                   int flags) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::fstatat(parent, path, output, flags);
  }
#endif
  return LegacyFstatAt(parent, path, output, flags);
}
inline int unlinkat(int parent, const char* path, int flags) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::unlinkat(parent, path, flags);
  }
#endif
  return LegacyUnlinkAt(parent, path, flags);
}
inline DIR* fdopendir(int fd) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (__builtin_available(macOS 10.10, *)) {
    return ::fdopendir(fd);
  }
#endif
  return LegacyFdOpenDir(fd);
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_FD_IO_H_
