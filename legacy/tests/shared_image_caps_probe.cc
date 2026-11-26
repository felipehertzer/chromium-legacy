// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <stdio.h>

#include "base/at_exit.h"
#include "base/check.h"
#include "base/check_op.h"
#include "base/command_line.h"
#include "gpu/command_buffer/common/shared_image_capabilities.h"
#include "gpu/ipc/common/shared_image_capabilities.mojom.h"
#include "gpu/ipc/common/shared_image_capabilities_mojom_traits.h"
#include "mojo/core/embedder/embedder.h"
int main(int argc, char** argv) {
  base::AtExitManager exit_manager;
  base::CommandLine::Init(argc, argv);
  mojo::core::Init();
  unsigned checks = 0;
  gpu::SharedImageCapabilities defaults;
  CHECK_EQ(defaults.texture_target_for_io_surfaces, 0x0DE1u);
  ++checks;
  for (uint32_t target : {0x0DE1u, 0x84F5u}) {
    gpu::SharedImageCapabilities input, output;
    input.texture_target_for_io_surfaces = target;
    input.skia_writable_yuv_formats.push_back(viz::MultiPlaneFormat::kNV12);
    input.supports_scanout_shared_images = true;
    input.disable_webgpu_shared_images = true;
    auto bytes = gpu::mojom::SharedImageCapabilities::Serialize(&input);
    CHECK(gpu::mojom::SharedImageCapabilities::Deserialize(bytes, &output));
    ++checks;
    CHECK_EQ(output.texture_target_for_io_surfaces, target);
    ++checks;
    CHECK(output.supports_scanout_shared_images);
    ++checks;
    CHECK(output.disable_webgpu_shared_images);
    ++checks;
    CHECK(output.skia_writable_yuv_formats == input.skia_writable_yuv_formats);
    ++checks;
    bytes.pop_back();
    CHECK(!gpu::mojom::SharedImageCapabilities::Deserialize(bytes, &output));
    ++checks;
  }
  for (uint32_t target : {0u, 0x8513u, 0xDEADu}) {
    gpu::SharedImageCapabilities input, output;
    input.texture_target_for_io_surfaces = target;
    auto bytes = gpu::mojom::SharedImageCapabilities::Serialize(&input);
    CHECK(!gpu::mojom::SharedImageCapabilities::Deserialize(bytes, &output));
    ++checks;
  }
  printf(
      "%u shared-image IPC roundtrip/truncation/invalid-target checks passed\n",
      checks);
}
