// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <crt_externs.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <bit>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
#include <string>
#include <string_view>

#include "base/at_exit.h"
#include "services/device/public/cpp/generic_sensor/sensor_reading_shared_buffer.h"
#include "services/device/public/cpp/generic_sensor/sensor_reading_shared_buffer_reader.h"

namespace {
constexpr int kWrites = 200000;
struct SharedState {
  device::SensorReadingSharedBuffer buffer;
  std::atomic<bool> start{false};
  std::atomic<bool> done{false};
};
static_assert(std::atomic<bool>::is_always_lock_free);
int checks = 0;
int failures = 0;
void Check(bool ok, std::string_view name) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << name << '\n';
  }
}
void Store(SharedState& state, const device::SensorReading& value) {
  state.buffer.seqlock.value().WriteBegin();
  device::StoreSensorReading(state.buffer.reading, value);
  state.buffer.seqlock.value().WriteEnd();
}
bool Consistent(const device::SensorReading& value) {
  const double timestamp = value.raw.timestamp.value();
  if (!std::isfinite(timestamp) || timestamp < 0 || timestamp > kWrites) {
    return false;
  }
  for (size_t i = 0; i < value.raw.values.size(); ++i) {
    if (value.raw.values[i].value() != timestamp * (i + 1)) {
      return false;
    }
  }
  return true;
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  if (argc == 3 && std::string_view(argv[1]) == "--writer") {
    int fd = std::atoi(argv[2]);
    void* mapping = mmap(nullptr, sizeof(SharedState), PROT_READ | PROT_WRITE,
                         MAP_SHARED, fd, 0);
    close(fd);
    if (mapping == MAP_FAILED) {
      return 2;
    }
    auto& state = *static_cast<SharedState*>(mapping);
    while (!state.start.load(std::memory_order_acquire)) {
      sched_yield();
    }
    for (int version = 1; version <= kWrites; ++version) {
      device::SensorReading value;
      value.raw.timestamp = static_cast<double>(version);
      for (size_t i = 0; i < value.raw.values.size(); ++i) {
        value.raw.values[i] = static_cast<double>(version * (i + 1));
      }
      Store(state, value);
      if (version % 1024 == 0) {
        sched_yield();
      }
    }
    state.done.store(true, std::memory_order_release);
    munmap(mapping, sizeof(SharedState));
    return 0;
  }

  // The descriptor is intentionally inherited only by this test's writer.
  char path[] = "/tmp/chromium-sensor-probe.XXXXXX";
  int fd = mkstemp(path);
  if (fd < 0) {
    return 1;
  }
  unlink(path);
  if (ftruncate(fd, sizeof(SharedState))) {
    close(fd);
    return 1;
  }
  void* writable = mmap(nullptr, sizeof(SharedState), PROT_READ | PROT_WRITE,
                        MAP_SHARED, fd, 0);
  void* read_only =
      mmap(nullptr, sizeof(SharedState), PROT_READ, MAP_SHARED, fd, 0);
  if (writable == MAP_FAILED || read_only == MAP_FAILED) {
    close(fd);
    return 1;
  }
  auto* state = new (writable) SharedState;
  const auto* reader = static_cast<const SharedState*>(read_only);
  device::SensorReading pattern;
  pattern.raw.timestamp = -0.0;
  pattern.raw.values[0] = std::numeric_limits<double>::infinity();
  pattern.raw.values[1] = std::bit_cast<double>(uint64_t{0x7ff8000000001234});
  pattern.raw.values[2] = -1.25;
  pattern.raw.values[3] = 42.0;
  Store(*state, pattern);
  device::SensorReading copied;
  Check(device::SensorReadingSharedBufferReader::GetReading(&reader->buffer,
                                                            &copied),
        "production reader accepts a read-only mapping");
  Check(std::bit_cast<std::array<uint8_t, sizeof(pattern)>>(pattern) ==
            std::bit_cast<std::array<uint8_t, sizeof(copied)>>(copied),
        "atomic transfer preserves floating-point bits including NaN payloads");
  Store(*state, device::SensorReading());
  Check(device::SensorReadingSharedBufferReader::GetReading(&reader->buffer,
                                                            &copied) &&
            Consistent(copied),
        "zero readings remain valid");

  if (fcntl(fd, F_SETFD, 0)) {
    return 1;
  }
  const std::string fd_text = std::to_string(fd);
  char* child_args[] = {argv[0], const_cast<char*>("--writer"),
                        const_cast<char*>(fd_text.c_str()), nullptr};
  pid_t child = -1;
  int status = posix_spawn(&child, argv[0], nullptr, nullptr, child_args,
                           *_NSGetEnviron());
  if (status) {
    munmap(read_only, sizeof(SharedState));
    munmap(writable, sizeof(SharedState));
    close(fd);
    return 1;
  }
  state->start.store(true, std::memory_order_release);
  size_t snapshots = 0;
  size_t intermediate = 0;
  bool coherent = true;
  bool timed_out = false;
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(15);
  while (!reader->done.load(std::memory_order_acquire) || snapshots < 10000) {
    if (device::SensorReadingSharedBufferReader::GetReading(&reader->buffer,
                                                            &copied)) {
      ++snapshots;
      coherent &= Consistent(copied);
      intermediate += copied.raw.timestamp.value() > 0 &&
                      copied.raw.timestamp.value() < kWrites;
    }
    if (std::chrono::steady_clock::now() > deadline) {
      timed_out = true;
      kill(child, SIGKILL);
      break;
    }
  }
  int child_status = 0;
  pid_t waited;
  do {
    waited = waitpid(child, &child_status, 0);
  } while (waited < 0 && errno == EINTR);
  Check(!timed_out && waited == child && WIFEXITED(child_status) &&
            WEXITSTATUS(child_status) == 0,
        "independent writer process completes");
  Check(coherent && snapshots >= 10000,
        "seqlock snapshots never accept torn multi-field readings under "
        "contention");
  Check(intermediate > 0,
        "reader observes intermediate versions while the writer is active");
  Check(device::SensorReadingSharedBufferReader::GetReading(&reader->buffer,
                                                            &copied) &&
            copied.raw.timestamp.value() == kWrites && Consistent(copied),
        "final complete reading is visible through the read-only mapping");
  munmap(read_only, sizeof(SharedState));
  state->~SharedState();
  munmap(writable, sizeof(SharedState));
  close(fd);
  std::cout << checks << " sensor sharing checks, " << snapshots
            << " snapshots, " << failures << " failures\n";
  return failures ? 1 : 0;
}
