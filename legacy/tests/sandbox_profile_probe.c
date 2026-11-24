// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Keep these declarations identical to sandbox/mac/seatbelt.cc. The test uses
// the system compiler and applies each real Chromium policy only to itself.
typedef struct sandbox_params_t sandbox_params_t;
typedef struct sandbox_profile_t sandbox_profile_t;
extern sandbox_params_t* sandbox_create_params(void);
extern int sandbox_set_param(sandbox_params_t*, const char*, const char*);
extern void sandbox_free_params(sandbox_params_t*);
extern sandbox_profile_t* sandbox_compile_string(const char*,
                                                 sandbox_params_t*,
                                                 char**);
extern int sandbox_apply(sandbox_profile_t*);
extern void sandbox_free_profile(sandbox_profile_t*);
extern void sandbox_free_error(char*);
extern int sandbox_check(pid_t, const char*, int, ...);

static unsigned checks;

static void Check(bool result, const char* operation) {
  if (!result) {
    fprintf(stderr, "FAIL: %s (errno=%d)\n", operation, errno);
    exit(1);
  }
  ++checks;
}

static void CheckDenied(const char* path, int flags) {
  errno = 0;
  int fd = open(path, flags, 0600);
  int saved_errno = errno;
  if (fd >= 0) {
    close(fd);
  }
  Check(fd == -1 && (saved_errno == EPERM || saved_errno == EACCES), path);
}

int main(int argc, char** argv) {
  if (argc < 4 || (argc - 4) % 2) {
    fprintf(stderr,
            "usage: probe PROFILE FIXTURES EXECUTABLE [KEY VALUE ...]\n");
    return 2;
  }
  FILE* source = fopen(argv[1], "rb");
  Check(source != NULL, "open profile");
  Check(fseek(source, 0, SEEK_END) == 0, "seek profile");
  long length = ftell(source);
  Check(length > 0 && length <= 16 * 1024 * 1024, "profile length");
  rewind(source);
  char* text = calloc((size_t)length + 1, 1);
  Check(text != NULL, "allocate profile");
  Check(fread(text, 1, (size_t)length, source) == (size_t)length,
        "read profile");
  fclose(source);

  char forbidden_read[PATH_MAX], forbidden_write[PATH_MAX], log[PATH_MAX];
  const char* names[] = {"forbidden-read", "forbidden-write", "log"};
  char* paths[] = {forbidden_read, forbidden_write, log};
  for (unsigned i = 0; i < 3; ++i) {
    int length_written =
        snprintf(paths[i], PATH_MAX, "%s/%s", argv[2], names[i]);
    Check(length_written > 0 && length_written < PATH_MAX, "fixture path");
  }
  int fd = open(forbidden_read, O_RDONLY);
  Check(fd >= 0, "fixture readable before sandbox");
  close(fd);
  Check(sandbox_check(getpid(), NULL, 0) == 0, "initially unsandboxed");

  sandbox_params_t* parameters = sandbox_create_params();
  Check(parameters != NULL, "create parameters");
  for (int i = 4; i < argc; i += 2) {
    Check(sandbox_set_param(parameters, argv[i], argv[i + 1]) == 0, argv[i]);
  }
  char* error = NULL;
  sandbox_profile_t* profile = sandbox_compile_string(text, parameters, &error);
  if (!profile && error) {
    fprintf(stderr, "%s\n", error);
  }
  if (error) {
    sandbox_free_error(error);
  }
  sandbox_free_params(parameters);
  free(text);
  Check(profile != NULL, "compile current profile");
  int applied = sandbox_apply(profile);
  sandbox_free_profile(profile);
  Check(applied == 0, "apply current profile");
  Check(sandbox_check(getpid(), NULL, 0) == 1, "sandbox active");

  fd = open(argv[3], O_RDONLY);
  Check(fd >= 0, "executable read allowed");
  close(fd);
  fd = open(log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  Check(fd >= 0, "configured log write allowed");
  Check(write(fd, "test", 4) == 4, "write configured log");
  close(fd);
  CheckDenied(forbidden_read, O_RDONLY);
  CheckDenied(forbidden_write, O_WRONLY | O_CREAT | O_EXCL);
  CheckDenied(log, O_RDONLY);
  printf(
      "%u checks passed; current profile applied; private read/create denied\n",
      checks);
  return 0;
}
