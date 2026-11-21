// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "legacy/apple/clock.h"
#include "legacy/apple/file_times.h"
#include "legacy/apple/remove_all.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool condition, const char* name) {
  ++checks;
  if (!condition) {
    fprintf(stderr, "FAIL: %s (errno=%d)\n", name, errno);
    ++failures;
  }
}

void Join(char* result, const char* parent, const char* leaf) {
  int count = snprintf(result, PATH_MAX, "%s/%s", parent, leaf);
  if (count < 0 || count >= PATH_MAX) {
    abort();
  }
}

bool MakeFile(const char* path) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) {
    return false;
  }
  bool written = write(fd, "sentinel", 8) == 8;
  return close(fd) == 0 && written;
}

bool Exists(const char* path) {
  struct stat info{};
  return lstat(path, &info) == 0;
}

void CheckSentinel(const char* path) {
  char data[8]{};
  int fd = open(path, O_RDONLY);
  bool intact = fd >= 0 && read(fd, data, sizeof(data)) == sizeof(data) &&
                memcmp(data, "sentinel", sizeof(data)) == 0;
  if (fd >= 0) {
    close(fd);
  }
  Check(intact, "outside target remains intact");
}

int FileDescriptorCount() {
  int count = 0;
  for (int fd = 0; fd < 4096; ++fd) {
    if (fcntl(fd, F_GETFD) != -1) {
      ++count;
    }
  }
  return count;
}

void ClockTests() {
  using namespace chromium_legacy;
  uint64_t nanos = 99;
  Check(MachTicksToNanos(9, 3, 2, &nanos) && nanos == 13,
        "tick conversion rounds down");
  Check(MachTicksToNanos(UINT64_MAX, UINT32_MAX, UINT32_MAX, &nanos) &&
            nanos == UINT64_MAX,
        "tick multiplication does not overflow before division");
  Check(!MachTicksToNanos(UINT64_MAX, 2, 1, &nanos),
        "reject nanosecond overflow");
  Check(!MachTicksToNanos(1, 1, 0, &nanos), "reject zero denominator");
  Check(!MachTicksToNanos(1, 0, 1, &nanos), "reject zero numerator");
  Check(!MachTicksToNanos(1, 1, 1, nullptr),
        "reject missing conversion output");
  Check(MachTicksToNanos(0, 1, 1, &nanos) && nanos == 0, "zero ticks");
  timespec legacy{}, modern{}, before{}, after{};
  Check(LegacyRealtime(&legacy) == 0, "legacy real time");
  Check(Realtime(&modern) == 0, "selected real time");
  Check(llabs(legacy.tv_sec - modern.tv_sec) <= 1 && legacy.tv_nsec >= 0 &&
            legacy.tv_nsec < 1000000000,
        "legacy real time agrees with system clock");
  Check(LegacyMonotonic(&before) == 0, "legacy monotonic clock");
  usleep(20000);
  Check(LegacyMonotonic(&after) == 0, "legacy monotonic clock after delay");
  int64_t elapsed = (after.tv_sec - before.tv_sec) * 1000000000 +
                    after.tv_nsec - before.tv_nsec;
  Check(elapsed >= 10000000 && elapsed < 10000000000LL,
        "legacy monotonic clock measures elapsed time");
  Check(Monotonic(&modern) == 0, "selected monotonic clock");
  Check(ClockGettime(static_cast<clockid_t>(0), &modern) == 0,
        "clock-ID real time");
  errno = 0;
  Check(ClockGettime(static_cast<clockid_t>(999), &modern) == -1 &&
            errno == EINVAL,
        "unsupported clock ID reports an error");
  Check(LegacyRealtime(nullptr) == -1 && errno == EINVAL,
        "legacy real time validates output");
  Check(LegacyMonotonic(nullptr) == -1 && errno == EINVAL,
        "legacy monotonic clock validates output");
}

void TimeTests(const char* root) {
  char file[PATH_MAX];
  Join(file, root, "times");
  Check(MakeFile(file), "create timestamp test file");
  struct stat before{}, after{};
  Check(stat(file, &before) == 0, "read original timestamps");
  timespec times[2] = {{0, UTIME_OMIT}, {1234567890, 123456789}};
  Check(chromium_legacy::LegacySetFileTimes(file, times[0], times[1]) == 0,
        "set legacy modification time");
  Check(stat(file, &after) == 0 &&
            after.st_mtimespec.tv_sec == times[1].tv_sec &&
            after.st_mtimespec.tv_nsec == times[1].tv_nsec,
        "preserve modification nanoseconds");
  Check(after.st_atimespec.tv_sec == before.st_atimespec.tv_sec &&
            after.st_atimespec.tv_nsec == before.st_atimespec.tv_nsec,
        "omitted access time stays unchanged");
  times[0] = {1234500000, 987654321};
  Check(chromium_legacy::LegacySetFileTimes(file, times[0], times[1]) == 0,
        "set both file times");
  Check(stat(file, &after) == 0 &&
            after.st_atimespec.tv_sec == times[0].tv_sec &&
            after.st_atimespec.tv_nsec == times[0].tv_nsec &&
            after.st_mtimespec.tv_nsec == times[1].tv_nsec,
        "attribute order preserves both timestamps");
  times[0].tv_nsec = UTIME_OMIT;
  times[1].tv_nsec = 1000000000;
  Check(chromium_legacy::LegacySetFileTimes(file, times[0], times[1]) == -1 &&
            errno == EINVAL,
        "invalid nanoseconds are rejected");
  times[1].tv_nsec = UTIME_NOW;
  Check(chromium_legacy::LegacySetFileTimes(file, times[0], times[1]) == 0,
        "current-time sentinel");
  Check(stat(file, &after) == 0 && llabs(after.st_mtime - time(nullptr)) < 2,
        "current-time sentinel agrees with real time");
  times[0].tv_nsec = UTIME_OMIT;
  times[1].tv_nsec = UTIME_OMIT;
  before = after;
  Check(chromium_legacy::LegacySetFileTimes(file, times[0], times[1]) == 0 &&
            stat(file, &after) == 0 &&
            after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec &&
            after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
        "two omitted times change neither timestamp");
  times[1] = {1234567890, 123456789};
  char link[PATH_MAX];
  Join(link, root, "time-link");
  Check(symlink(file, link) == 0, "create timestamp symlink");
  Check(chromium_legacy::LegacySetFileTimes(link, times[0], times[1]) == 0 &&
            stat(file, &after) == 0 && after.st_mtime == times[1].tv_sec,
        "timestamp update follows the requested symlink");
}

struct RaceContext {
  char victim[PATH_MAX];
  char moved[PATH_MAX];
  char target[PATH_MAX];
  int stop = 0;
};
void* RaceWriter(void* pointer) {
  auto* context = static_cast<RaceContext*>(pointer);
  while (!__atomic_load_n(&context->stop, __ATOMIC_RELAXED)) {
    mkdir(context->victim, 0700);
    rename(context->victim, context->moved);
    symlink(context->target, context->victim);
    unlink(context->victim);
    rename(context->moved, context->victim);
  }
  return nullptr;
}

void RemovalTests(const char* root) {
  using chromium_legacy::LegacyRemoveAll;
  char outside[PATH_MAX], sentinel[PATH_MAX], tree[PATH_MAX], child[PATH_MAX];
  Join(outside, root, "outside");
  Check(mkdir(outside, 0700) == 0, "create outside directory");
  Join(sentinel, outside, "keep");
  Check(MakeFile(sentinel), "create outside sentinel");
  Join(tree, root, "tree");
  Check(mkdir(tree, 0700) == 0, "create tree");
  Join(child, tree, "café-日本");
  Check(mkdir(child, 0700) == 0, "Unicode subdirectory");
  char nested[PATH_MAX];
  Join(nested, child, "file");
  Check(MakeFile(nested), "create nested file");
  Join(child, tree, "regular");
  Check(MakeFile(child), "create regular file");
  Join(child, tree, "outside-link");
  Check(symlink(outside, child) == 0, "link to outside directory");
  Join(child, tree, "broken");
  Check(symlink("missing", child) == 0, "broken symlink");
  Join(child, tree, "cycle");
  Check(symlink("cycle", child) == 0, "symlink cycle");
  uint64_t count = 999;
  Check(LegacyRemoveAll(tree, &count) == 0 && count == 7 && !Exists(tree),
        "recursive removal counts files, directories and symlinks");
  CheckSentinel(sentinel);
  Check(LegacyRemoveAll(tree, &count) == 0 && count == 0,
        "nonexistent path is not an error");
  Check(LegacyRemoveAll("", &count) == 0 && count == 0, "empty path");
  Check(LegacyRemoveAll(nullptr, &count) == -1 && errno == EINVAL,
        "null path is rejected");
  Check(LegacyRemoveAll(outside, nullptr) == -1 && errno == EINVAL,
        "missing count is rejected");

  Join(child, root, "root-link");
  Check(symlink(outside, child) == 0, "create root symlink");
  Check(LegacyRemoveAll(child, &count) == 0 && count == 1,
        "root symlink itself is removed");
  CheckSentinel(sentinel);

  Join(tree, root, "original");
  Check(mkdir(tree, 0700) == 0, "create rename test directory");
  Join(child, tree, "entry");
  Check(MakeFile(child), "create rename test entry");
  FSRef ref{};
  Check(FSPathMakeRefWithOptions(reinterpret_cast<const UInt8*>(tree),
                                 kFSPathMakeRefDoNotFollowLeafSymlink, &ref,
                                 nullptr) == noErr,
        "capture directory reference");
  char moved[PATH_MAX];
  Join(moved, root, "renamed");
  Check(rename(tree, moved) == 0 && symlink(outside, tree) == 0,
        "replace referenced path with outside symlink");
  count = 0;
  Check(chromium_legacy::internal::RemoveFileReference(ref, &count) == noErr &&
            count == 2 && !Exists(moved),
        "reference deletion retains directory identity after rename");
  CheckSentinel(sentinel);
  Check(LegacyRemoveAll(tree, &count) == 0 && count == 1,
        "remove replacement symlink");

  if (geteuid() != 0) {
    Join(tree, root, "protected");
    Check(mkdir(tree, 0700) == 0, "create permission test directory");
    Join(child, tree, "entry");
    Check(MakeFile(child) && chmod(tree, 0500) == 0,
          "protect parent directory");
    int result = LegacyRemoveAll(child, &count);
    int error = errno;
    Check(result == -1 && (error == EACCES || error == EPERM) && Exists(child),
          "permission errors preserve the file");
    Check(chmod(tree, 0700) == 0 && LegacyRemoveAll(tree, &count) == 0,
          "restore permission test directory");
  }

  RaceContext race{};
  Join(race.victim, root, "victim");
  Join(race.moved, root, "moved-victim");
  Join(race.target, root, "outside");
  pthread_t thread;
  int started = pthread_create(&thread, nullptr, RaceWriter, &race);
  Check(started == 0, "start symlink race writer");
  if (started == 0) {
    for (int iteration = 0; iteration < 500; ++iteration) {
      LegacyRemoveAll(race.victim, &count);
    }
    __atomic_store_n(&race.stop, 1, __ATOMIC_RELAXED);
    pthread_join(thread, nullptr);
    CheckSentinel(sentinel);
    LegacyRemoveAll(race.victim, &count);
    LegacyRemoveAll(race.moved, &count);
  }

  int before = FileDescriptorCount();
  bool removed = true;
  Join(tree, root, "repeat");
  for (int iteration = 0; iteration < 50; ++iteration) {
    if (mkdir(tree, 0700) || LegacyRemoveAll(tree, &count) || count != 1) {
      removed = false;
      break;
    }
  }
  Check(removed && FileDescriptorCount() == before,
        "repeated directory removal releases iterators and descriptors");
}
}  // namespace

int main() {
  ClockTests();
  char root[] = "/tmp/chromium-legacy-platform.XXXXXX";
  if (!mkdtemp(root)) {
    return 2;
  }
  TimeTests(root);
  RemovalTests(root);
  uint64_t count;
  Check(chromium_legacy::LegacyRemoveAll(root, &count) == 0,
        "remove probe temporary directory");
  printf("%d legacy platform checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
