// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <ApplicationServices/ApplicationServices.h>
#include <errno.h>
#include <libproc.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern int sandbox_check(pid_t, const char*, int, ...);

static void PrintString(const char* string) {
  putchar('"');
  for (const unsigned char* p = (const unsigned char*)string; *p; ++p) {
    if (*p == '"' || *p == '\\') {
      putchar('\\');
      putchar(*p);
    } else if (*p < 0x20) {
      printf("\\u%04x", *p);
    } else {
      putchar(*p);
    }
  }
  putchar('"');
}

static unsigned WindowCount(CFArrayRef windows, pid_t pid) {
  unsigned count = 0;
  for (CFIndex i = 0; windows && i < CFArrayGetCount(windows); ++i) {
    CFDictionaryRef window = CFArrayGetValueAtIndex(windows, i);
    CFNumberRef owner = CFDictionaryGetValue(window, kCGWindowOwnerPID);
    CFNumberRef layer = CFDictionaryGetValue(window, kCGWindowLayer);
    int owner_pid = 0, layer_number = -1;
    if (owner && layer &&
        CFNumberGetValue(owner, kCFNumberIntType, &owner_pid) &&
        CFNumberGetValue(layer, kCFNumberIntType, &layer_number) &&
        owner_pid == pid && layer_number == 0) {
      ++count;
    }
  }
  return count;
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: process-probe PID [PID ...]\n");
    return 2;
  }
  CFArrayRef windows = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  printf("[");
  bool failed = false;
  for (int i = 1; i < argc; ++i) {
    char* end = NULL;
    errno = 0;
    long value = strtol(argv[i], &end, 10);
    if (errno || !end || *end || value <= 0 || value > INT_MAX) {
      failed = true;
      break;
    }
    pid_t pid = (pid_t)value;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int path_size = proc_pidpath(pid, path, sizeof(path));
    int sandbox_status = sandbox_check(pid, NULL, 0);
    if (i != 1) {
      putchar(',');
    }
    printf(
        "{\"pid\":%d,\"sandbox_status\":%d,\"onscreen_windows\":%u,\"path\":",
        pid, sandbox_status, WindowCount(windows, pid));
    PrintString(path);
    putchar('}');
    failed |= path_size <= 0 || sandbox_status < 0;
  }
  puts("]");
  if (windows) {
    CFRelease(windows);
  }
  return failed ? 1 : 0;
}
