// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef BASE_APPLE_VM_STATISTICS_H_
#define BASE_APPLE_VM_STATISTICS_H_
#include <mach/host_info.h>
#include <mach/vm_statistics.h>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include "base/containers/span.h"

namespace base::apple {
// Mach reports how many integer words it initialized. Older kernels return
// rev0 without compressor/file-backed counters; never consume an unfilled tail.
inline bool NormalizeVMStatisticsReply(vm_statistics64_data_t& statistics,
                                       mach_msg_type_number_t count) {
  if (count < HOST_VM_INFO64_REV0_COUNT || count > HOST_VM_INFO64_COUNT)
    return false;
  auto bytes = base::byte_span_from_ref(statistics);
  const size_t initialized = size_t{count} * sizeof(integer_t);
  std::ranges::fill(bytes.subspan(initialized), uint8_t{0});
  return true;
}
}  // namespace base::apple
#endif  // BASE_APPLE_VM_STATISTICS_H_
