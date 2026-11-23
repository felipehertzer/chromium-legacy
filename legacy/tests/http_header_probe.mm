// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <cstdio>
#include "legacy/apple/http_header.h"

// Allows malformed/ambiguous dictionaries that the real response initializer
// may normalize, so rejection does not depend on a modern OS's normalization.
@interface LegacyHTTPHeaderFixture : NSHTTPURLResponse
@property(copy) NSDictionary* fixtureHeaders;
@end
@implementation LegacyHTTPHeaderFixture
@synthesize fixtureHeaders = _fixtureHeaders;
- (NSDictionary*)allHeaderFields {
  return self.fixtureHeaders;
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
    Check(chromium_legacy::EqualHTTPHeaderName(@"X-Test", @"x-TEST"),
          "ASCII case insensitivity");
    Check(!chromium_legacy::EqualHTTPHeaderName(@"X-Test", @"X-Other"),
          "different names");
    Check(!chromium_legacy::EqualHTTPHeaderName(@"X-Test", @"X-Test-Long"),
          "different lengths");
    Check(!chromium_legacy::EqualHTTPHeaderName(@"ſame", @"same"),
          "Unicode folding cannot alias ASCII header names");
    Check(!chromium_legacy::EqualHTTPHeaderName(nil, @"x"), "nil name");
    NSURL* url = [NSURL URLWithString:@"https://sso.invalid/test"];
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc]
         initWithURL:url
          statusCode:200
         HTTPVersion:@"HTTP/1.1"
        headerFields:@{
          @"Access-Control-Allow-Origin" : @"https://example.test",
          @"ACCEPT" : @"application/json",
          @"X-Empty" : @""
        }];
    Check(response.statusCode == 200, "real native HTTP response fixture");
    Check([chromium_legacy::HTTPHeaderField(response,
                                            @"access-control-allow-origin")
              isEqual:@"https://example.test"],
          "CORS origin lookup");
    Check([chromium_legacy::HTTPHeaderField(response, @"accept")
              isEqual:@"application/json"],
          "uppercase response field");
    Check([chromium_legacy::HTTPHeaderField(response, @"x-empty") isEqual:@""],
          "empty values remain distinct from missing headers");
    Check(chromium_legacy::HTTPHeaderField(response, @"absent") == nil,
          "missing field");
    Check(chromium_legacy::HTTPHeaderField(nil, @"accept") == nil,
          "nil response");
    Check(chromium_legacy::HTTPHeaderField(response, nil) == nil, "nil field");
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
    LegacyHTTPHeaderFixture* malformed =
        [[LegacyHTTPHeaderFixture alloc] initWithURL:url
                                          statusCode:200
                                         HTTPVersion:@"HTTP/1.1"
                                        headerFields:@{}];
    malformed.fixtureHeaders = @{
      @"Access-Control-Allow-Origin" : @"*",
      @"access-control-allow-origin" : @"https://other.test"
    };
    Check(chromium_legacy::HTTPHeaderField(
              malformed, @"access-control-allow-origin") == nil,
          "ambiguous case variants are rejected");
    malformed.fixtureHeaders = @{@"accept" : @7};
    Check(chromium_legacy::HTTPHeaderField(malformed, @"accept") == nil,
          "non-string value is rejected");
    malformed.fixtureHeaders = @{@7 : @"invalid", @"accept" : @"text/plain"};
    Check([chromium_legacy::HTTPHeaderField(malformed, @"accept")
              isEqual:@"text/plain"],
          "non-string key cannot interfere with a valid field");
#endif
  }
  std::printf("%d HTTP header checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
