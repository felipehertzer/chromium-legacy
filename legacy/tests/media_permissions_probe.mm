// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <iostream>
#include <string_view>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "chrome/browser/permissions/system/system_media_capture_permissions_mac.mm"

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
struct CompletionState {
  scoped_refptr<base::SequencedTaskRunner> runner =
      base::SequencedTaskRunner::GetCurrentDefault();
  bool returned = false;
  int callbacks = 0;
  void Complete() {
    ++callbacks;
    Check(returned, "system permission callback remains asynchronous");
    Check(runner->RunsTasksInCurrentSequence(),
          "system permission callback returns to the requesting sequence");
  }
};
class API_AVAILABLE(macos(10.14)) ProbeMediaAuthorization
    : public system_permission_settings::MediaAuthorizationWrapper {
 public:
  AVAuthorizationStatus status = AVAuthorizationStatusNotDetermined;
  int queries = 0;
  int requests = 0;
  AVAuthorizationStatus AuthorizationStatusForMediaType(NSString*) override {
    ++queries;
    return status;
  }
  void RequestAccessForMediaType(NSString* type,
                                 base::OnceClosure callback) override {
    ++requests;
    Check([type isEqual:AVMediaTypeAudio] || [type isEqual:AVMediaTypeVideo],
          "system permission request retains its actual media type");
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, std::move(callback));
  }
};
API_AVAILABLE(macos(10.14))
void NativePolicyChecks() {
  using namespace system_permission_settings;
  ProbeMediaAuthorization authorization;
  SetMediaAuthorizationWrapperForTesting(&authorization);
  struct Case {
    AVAuthorizationStatus status;
    SystemPermission expected;
  };
  const Case cases[] = {
      {AVAuthorizationStatusNotDetermined, SystemPermission::kNotDetermined},
      {AVAuthorizationStatusRestricted, SystemPermission::kRestricted},
      {AVAuthorizationStatusDenied, SystemPermission::kDenied},
      {AVAuthorizationStatusAuthorized, SystemPermission::kAllowed},
  };
  for (const Case& value : cases) {
    authorization.status = value.status;
    Check(CheckSystemAudioCapturePermission() == value.expected,
          "microphone preserves the native authorization decision");
    Check(CheckSystemVideoCapturePermission() == value.expected,
          "camera preserves the native authorization decision");
  }
  Check(authorization.queries == 8,
        "supported OS always consults the native authorization wrapper");
  CompletionState state;
  RequestSystemAudioCapturePermission(
      base::BindOnce(&CompletionState::Complete, base::Unretained(&state)));
  RequestSystemVideoCapturePermission(
      base::BindOnce(&CompletionState::Complete, base::Unretained(&state)));
  Check(state.callbacks == 0, "callbacks do not run before requests return");
  state.returned = true;
  base::RunLoop().RunUntilIdle();
  Check(state.callbacks == 2, "both requests complete exactly once");
  Check(authorization.requests == 2,
        "supported OS requests both permissions through its native wrapper");
  SetMediaAuthorizationWrapperForTesting(nullptr);
}
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::SingleThreadTaskExecutor executor;
  @autoreleasepool {
    if (@available(macOS 10.14, *)) {
      NativePolicyChecks();
    } else {
      using namespace system_permission_settings;
      Check(
          CheckSystemAudioCapturePermission() == SystemPermission::kAllowed &&
              CheckSystemVideoCapturePermission() == SystemPermission::kAllowed,
          "pre-Mojave OS has no app-level media authorization gate");
      CompletionState state;
      RequestSystemAudioCapturePermission(
          base::BindOnce(&CompletionState::Complete, base::Unretained(&state)));
      state.returned = true;
      base::RunLoop().RunUntilIdle();
      Check(state.callbacks == 1, "pre-Mojave callback completes exactly once");
    }
  }
  std::cout << checks << " media permission checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
