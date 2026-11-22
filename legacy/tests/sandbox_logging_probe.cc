// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <errno.h>
#include <string.h>

#include <iostream>
#include <string>
#include <string_view>

#include "base/compiler_specific.h"
#include "sandbox/mac/sandbox_logging.h"

// Inspect the original annotation that Crashpad reads, without adding an API
// or linking the sandbox logger against Base.
#include "sandbox/mac/sandbox_crash_message.cc"

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, std::string_view label) {
  ++checks;
  if (!value) {
    ++failures;
    std::cerr << "FAILED: " << label << '\n';
  }
}
std::string_view Message() {
  if (!annotation.message) {
    return {};
  }
  // SetCrashMessage owns this NUL-terminated string for the process lifetime.
  return UNSAFE_TODO(std::string_view(annotation.message));
}
}  // namespace

int main() {
  sandbox::crash_message::SetCrashMessage("sentinel");
  sandbox::logging::Info("informational %d", 7);
  Check(Message() == "sentinel",
        "informational logging preserves crash metadata");
  sandbox::logging::Warning("warning %% literal");
  Check(Message() == "sentinel", "warnings preserve crash metadata");
  sandbox::logging::Error("value=%d text=%s", 42, "marker");
  Check(Message() == "value=42 text=marker",
        "error formatting retains arguments");
  sandbox::logging::Error("literal %%n %%s");
  Check(Message() == "literal %n %s",
        "formatted percent signs remain literal log data");

  const std::string expected = std::string("open: ") + strerror(ENOENT);
  errno = ENOENT;
  sandbox::logging::PError("open");
  Check(Message() == expected,
        "errno text is captured before logging changes errno");

  const std::string oversized(5000, 'x');
  sandbox::logging::Error("%s", oversized.c_str());
  Check(Message().size() == 4095,
        "oversized errors retain the bounded message");
  Check(
      !Message().empty() && Message().front() == 'x' && Message().back() == 'x',
      "truncated error content remains intact");
  sandbox::logging::Info("finished");
  Check(Message().size() == 4095,
        "later logs preserve the owned crash-message copy");
  std::cout << checks << " sandbox logging checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
