// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <mach/mach.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "legacy/apple/atomic_wait.h"
#include "legacy/apple/audit_token.h"
#include "legacy/apple/fd_io.h"
#include "legacy/apple/rust_posix.h"

extern "C" void* __alloc_token_aligned_alloc(size_t alignment,
                                             size_t size,
                                             size_t token)
    __attribute__((weak_import));

namespace {
int failures = 0;
int checks = 0;
void Check(bool condition, std::string_view name) {
  ++checks;
  if (!condition) {
    ++failures;
    std::cerr << "FAIL: " << name << "\n";
  }
}
}  // namespace

int main() {
  using namespace std::chrono;
  audit_token_t token{};
  mach_msg_type_number_t token_count = TASK_AUDIT_TOKEN_COUNT;
  Check(task_info(mach_task_self(), TASK_AUDIT_TOKEN,
                  reinterpret_cast<task_info_t>(&token),
                  &token_count) == KERN_SUCCESS,
        "obtain kernel-issued audit token");
  pid_t decoded_pid = -1;
  ChromiumLegacyAuditTokenToAu32(token, nullptr, nullptr, nullptr, nullptr,
                                 nullptr, &decoded_pid, nullptr, nullptr);
  Check(decoded_pid == getpid(), "legacy OS audit decoder preserves PID");
  auto before = steady_clock::now();
  std::this_thread::sleep_for(milliseconds(20));
  Check(steady_clock::now() - before >= milliseconds(10), "steady clock");
  Check(system_clock::to_time_t(system_clock::now()) > 1700000000,
        "system clock epoch");
  struct alignas(128) Aligned {
    int value = 42;
  };
  auto aligned = std::make_unique<Aligned>();
  Check(reinterpret_cast<uintptr_t>(aligned.get()) % alignof(Aligned) == 0 &&
            aligned->value == 42,
        "aligned C++ allocation");
  if (__alloc_token_aligned_alloc) {
    void* token_aligned = __alloc_token_aligned_alloc(64, 128, 0);
    Check(token_aligned && reinterpret_cast<uintptr_t>(token_aligned) % 64 == 0,
          "bootstrap C allocation keeps alignment");
    std::free(token_aligned);
    void* byte_aligned = __alloc_token_aligned_alloc(1, 1, 0);
    Check(byte_aligned, "bootstrap C allocation supports byte alignment");
    std::free(byte_aligned);
    void* small_aligned = __alloc_token_aligned_alloc(4, 12, 0);
    Check(small_aligned && reinterpret_cast<uintptr_t>(small_aligned) % 4 == 0,
          "bootstrap C allocation supports sub-pointer alignment");
    std::free(small_aligned);
    errno = 0;
    Check(!__alloc_token_aligned_alloc(64, 129, 0) && errno == EINVAL,
          "bootstrap C allocation rejects a nonmultiple size");
    errno = 0;
    Check(!__alloc_token_aligned_alloc(0, 128, 0) && errno == EINVAL,
          "bootstrap C allocation rejects zero alignment");
    errno = 0;
    Check(!__alloc_token_aligned_alloc(3, 129, 0) && errno == EINVAL,
          "bootstrap C allocation rejects invalid alignment");
  }
  std::atomic<uint32_t> legacy_flag{0};
  std::atomic<int> legacy_result{-1};
  std::thread legacy_waiter([&] {
    while (legacy_flag.load() == 0) {
      int result = chromium_legacy::LegacyAtomicWait<4>(&legacy_flag, 0,
                                                        1000000000, true);
      legacy_result.store(result);
      if (result != 0) {
        return;
      }
    }
  });
  std::this_thread::sleep_for(milliseconds(20));
  legacy_flag.store(1);
  Check(chromium_legacy::LegacyAtomicNotify(&legacy_flag) == 0,
        "legacy atomic notification");
  legacy_waiter.join();
  Check(legacy_result.load() == 0,
        "legacy atomic wait avoids lost notifications");
  std::atomic<uint64_t> legacy_wide{0};
  Check(chromium_legacy::LegacyAtomicWait<8>(&legacy_wide, 0, 10000000, true) ==
            ETIMEDOUT,
        "legacy 64-bit wait timeout");
  legacy_wide.store(1);
  Check(chromium_legacy::LegacyAtomicWait<8>(&legacy_wide, 0, 0, false) == 0,
        "legacy changed predicate returns immediately");

  struct alignas(2048) CollidingWaiters {
    std::atomic<uint32_t> first{0};
    std::array<char, 2048 - sizeof(std::atomic<uint32_t>)> padding{};
    std::atomic<uint32_t> second{0};
  };
  auto colliding = std::make_unique<CollidingWaiters>();
  Check(&chromium_legacy::internal::WaitBucket(&colliding->first) ==
            &chromium_legacy::internal::WaitBucket(&colliding->second),
        "atomic test addresses share one wait bucket");
  std::atomic<int> waiting{0};
  std::atomic<int> timed_out{0};
  auto wait_for_value = [&](std::atomic<uint32_t>& value) {
    waiting.fetch_add(1);
    while (value.load() == 0) {
      if (chromium_legacy::LegacyAtomicWait<4>(&value, 0, 1000000000, true) !=
          0) {
        timed_out.fetch_add(1);
        return;
      }
    }
  };
  std::thread first_waiter([&] { wait_for_value(colliding->first); });
  std::thread second_waiter([&] { wait_for_value(colliding->second); });
  while (waiting.load() != 2) {
    std::this_thread::yield();
  }
  colliding->first.store(1);
  chromium_legacy::LegacyAtomicNotify(&colliding->first);
  first_waiter.join();
  colliding->second.store(1);
  chromium_legacy::LegacyAtomicNotify(&colliding->second);
  second_waiter.join();
  Check(timed_out.load() == 0,
        "colliding atomic addresses cannot lose notifications");

  std::atomic<int> flag{0};
  std::thread notifier([&flag] {
    std::this_thread::sleep_for(milliseconds(20));
    flag.store(1);
    flag.notify_all();
  });
  flag.wait(0);
  notifier.join();
  Check(flag.load() == 1, "atomic wait and notification");
  std::array<uint8_t, 1024> random{}, other{};
  Check(RAND_bytes(random.data(), random.size()) == 1 &&
            RAND_bytes(other.data(), other.size()) == 1 && random != other,
        "current BoringSSL system entropy");
  SSL_CTX* tls = SSL_CTX_new(TLS_method());
  Check(tls != nullptr, "current TLS context initialization");
  SSL_CTX_free(tls);

  std::mutex mutex;
  std::condition_variable condition;
  bool ready = false;
  std::thread producer([&] {
    std::lock_guard lock(mutex);
    ready = true;
    condition.notify_one();
  });
  {
    std::unique_lock lock(mutex);
    Check(condition.wait_for(lock, seconds(2), [&] { return ready; }),
          "condition variable");
  }
  producer.join();

  namespace fs = std::filesystem;
  std::error_code error;
  auto root = fs::temp_directory_path(error) /
              ("chromium-legacy-runtime-" + std::to_string(getpid()) + "-" +
               std::to_string(steady_clock::now().time_since_epoch().count()));
  Check(!error && fs::create_directory(root, error), "filesystem directory");
  if (error) {
    return 2;
  }
  auto child = root / "nested";
  Check(fs::create_directory(child, error), "nested directory");
  auto file = child / "entry";
  {
    std::ofstream stream(file);
    stream << "current libc++";
    Check(stream.good(), "file stream");
  }
  auto desired = fs::file_time_type::clock::now() - hours(1);
  fs::last_write_time(file, desired, error);
  Check(!error, "set filesystem time");
  auto actual = fs::last_write_time(file, error);
  auto difference = actual > desired ? actual - desired : desired - actual;
  Check(!error && difference < milliseconds(1), "filesystem time roundtrip");
  fs::permissions(file, fs::perms::owner_read | fs::perms::owner_write,
                  fs::perm_options::replace, error);
  Check(!error, "file permissions");
  auto cwd_before = fs::current_path(error);
  auto anchor = root / "anchor";
  auto moved = root / "moved";
  auto outside = root / "outside";
  Check(fs::create_directory(anchor, error) &&
            fs::create_directory(outside, error),
        "create descriptor test directories");
  {
    std::ofstream stream(anchor / "entry");
    stream << "anchored";
  }
  {
    std::ofstream stream(outside / "entry");
    stream << "outside";
  }
  int directory = ::open(anchor.c_str(), O_RDONLY | O_DIRECTORY);
  Check(directory >= 0, "open directory anchor");
  fs::rename(anchor, moved, error);
  fs::create_directory_symlink(outside, anchor, error);
  struct stat identity{}, child_identity{};
  Check(!error && ::stat((moved / "entry").c_str(), &identity) == 0 &&
            chromium_legacy::LegacyFstatAt(directory, "entry", &child_identity,
                                           0) == 0 &&
            identity.st_ino == child_identity.st_ino,
        "legacy relative metadata preserves renamed directory identity");
  int opened =
      chromium_legacy::LegacyOpenAt(directory, "entry", O_RDWR | O_NOFOLLOW);
  Check(opened >= 0 && ::fstat(opened, &child_identity) == 0 &&
            identity.st_ino == child_identity.st_ino,
        "legacy relative open cannot follow the replacement path");
  if (opened >= 0) {
    timespec omitted{0, UTIME_OMIT};
    timespec modified{1700000000, 123456789};
    struct stat after{};
    Check(ChromiumLegacyRustFutimens(opened, &omitted, &modified) == 0 &&
              ::fstat(opened, &after) == 0 &&
              after.st_mtimespec.tv_sec == modified.tv_sec,
          "Rust adapter updates descriptor timestamps");
    Check(after.st_atimespec.tv_sec == child_identity.st_atimespec.tv_sec &&
              after.st_atimespec.tv_nsec == child_identity.st_atimespec.tv_nsec,
          "Rust adapter atomically preserves omitted access time");
    timespec now{0, UTIME_NOW};
    Check(ChromiumLegacyRustFutimens(opened, &now, &now) == 0 &&
              ::fstat(opened, &after) == 0 &&
              after.st_atimespec.tv_sec == after.st_mtimespec.tv_sec &&
              after.st_atimespec.tv_nsec == after.st_mtimespec.tv_nsec,
          "UTIME_NOW uses one timestamp for both attributes");
    ::close(opened);
  }
  Check(chromium_legacy::LegacyMkdirAt(directory, "child", 0700) == 0 &&
            fs::exists(moved / "child") && !fs::exists(outside / "child"),
        "legacy relative directory creation stays anchored");
  pid_t spawned_pid = -1;
  std::array<char, 8> shell_name{"/bin/sh"};
  std::array<char, 3> shell_option{"-c"};
  std::array<char, 40> shell_command{"test -f entry && test ! -L entry"};
  std::array<char*, 4> arguments{shell_name.data(), shell_option.data(),
                                 shell_command.data(), nullptr};
  std::array<char*, 1> environment{nullptr};
  int spawn_result = chromium_legacy::internal::RelativeFileOperation(
      directory, ".",
      [&](const char*) {
        return posix_spawn(&spawned_pid, shell_name.data(), nullptr, nullptr,
                           arguments.data(), environment.data());
      },
      -1);
  int child_status = -1;
  Check(spawn_result == 0 &&
            waitpid(spawned_pid, &child_status, 0) == spawned_pid &&
            WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0,
        "legacy spawn inherits the worker directory after rename");

  DIR* stream = chromium_legacy::LegacyFdOpenDir(directory);
  Check(stream != nullptr, "legacy directory stream transfer");
  if (stream) {
    Check(chromium_legacy::LegacyUnlinkAt(dirfd(stream), "entry", 0) == 0 &&
              fs::exists(outside / "entry"),
          "legacy relative removal preserves outside file");
    closedir(stream);
  } else if (directory >= 0) {
    close(directory);
  }
  Check(chromium_legacy::LegacyOpenAt(-1, "entry", O_RDONLY) == -1 &&
            errno == EBADF,
        "invalid directory descriptor is rejected");
  Check(fs::current_path(error) == cwd_before && !error,
        "legacy relative I/O never changes the caller cwd");
  fs::remove_all(anchor, error);
  fs::remove_all(moved, error);
  fs::remove_all(outside, error);

  Check(fs::remove_all(root, error) == 3 && !error,
        "filesystem recursive removal");
  std::printf("%d C++ runtime checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
