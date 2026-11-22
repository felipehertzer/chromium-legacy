// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>

#include "legacy/apple/secure_archive.h"

@interface LegacySecureDecoderFixture : NSKeyedUnarchiver
@end
@implementation LegacySecureDecoderFixture
@end

@interface LegacyInsecureArchiveFixture : NSObject <NSCoding>
@end
@implementation LegacyInsecureArchiveFixture
- (void)encodeWithCoder:(NSCoder*)coder {
  (void)coder;
}
- (instancetype)initWithCoder:(NSCoder*)coder {
  (void)coder;
  return [super init];
}
@end

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, const char* message) {
  ++checks;
  if (!success) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", message);
  }
}
}  // namespace
int main() {
  @autoreleasepool {
    Check(chromium_legacy::SecureArchive(nil) == nil, "nil callback");
    if (@available(macOS 10.8, *)) {
      NSDictionary* expected =
          @{@"window" : @"test",
            @"bounds" : @[ @10, @20 ]};
      __block bool secure = false;
      NSData* data = chromium_legacy::SecureArchive(^(NSKeyedArchiver* coder) {
        secure = coder.requiresSecureCoding;
        [coder encodeObject:expected forKey:@"payload"];
      });
      Check(secure, "secure coding is enabled before encoding");
      Check(data.length > 0, "real archive produced");
      NSKeyedUnarchiver* decoder = chromium_legacy::SecureUnarchiver(
          data, LegacySecureDecoderFixture.class);
      Check([decoder isKindOfClass:LegacySecureDecoderFixture.class],
            "decoder subclass is preserved");
      Check(decoder.requiresSecureCoding, "decoder requires secure coding");
      id decoded = [decoder
          decodeObjectOfClasses:[NSSet setWithArray:@[
            NSDictionary.class, NSArray.class, NSString.class, NSNumber.class
          ]]
                         forKey:@"payload"];
      [decoder finishDecoding];
      Check([decoded isEqual:expected], "secure archive round trip");
      NSKeyedUnarchiver* restricted = chromium_legacy::SecureUnarchiver(
          data, LegacySecureDecoderFixture.class);
      bool wrong_class_rejected = false;
      @try {
        wrong_class_rejected =
            [restricted decodeObjectOfClass:NSString.class forKey:@"payload"] ==
            nil;
      } @catch (NSException* exception) {
        (void)exception;
        wrong_class_rejected = true;
      }
      Check(wrong_class_rejected, "decoder rejects a disallowed class");
      bool downgrade_rejected = false;
      @try {
        restricted.requiresSecureCoding = NO;
      } @catch (NSException* exception) {
        (void)exception;
        downgrade_rejected = true;
      }
      Check(downgrade_rejected, "secure decoding cannot be downgraded");
      Check(chromium_legacy::SecureUnarchiver(data, NSObject.class) == nil,
            "non-decoder class is refused");
      Check(chromium_legacy::SecureUnarchiver(nil, NSKeyedUnarchiver.class) ==
                nil,
            "nil archive is refused");

      bool rejected = false;
      @try {
        chromium_legacy::SecureArchive(^(NSKeyedArchiver* coder) {
          [coder encodeObject:[[LegacyInsecureArchiveFixture alloc] init]
                       forKey:@"payload"];
        });
      } @catch (NSException* exception) {
        (void)exception;
        rejected = true;
      }
      Check(rejected, "insecure coding object is rejected");
    } else {
      __block bool called = false;
      NSData* data = chromium_legacy::SecureArchive(^(NSKeyedArchiver* coder) {
        (void)coder;
        called = true;
      });
      Check(data == nil && !called,
            "unsupported secure coding produces no archive");
      Check(chromium_legacy::SecureUnarchiver([NSData data],
                                              NSKeyedUnarchiver.class) == nil,
            "unsupported secure decoding remains unavailable");
    }
  }
  std::printf("%d secure archive checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
