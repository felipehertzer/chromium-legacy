// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include <iostream>
#include <string_view>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "base/timer/timer.h"
// Compile the actual implementation, including the native capability gate.
#include "device/fido/mac/touch_id_context.mm"

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
struct AvailabilityState {
  base::RunLoop loop;
  scoped_refptr<base::SequencedTaskRunner> runner =
      base::SequencedTaskRunner::GetCurrentDefault();
  bool returned = false;
  bool available = true;
  int callbacks = 0;
  void Complete(bool result) {
    ++callbacks;
    available = result;
    Check(returned, "availability completion is asynchronous");
    Check(runner->RunsTasksInCurrentSequence(),
          "availability completion returns to its original sequence");
    loop.Quit();
  }
  void Timeout() {
    Check(false, "availability completion timed out");
    loop.Quit();
  }
  base::WeakPtrFactory<AvailabilityState> weak_factory{this};
};
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::SingleThreadTaskExecutor executor;
  base::ThreadPoolInstance::CreateAndStartWithDefaultParams(
      "LegacyFidoContext");
  @autoreleasepool {
    auto context = device::fido::mac::TouchIdContext::Create();
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    Check(!context, "unsupported native authenticator creates no context");
#else
    if (@available(macOS 10.12.2, *)) {
      Check(context != nullptr, "native context constructed on a supported OS");
      Check(context && context->authentication_context() != nil,
            "factory owns a real LAContext");
    } else {
      Check(!context, "older OS creates no native context");
    }
#endif
    context.reset();
    AvailabilityState state;
    base::OneShotTimer timeout;
    timeout.Start(FROM_HERE, base::Seconds(10),
                  base::BindOnce(&AvailabilityState::Timeout,
                                 state.weak_factory.GetWeakPtr()));
    device::fido::mac::AuthenticatorConfig config;
    // A standalone executable has no entitlement for this fictitious group.
    // No biometric prompt, key creation or credential-store query is made.
    config.keychain_access_group = "org.chromium.legacy.probe.invalid";
    device::fido::mac::TouchIdContext::TouchIdAvailable(
        config, base::BindOnce(&AvailabilityState::Complete,
                               state.weak_factory.GetWeakPtr()));
    state.returned = true;
    state.loop.Run();
    Check(state.callbacks == 1, "availability completes exactly once");
    Check(!state.available,
          "missing entitlement cannot advertise native credentials");
  }
  base::ThreadPoolInstance::Get()->Shutdown();
  std::printf("%d Fido context checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
