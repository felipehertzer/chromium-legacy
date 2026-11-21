/* Copyright 2026 The Chromium Legacy Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file. */
#include <errno.h>
#include <stdio.h>
#include <time.h>

#include "vpx_ports/vpx_timer.h"

#if !CONFIG_OS_SUPPORT
#error This probe requires the actual OS timer implementation.
#endif

static int checks;
static int failures;
static void Check(int success, const char* name) {
  ++checks;
  if (!success) {
    ++failures;
    fprintf(stderr, "FAIL: %s\n", name);
  }
}
static void Sleep(long nanoseconds) {
  struct timespec duration = {0, nanoseconds};
  while (nanosleep(&duration, &duration) && errno == EINTR) {
  }
}
int main(void) {
  struct vpx_usec_timer timer;
  int64_t first;
  vpx_usec_timer_start(&timer);
  timer.end = timer.begin;
  Check(vpx_usec_timer_elapsed(&timer) == 0, "zero interval");
  Sleep(20000000);
  vpx_usec_timer_mark(&timer);
  first = vpx_usec_timer_elapsed(&timer);
  Check(first >= 10000, "microsecond timer scale");
  Sleep(10000000);
  vpx_usec_timer_mark(&timer);
  Check(vpx_usec_timer_elapsed(&timer) >= first, "monotonic repeated mark");
  vpx_usec_timer_start(&timer);
  Sleep(2000000);
  vpx_usec_timer_mark(&timer);
  Check(vpx_usec_timer_elapsed(&timer) >= 1000, "timer can be restarted");
  printf("%d libvpx timer checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
