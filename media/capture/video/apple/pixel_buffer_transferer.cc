// Copyright 2020 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "media/capture/video/apple/pixel_buffer_transferer.h"

#include "base/check.h"
#include "base/logging.h"

namespace media {

PixelBufferTransferer::PixelBufferTransferer() {
  if (__builtin_available(macOS 10.8, iOS 16.0, tvOS 16.0, *)) {
    VTPixelTransferSessionRef session = nullptr;
    OSStatus error = VTPixelTransferSessionCreate(nil, &session);
    // Preserve the existing invariant for systems supporting VideoToolbox.
    CHECK(error == noErr) << "Creating a VTPixelTransferSession failed: " << error;
    transfer_session_.reset(session);
  }
}

bool PixelBufferTransferer::TransferImage(CVPixelBufferRef source,
                                          CVPixelBufferRef destination) {
  DCHECK(source);
  DCHECK(destination);
  if (__builtin_available(macOS 10.8, iOS 16.0, tvOS 16.0, *)) {
    auto session = static_cast<VTPixelTransferSessionRef>(
        const_cast<void*>(transfer_session_.get()));
    OSStatus error = VTPixelTransferSessionTransferImage(session, source, destination);
    if (error == kVTPixelTransferNotSupportedErr) {
      return false;
    }
    CHECK(error == noErr)
        << "Unexpected VTPixelTransferSessionTransferImage error: " << error;
    return true;
  }
  return false;
}

PixelBufferTransferer::~PixelBufferTransferer() {
  if (__builtin_available(macOS 10.8, iOS 16.0, tvOS 16.0, *)) {
    VTPixelTransferSessionInvalidate(static_cast<VTPixelTransferSessionRef>(
        const_cast<void*>(transfer_session_.get())));
  }
}

}  // namespace media
