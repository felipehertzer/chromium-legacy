// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_SECURE_ARCHIVE_H_
#define LEGACY_APPLE_SECURE_ARCHIVE_H_

#import <Foundation/Foundation.h>

namespace chromium_legacy {
// No archive is produced where secure coding is unavailable. The old
// initializer still enforces the same requiresSecureCoding contract.
inline NSData* SecureArchive(void (^encode)(NSKeyedArchiver*)) {
  if (!encode) {
    return nil;
  }
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101300
  if (@available(macOS 10.13, *)) {
    NSKeyedArchiver* encoder =
        [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    encode(encoder);
    [encoder finishEncoding];
    return [encoder.encodedData copy];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101300
  if (@available(macOS 10.8, *)) {
    NSMutableData* buffer = [NSMutableData data];
    NSKeyedArchiver* encoder =
        [[NSKeyedArchiver alloc] initForWritingWithMutableData:buffer];
    encoder.requiresSecureCoding = YES;
    encode(encoder);
    [encoder finishEncoding];
    return [buffer copy];
  }
#endif
  return nil;
}
// Preserve subclasses used by AppKit restoration and set the secure-coding
// requirement before any object decoding. Unsupported systems return nil.
inline NSKeyedUnarchiver* SecureUnarchiver(NSData* data, Class decoder_class) {
  if (!data || !decoder_class ||
      ![decoder_class isSubclassOfClass:NSKeyedUnarchiver.class]) {
    return nil;
  }
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) || \
    __MAC_OS_X_VERSION_MIN_REQUIRED >= 101300
  if (@available(macOS 10.13, *)) {
    return [[decoder_class alloc] initForReadingFromData:data error:nil];
  }
#endif
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101300
  if (@available(macOS 10.8, *)) {
    NSKeyedUnarchiver* decoder = nil;
    @try {
      decoder = [[decoder_class alloc] initForReadingWithData:data];
      decoder.requiresSecureCoding = YES;
      if (@available(macOS 10.11, *)) {
        decoder.decodingFailurePolicy =
            NSDecodingFailurePolicySetErrorAndReturn;
      }
    } @catch (NSException* exception) {
      (void)exception;
      return nil;
    }
    return decoder;
  }
#endif
  return nil;
}
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_SECURE_ARCHIVE_H_
