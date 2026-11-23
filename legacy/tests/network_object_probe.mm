// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include <cstring>

#include "legacy/apple/scoped_network.h"

int main() {
  int checks = 0;
  int failures = 0;
  auto check = [&](bool ok, const char* name) {
    ++checks;
    if (!ok) {
      ++failures;
      std::fprintf(stderr, "FAIL: %s\n", name);
    }
  };
  @autoreleasepool {
    using Endpoint = chromium_legacy::ScopedNetworkObject<nw_endpoint_t>;
    Endpoint empty;
    check(!empty && empty.get() == nullptr,
          "empty ownership needs no framework");
    Endpoint empty_copy(empty);
    check(!empty_copy, "empty copies remain empty");
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    if (@available(macOS 10.14, *)) {
      // Constructing an endpoint is descriptive: no connection or discovery
      // request is started and no permission is requested.
      Endpoint original(nw_endpoint_create_host("127.0.0.1", "12345"));
      check(static_cast<bool>(original), "adopt a real create result");
      nw_endpoint_t identity = original.get();
      Endpoint copy(original);
      original.reset();
      check(copy.get() == identity, "copy owns the endpoint after owner reset");
      check(std::strcmp(nw_endpoint_get_hostname(copy.get()), "127.0.0.1") == 0,
            "copied endpoint remains usable");
      Endpoint assigned;
      assigned = copy;
      copy.reset();
      check(assigned.get() == identity, "copy assignment retains ownership");
      Endpoint moved(static_cast<Endpoint&&>(assigned));
      check(!assigned && moved.get() == identity, "move clears its source");
      Endpoint move_assigned(nw_endpoint_create_host("127.0.0.2", "12346"));
      move_assigned = static_cast<Endpoint&&>(moved);
      check(!moved && move_assigned.get() == identity,
            "move assignment replaces an owned endpoint");
      auto delayed = [move_assigned] {
        return std::strcmp(nw_endpoint_get_hostname(move_assigned.get()),
                           "127.0.0.1") == 0;
      };
      move_assigned.reset();
      check(delayed(), "captured copy survives the scheduling owner's reset");
      Endpoint replacement(nw_endpoint_create_host("127.0.0.3", "12347"));
      replacement.reset(nw_endpoint_create_host("127.0.0.4", "12348"));
      check(std::strcmp(nw_endpoint_get_hostname(replacement.get()),
                        "127.0.0.4") == 0,
            "reset adopts a replacement create result");
      replacement.reset();
      check(!replacement, "reset clears the final reference");
    }
#endif
  }
  std::printf("%d Network object ownership checks, %d failures\n", checks,
              failures);
  return failures ? 1 : 0;
}
