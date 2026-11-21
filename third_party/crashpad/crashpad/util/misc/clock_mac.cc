// Copyright 2014 The Crashpad Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "util/misc/clock.h"

#include <time.h>

#include "base/check.h"
#include "legacy/apple/clock.h"

namespace crashpad {

uint64_t ClockMonotonicNanoseconds() {
  if (__builtin_available(macOS 10.12, *)) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  }
  timespec now;
  CHECK(chromium_legacy::LegacyMonotonic(&now) == 0);
  return static_cast<uint64_t>(now.tv_sec) * 1000000000 + static_cast<uint64_t>(now.tv_nsec);
}

}  // namespace crashpad
