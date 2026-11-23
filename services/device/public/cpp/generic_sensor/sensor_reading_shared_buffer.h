// Copyright 2023 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef SERVICES_DEVICE_PUBLIC_CPP_GENERIC_SENSOR_SENSOR_READING_SHARED_BUFFER_H_
#define SERVICES_DEVICE_PUBLIC_CPP_GENERIC_SENSOR_SENSOR_READING_SHARED_BUFFER_H_

#include <array>
#include <atomic>
#include <bit>

#include "base/containers/span.h"
#include "device/base/synchronization/one_writer_seqlock.h"
#include "services/device/public/cpp/generic_sensor/sensor_reading.h"
#include "services/device/public/mojom/sensor.mojom-shared.h"

namespace device {

// This structure represents sensor reading buffer: sensor reading and seqlock
// for synchronization.
//
struct SensorReadingSharedBuffer {
  SensorReadingField<OneWriterSeqLock> seqlock;
  SensorReading reading;
};

// The existing seqlock validates each complete snapshot. Lion builds copy the
// representation using lock-free byte atomics on both sides, avoiding generic
// aggregate libatomic calls and keeping loads compatible with read-only maps.
inline SensorReading LoadSensorReading(const SensorReading& source) {
#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && \
    __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 1080
  static_assert(std::atomic_ref<uint8_t>::is_always_lock_free);
  static_assert(std::atomic_ref<uint8_t>::required_alignment == 1);
  const auto input =
      base::byte_span_from_ref(base::allow_nonunique_obj, source);
  std::array<uint8_t, sizeof(SensorReading)> bytes;
  auto output = base::span(bytes);
  for (size_t i = 0; i < input.size(); ++i) {
    output[i] = std::atomic_ref(const_cast<uint8_t&>(input[i]))
                    .load(std::memory_order_relaxed);
  }
  return std::bit_cast<SensorReading>(bytes);
#else
  // TODO(https://github.com/llvm/llvm-project/issues/118378): Remove
  // const_cast.
  return std::atomic_ref(const_cast<SensorReading&>(source))
      .load(std::memory_order_relaxed);
#endif
}

inline void StoreSensorReading(SensorReading& destination,
                               const SensorReading& source) {
#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && \
    __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 1080
  auto output =
      base::byte_span_from_ref(base::allow_nonunique_obj, destination);
  const auto bytes =
      std::bit_cast<std::array<uint8_t, sizeof(SensorReading)>>(source);
  const auto input = base::span(bytes);
  for (size_t i = 0; i < output.size(); ++i) {
    std::atomic_ref(output[i]).store(input[i], std::memory_order_relaxed);
  }
#else
  std::atomic_ref(destination).store(source, std::memory_order_relaxed);
#endif
}

// Gets the shared reading buffer offset for the given sensor type.
uint64_t GetSensorReadingSharedBufferOffset(mojom::SensorType type);

// SensorReadingSharedBuffer is used in shared memory, so it must be trivially
// copyable.
static_assert(std::is_trivially_copyable_v<SensorReadingSharedBuffer>);

}  // namespace device

#endif  // SERVICES_DEVICE_PUBLIC_CPP_GENERIC_SENSOR_SENSOR_READING_SHARED_BUFFER_H_
