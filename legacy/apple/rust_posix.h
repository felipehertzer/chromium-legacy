// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_RUST_POSIX_H_
#define LEGACY_APPLE_RUST_POSIX_H_
#include <dirent.h>
#include <stddef.h>
#include <sys/stat.h>
#include <time.h>
extern "C" {
int ChromiumLegacyRustClockGettime(clockid_t, timespec*);
void ChromiumLegacyRustRandom(unsigned char*, size_t);
int ChromiumLegacyRustOpenAt(int, const char*, int, mode_t);
int ChromiumLegacyRustFstatAt(int, const char*, struct stat*, int);
int ChromiumLegacyRustMkdirAt(int, const char*, mode_t);
int ChromiumLegacyRustUnlinkAt(int, const char*, int);
DIR* ChromiumLegacyRustFdOpenDir(int);
int ChromiumLegacyRustDirFd(DIR*);
int ChromiumLegacyRustRenameAt(int, const char*, int, const char*);
int ChromiumLegacyRustFchmodAt(int, const char*, mode_t, int);
int ChromiumLegacyRustLinkAt(int, const char*, int, const char*, int);
int ChromiumLegacyRustFutimens(int, const timespec*, const timespec*);
int ChromiumLegacyRustUtimensAt(int,
                                const char*,
                                const timespec*,
                                const timespec*,
                                int);
}
#endif  // LEGACY_APPLE_RUST_POSIX_H_
