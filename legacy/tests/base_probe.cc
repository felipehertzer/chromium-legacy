// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include <iostream>
#include <string>
#include <string_view>
#include <thread>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "base/process/launch.h"
#include "base/process/process.h"
#include "base/synchronization/waitable_event.h"
#include "base/system/sys_info.h"
#include "base/threading/platform_thread.h"
#include "base/time/time.h"
#include "crypto/unexportable_key.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, std::string_view description) {
  ++checks;
  if (!success) {
    ++failures;
    std::cerr << "FAIL: " << description << "\n";
  }
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  int32_t major = 0, minor = 0, patch = 0;
  base::SysInfo::OperatingSystemVersionNumbers(&major, &minor, &patch);
  Check(major >= 10 && minor >= 0 && patch >= 0, "system version");
  auto start = base::TimeTicks::Now();
  base::PlatformThread::Sleep(base::Milliseconds(20));
  Check(base::TimeTicks::Now() - start >= base::Milliseconds(10),
        "monotonic process clock");
  Check(!base::TimeTicks::LowResolutionNow().is_null(), "low resolution clock");
  Check(!base::ThreadTicks::Now().is_null(), "thread CPU clock");
  base::WaitableEvent event;
  std::thread signaler([&] { event.Signal(); });
  Check(event.TimedWait(base::Seconds(5)), "Mach-backed event notification");
  signaler.join();

  base::ScopedTempDir temp;
  if (!temp.CreateUniqueTempDir()) {
    Check(false, "create private test directory");
    return 1;
  }
  const auto source = temp.GetPath().AppendASCII("source");
  const auto nested = source.AppendASCII("nested");
  const auto target = temp.GetPath().AppendASCII("target");
  const auto outside = temp.GetPath().AppendASCII("outside");
  Check(base::CreateDirectory(nested) && base::CreateDirectory(outside),
        "directory creation");
  Check(base::WriteFile(nested.AppendASCII("entry"), "payload"), "file write");
  Check(base::WriteFile(outside.AppendASCII("keep"), "outside"),
        "outside sentinel");
  Check(base::CreateSymbolicLink(outside, source.AppendASCII("link")),
        "directory symlink creation");
  Check(base::CopyDirectoryNoFollow(source, target, true),
        "directory copy without following symlinks");
  std::string contents;
  Check(base::ReadFileToString(target.AppendASCII("nested/entry"), &contents) &&
            contents == "payload",
        "copied contents");
  Check(!base::PathExists(target.AppendASCII("link/keep")),
        "directory copy excludes symlink targets");
  Check(base::DeletePathRecursively(source) &&
            base::PathExists(outside.AppendASCII("keep")),
        "recursive deletion preserves outside symlink target");

  base::LaunchOptions options;
  options.current_directory = target.AppendASCII("nested");
  base::CommandLine command({"/bin/sh", "-c", "test -f entry"});
  base::Process process = base::LaunchProcess(command, options);
  int exit_code = -1;
  Check(process.IsValid() && process.WaitForExit(&exit_code) && exit_code == 0,
        "process launch with a requested directory");
  Check(!crypto::GetUnexportableKeyProvider(
            {.keychain_access_group = "org.chromium.legacy.unentitled-probe"}),
        "hardware-backed keys require the actual entitlement");
  Check(temp.Delete(), "private test directory cleanup");
  std::printf("%d Base integration checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
