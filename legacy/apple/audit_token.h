// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_AUDIT_TOKEN_H_
#define LEGACY_APPLE_AUDIT_TOKEN_H_
#include <bsm/libbsm.h>

// OpenBSM-21 exports this decoder on Lion. Current SDKs annotate the public
// declaration 10.8; this alias retains the older, verified ABI. Parse through
// the OS implementation rather than assuming the token's internal layout.
extern "C" void ChromiumLegacyAuditTokenToAu32(
    audit_token_t,
    uid_t*,
    uid_t*,
    gid_t*,
    uid_t*,
    gid_t*,
    pid_t*,
    au_asid_t*,
    au_tid_t*) __asm("_audit_token_to_au32");
namespace chromium_legacy {
inline pid_t AuditTokenPid(audit_token_t token) {
  if (__builtin_available(macOS 10.8, *)) {
    return audit_token_to_pid(token);
  }
  pid_t pid = -1;
  ChromiumLegacyAuditTokenToAu32(token, nullptr, nullptr, nullptr, nullptr,
                                 nullptr, &pid, nullptr, nullptr);
  return pid;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_AUDIT_TOKEN_H_
