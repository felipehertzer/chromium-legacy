// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <iostream>
#include "base/at_exit.h"
#include "base/command_line.h"
// Compile the actual pool implementation and its optional-symbol path.
#include "media/capture/video/apple/pixel_buffer_pool.mm"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, const char* message) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << message << '\n';
  }
}
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  @autoreleasepool {
    auto pool =
        media::PixelBufferPool::Create(kCVPixelFormatType_32BGRA, 16, 32, 2);
    Check(pool != nullptr, "real CoreVideo pool is created");
    if (!pool) {
      return 1;
    }
    auto first = pool->CreateBuffer();
    auto second = pool->CreateBuffer();
    Check(first && second, "two buffers fit the allocation limit");
    Check(first && CVPixelBufferGetWidth(first.get()) == 16 &&
              CVPixelBufferGetHeight(first.get()) == 32 &&
              CVPixelBufferGetPixelFormatType(first.get()) ==
                  kCVPixelFormatType_32BGRA,
          "allocated buffers retain the requested format and dimensions");
    Check(!pool->CreateBuffer(), "third outstanding buffer is rejected");
    pool->Flush();
    Check(first && second && CVPixelBufferGetWidth(first.get()) == 16 &&
              !pool->CreateBuffer(),
          "flush preserves held buffers and their allocation accounting");
    first.reset();
    auto reused = pool->CreateBuffer();
    Check(static_cast<bool>(reused), "released capacity can be reused");
    second.reset();
    reused.reset();
    pool->Flush();
    auto surviving = pool->CreateBuffer();
    Check(static_cast<bool>(surviving),
          "allocations still work after flushing free buffers");
    pool.reset();
    Check(surviving && CVPixelBufferGetWidth(surviving.get()) == 16 &&
              CVPixelBufferGetHeight(surviving.get()) == 32,
          "a buffer safely outlives its pool");
  }
  std::cout << checks << " pixel buffer pool checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
