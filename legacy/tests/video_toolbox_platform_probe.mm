// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// Exercise the actual production helpers without constructing GPU services.
// Unused encoder methods are removed by Chromium's normal dead-strip link.
#include <dlfcn.h>

#include <iostream>
#include <string_view>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "media/gpu/mac/vt_config_util.mm"
#include "media/gpu/mac/vt_video_encode_accelerator_mac.mm"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, std::string_view description) {
  ++checks;
  if (!success) {
    ++failures;
    std::cerr << "FAIL: " << description << "\n";
  }
}
void CheckField(CFDictionaryRef dictionary,
                CFStringRef key,
                CFTypeRef expected,
                std::string_view description) {
  if (!dictionary) {
    Check(false, description);
    return;
  }
  CFTypeRef actual = CFDictionaryGetValue(dictionary, key);
  Check(actual && CFEqual(actual, expected), description);
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  @autoreleasepool {
    if (__builtin_available(macOS 10.9, *)) {
      bool svc = media::IsSVCSupported(media::H264PROFILE_BASELINE);
      bool qp = media::IsManualQpSupported(media::H264PROFILE_BASELINE);
      Check(!svc ||
                (dlsym(RTLD_DEFAULT, "kVTVideoEncoderSpecification_"
                                     "EnableLowLatencyRateControl") &&
                 dlsym(RTLD_DEFAULT,
                       "kVTCompressionPropertyKey_BaseLayerFrameRateFraction")),
            "advertised SVC has its real native exports");
      Check(!qp || dlsym(RTLD_DEFAULT, "kVTEncodeFrameOptionKey_BaseFrameQP"),
            "advertised QP has its real native export");
      if (__builtin_available(macOS 11.3, *)) {
        Check(svc, "H264 SVC is retained on supported systems");
      } else {
        Check(!svc, "older systems do not advertise unavailable SVC");
      }
      if (__builtin_available(macOS 12.0, *)) {
        Check(qp, "manual H264 QP is retained on supported systems");
      } else {
        Check(!qp, "older systems do not advertise unavailable manual QP");
      }
      Check(!media::IsSVCSupported(media::VP9PROFILE_PROFILE0),
            "VT encoder does not advertise VP9 temporal layers");
      auto session = media::CreateCompressionSession(
          media::H264PROFILE_BASELINE, gfx::Size(640, 480),
          media::EncoderType::kSoftware, false);
      Check(session.has_value(), "real native H264 session creation");
      if (session.has_value()) {
        Check(!media::IsHardwareEncoder(session.value().get()),
              "explicit native software session stays software");
      }
    }
    media::VideoColorSpace color(media::VideoColorSpace::PrimaryID::BT709,
                                 media::VideoColorSpace::TransferID::BT709,
                                 media::VideoColorSpace::MatrixID::BT709,
                                 gfx::ColorSpace::RangeID::LIMITED);
    auto format = media::CreateFormatExtensions(kCMVideoCodecType_H264,
                                                media::H264PROFILE_BASELINE, 8,
                                                color, std::nullopt);
    Check(static_cast<bool>(format), "actual format extension dictionary");
    if (format) {
      CheckField(format.get(), kCMFormatDescriptionExtension_ColorPrimaries,
                 kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
                 "BT709 primaries");
      CheckField(format.get(), kCMFormatDescriptionExtension_TransferFunction,
                 kCMFormatDescriptionTransferFunction_ITU_R_709_2,
                 "BT709 transfer");
      CheckField(format.get(), kCMFormatDescriptionExtension_YCbCrMatrix,
                 kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2, "BT709 matrix");
      CheckField(format.get(), kCMFormatDescriptionExtension_FullRangeVideo,
                 kCFBooleanFalse, "limited range is preserved");
    }
    media::VideoColorSpace gamma(media::VideoColorSpace::PrimaryID::BT709,
                                 media::VideoColorSpace::TransferID::GAMMA22,
                                 media::VideoColorSpace::MatrixID::BT709,
                                 gfx::ColorSpace::RangeID::FULL);
    auto gamma_format = media::CreateFormatExtensions(
        kCMVideoCodecType_H264, media::H264PROFILE_BASELINE, 8, gamma,
        std::nullopt);
    CheckField(gamma_format.get(), kCMFormatDescriptionExtension_FullRangeVideo,
               kCFBooleanTrue, "full range is preserved");
    CheckField(gamma_format.get(), kCMFormatDescriptionExtension_GammaLevel,
               (__bridge CFTypeRef) @2.2, "explicit gamma is preserved");
  }
  std::cout << checks << " VideoToolbox platform checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
