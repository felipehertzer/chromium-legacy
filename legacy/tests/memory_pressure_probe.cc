// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstring>
#include <iostream>
#include <string_view>
#include "base/apple/scoped_mach_port.h"
#include "base/apple/scoped_nsautorelease_pool.h"
#include "base/apple/vm_statistics.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ref.h"
#include "base/process/process_metrics.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "components/memory_pressure/free_memory_pressure_evaluator.h"
#include "components/memory_pressure/system_memory_pressure_evaluator_mac.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, std::string_view message) {
  ++checks;
  if (!success) {
    ++failures;
    std::cerr << "FAIL: " << message << "\n";
  }
}
struct VoteState {
  int votes = 0;
  base::MemoryPressureLevel level = base::MEMORY_PRESSURE_LEVEL_NONE;
};
class RecordingVoter : public memory_pressure::MemoryPressureVoter {
 public:
  explicit RecordingVoter(VoteState& state) : state_(state) {}
  void SetVote(base::MemoryPressureLevel level) override {
    ++state_->votes;
    state_->level = level;
  }
  void SetVote(base::MemoryPressureLevel level, bool) override {
    SetVote(level);
  }

 private:
  const base::raw_ref<VoteState> state_;
};
class ProbeFreeEvaluator : public memory_pressure::FreeMemoryPressureEvaluator {
 public:
  explicit ProbeFreeEvaluator(VoteState& state)
      : FreeMemoryPressureEvaluator(std::make_unique<RecordingVoter>(state)) {
    StopObserving();
  }
};
void WaitForSampler() {
  base::RunLoop loop;
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, loop.QuitClosure(), base::Seconds(3));
  loop.Run();
}
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::apple::ScopedNSAutoreleasePool pool;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  base::SingleThreadTaskExecutor executor;
  vm_statistics64_data_t statistics;
  std::memset(&statistics, 0xa5, sizeof(statistics));
  statistics.free_count = 123;
  Check(base::apple::NormalizeVMStatisticsReply(statistics,
                                                HOST_VM_INFO64_REV0_COUNT),
        "rev0 memory response is accepted");
  Check(statistics.free_count == 123, "legacy native counters remain intact");
  Check(statistics.compressor_page_count == 0 &&
            statistics.external_page_count == 0 &&
            statistics.swapped_count == 0,
        "unreported compressor/file-backed/swap counters are cleared");
  statistics.external_page_count = 17;
  statistics.compressor_page_count = 19;
  statistics.swapped_count = 23;
  Check(base::apple::NormalizeVMStatisticsReply(statistics,
                                                HOST_VM_INFO64_REV1_COUNT),
        "rev1 memory response is accepted");
  Check(statistics.external_page_count == 17 &&
            statistics.compressor_page_count == 19 &&
            statistics.swapped_count == 0,
        "rev1 counters survive while absent rev2 data is cleared");
  Check(!base::apple::NormalizeVMStatisticsReply(statistics,
                                                 HOST_VM_INFO64_REV0_COUNT - 1),
        "truncated mandatory response is rejected");
  Check(!base::apple::NormalizeVMStatisticsReply(statistics,
                                                 HOST_VM_INFO64_COUNT + 1),
        "oversized response count is rejected");
  // Ask the real kernel for the original ABI view, without interposing an API.
  base::apple::ScopedMachSendRight host(mach_host_self());
  std::memset(&statistics, 0xa5, sizeof(statistics));
  mach_msg_type_number_t count = HOST_VM_INFO64_REV0_COUNT;
  const kern_return_t result =
      host_statistics64(host.get(), HOST_VM_INFO64,
                        reinterpret_cast<host_info64_t>(&statistics), &count);
  Check(result == KERN_SUCCESS && count == HOST_VM_INFO64_REV0_COUNT,
        "real kernel supports its legacy memory-statistics view");
  Check(base::apple::NormalizeVMStatisticsReply(statistics, count) &&
            statistics.compressor_page_count == 0,
        "real legacy response is normalized without reading its absent tail");
  base::SystemMemoryInfo memory;
  Check(base::GetSystemMemoryInfo(&memory) && memory.total.is_positive() &&
            memory.free <= memory.total,
        "production memory query reports bounded physical counters");
  {
    VoteState state;
    ProbeFreeEvaluator evaluator(state);
    struct Case {
      uint64_t free_mib;
      base::MemoryPressureLevel expected;
    };
    const Case cases[] = {{151, base::MEMORY_PRESSURE_LEVEL_NONE},
                          {150, base::MEMORY_PRESSURE_LEVEL_MODERATE},
                          {51, base::MEMORY_PRESSURE_LEVEL_MODERATE},
                          {50, base::MEMORY_PRESSURE_LEVEL_CRITICAL},
                          {0, base::MEMORY_PRESSURE_LEVEL_CRITICAL},
                          {151, base::MEMORY_PRESSURE_LEVEL_NONE}};
    int expected_votes = 0;
    for (const Case& value : cases) {
      base::AvailableMemoryMonitor::MemorySample sample;
      sample.timestamp = base::TimeTicks::Now();
      sample.total_physical_bytes = base::GiB(4);
      sample.available_physical_bytes = base::GiB(2);
      sample.free_physical_bytes = base::MiB(value.free_mib);
      evaluator.OnAvailableMemoryUpdated(sample);
      ++expected_votes;
      Check(evaluator.current_vote() == value.expected &&
                state.level == value.expected && state.votes == expected_votes,
            "current free-memory policy, boundaries and recovery reach the "
            "voter");
    }
  }
  Check(!base::AvailableMemoryMonitor::Get()->GetLastSample(),
        "stopped fixture leaves no active sampler or stale sample");
  {
    memory_pressure::MultiSourceMemoryPressureMonitor monitor;
    auto evaluator = memory_pressure::SystemMemoryPressureEvaluator::
        CreateDefaultSystemEvaluator(&monitor);
    Check(evaluator != nullptr,
          "actual platform factory constructs an evaluator");
    WaitForSampler();
    const bool sampled =
        base::AvailableMemoryMonitor::Get()->GetLastSample().has_value();
    Check(sampled ==
              !memory_pressure::mac::NativePressureNotificationsAvailable(),
          "factory runs the polling monitor exactly when native notifications "
          "are unavailable");
    evaluator.reset();
    Check(!base::AvailableMemoryMonitor::Get()->GetLastSample(),
          "evaluator destruction stops sampling and clears cached state");
  }
  std::cout << checks << " memory pressure checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
