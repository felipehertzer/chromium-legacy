// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <stdio.h>
#include <stdlib.h>

#include "legacy/apple/cv_buffer.h"
#include "legacy/apple/scoped_dispatch.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, const char* label) {
  ++checks;
  if (!value) {
    ++failures;
    fprintf(stderr, "FAILED: %s\n", label);
  }
}
struct Finalization {
  dispatch_semaphore_t signal;
  int count = 0;
};
void Finalize(void* context) {
  auto* state = static_cast<Finalization*>(context);
  ++state->count;
  dispatch_semaphore_signal(state->signal);
}
}  // namespace

int main() {
  @autoreleasepool {
    CVPixelBufferRef buffer = nullptr;
    Check(CVPixelBufferCreate(nullptr, 4, 4, kCVPixelFormatType_32BGRA, nullptr,
                              &buffer) == kCVReturnSuccess,
          "CoreVideo buffer created");
    if (buffer) {
      const CFStringRef key = CFSTR("ChromiumLegacyProbe");
      Check(!chromium_legacy::HasBufferAttachment(buffer, key),
            "missing attachment not present");
      Check(chromium_legacy::CopyBufferAttachment(buffer, key, nullptr) ==
                nullptr,
            "missing attachment copy is null");
      CFMutableStringRef value =
          CFStringCreateMutableCopy(nullptr, 0, CFSTR("retained value"));
      CVBufferSetAttachment(buffer, key, value,
                            kCVAttachmentMode_ShouldPropagate);
      Check(chromium_legacy::HasBufferAttachment(buffer, key),
            "attachment present after set");
      CVAttachmentMode mode = kCVAttachmentMode_ShouldNotPropagate;
      CFTypeRef copy =
          chromium_legacy::CopyBufferAttachment(buffer, key, &mode);
      Check(copy && CFEqual(copy, value), "attachment contents copied");
      Check(mode == kCVAttachmentMode_ShouldPropagate,
            "propagation mode preserved");
      CFRelease(value);
      CVBufferRemoveAttachment(buffer, key);
      Check(!chromium_legacy::HasBufferAttachment(buffer, key),
            "attachment absent after removal");
      Check(copy && CFEqual(copy, CFSTR("retained value")),
            "copy remains alive after original owners release");
      if (copy) {
        CFRelease(copy);
      }
      CVPixelBufferRelease(buffer);
    }

    chromium_legacy::ScopedDispatchObject<dispatch_semaphore_t> signal(
        dispatch_semaphore_create(0));
    Finalization state{signal.get()};
    chromium_legacy::ScopedDispatchObject<dispatch_queue_t> queue;
    Check(!queue, "default dispatch owner is empty");
    @autoreleasepool {
      queue.reset(dispatch_queue_create("chromium.legacy.dispatch.probe",
                                        DISPATCH_QUEUE_SERIAL));
      Check(static_cast<bool>(queue), "created queue adopted");
      dispatch_set_context(queue.get(), &state);
      dispatch_set_finalizer_f(queue.get(), Finalize);
      __block int delivered = 0;
      dispatch_async(queue.get(), ^{
        delivered = 42;
      });
      dispatch_sync(queue.get(), ^{
                    });
      Check(delivered == 42, "adopted queue executes blocks");
      queue.reset();
      Check(!queue, "reset clears dispatch owner");
    }
    const bool reset_released =
        dispatch_semaphore_wait(
            signal.get(), dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
        0;
    Check(reset_released,
          "reset releases the queue after ARC temporaries drain");
    if (!reset_released) {
      _Exit(1);
    }
    Check(state.count == 1, "reset finalizes exactly once");
    @autoreleasepool {
      {
        chromium_legacy::ScopedDispatchObject<dispatch_queue_t> other(
            dispatch_queue_create("chromium.legacy.dispatch.destructor",
                                  DISPATCH_QUEUE_SERIAL));
        dispatch_set_context(other.get(), &state);
        dispatch_set_finalizer_f(other.get(), Finalize);
      }
    }
    const bool destructor_released =
        dispatch_semaphore_wait(
            signal.get(), dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
        0;
    Check(destructor_released,
          "destructor releases the queue after ARC temporaries drain");
    if (!destructor_released) {
      _Exit(1);
    }
    Check(state.count == 2, "destructor finalizes exactly once");
  }
  printf("%d media platform checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
