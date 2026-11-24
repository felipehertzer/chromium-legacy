// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

#include "net/base/apple/guarded_fd.h"

namespace {
int checks = 0;
void Check(bool condition, const char* message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s (errno=%d)\n", message, errno);
    exit(1);
  }
  ++checks;
}
}  // namespace

int main() {
  const bool guarded = net::internal::FileDescriptorGuardsAvailable();
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  Check(!guarded, "forced old-system path has no guard APIs");
#endif
  for (int iteration = 0; iteration < 32; ++iteration) {
    int pair[2];
    Check(socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) == 0,
          "create owned socket pair");
    const guardid_t guard = reinterpret_cast<guardid_t>(&pair);
    if (guarded) {
      Check(change_fdguard_np(pair[0], nullptr, 0, &guard,
                              GUARD_CLOSE | GUARD_DUP, nullptr) == 0,
            "install descriptor ownership guard");
    }
    const char sent = 'L';
    char received = 0;
    Check(write(pair[0], &sent, 1) == 1, "guarded or ordinary write succeeds");
    Check(read(pair[1], &received, 1) == 1 && received == sent,
          "socket peer receives payload");
    if (guarded && iteration % 2 == 0) {
      Check(change_fdguard_np(pair[0], &guard, GUARD_CLOSE | GUARD_DUP, nullptr,
                              0, nullptr) == 0,
            "remove guard before ordinary file owner closes");
      Check(close(pair[0]) == 0, "ordinary owner closes unguarded file");
    } else if (guarded) {
      Check(guarded_close_np(pair[0], &guard) == 0,
            "socket closes with its guard");
    } else {
      Check(close(pair[0]) == 0, "old-system owner closes ordinary descriptor");
    }
    Check(fcntl(pair[0], F_GETFD) == -1 && errno == EBADF,
          "closed descriptor is not leaked");
    Check(fcntl(pair[1], F_GETFD) >= 0,
          "peer descriptor remains owned and open");
    Check(close(pair[1]) == 0, "close owned peer");
  }
  printf("guarded-fd: %d checks passed (guards=%d)\n", checks, guarded);
}
