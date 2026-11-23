// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <sys/xattr.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "legacy/apple/quarantine.h"

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
    char filename[] = "/tmp/chromium-legacy-quarantine.XXXXXX";
    int fd = mkstemp(filename);
    Check(fd >= 0, "create isolated test file");
    if (fd < 0)
      return 1;
    close(fd);
    const char seed[] = "0001;12345678;ChromiumLegacyProbe;";
    Check(setxattr(filename, "com.apple.quarantine", seed, sizeof(seed) - 1, 0,
                   0) == 0,
          "seed quarantine only on the owned test file");
    NSURL* file =
        [NSURL fileURLWithPath:[NSString stringWithUTF8String:filename]];
    NSError* error = nil;
    id value = nil;
    BOOL success =
        chromium_legacy::GetQuarantineProperties(file, &value, &error);
    Check(success && [value isKindOfClass:NSDictionary.class],
          "read actual quarantine attributes");
    if (!success || ![value isKindOfClass:NSDictionary.class]) {
      std::fprintf(stderr, "read error: %s\n", error.description.UTF8String);
      unlink(filename);
      return 1;
    }
    NSMutableDictionary* properties = [value mutableCopy];
    NSString* original_agent =
        [properties objectForKey:(__bridge NSString*)kLSQuarantineAgentNameKey];
    NSDate* original_time =
        [properties objectForKey:(__bridge NSString*)kLSQuarantineTimeStampKey];
    Check(original_time != nil, "quarantine timestamp is decoded");
    [properties setObject:(__bridge NSString*)kLSQuarantineTypeWebDownload
                   forKey:(__bridge NSString*)kLSQuarantineTypeKey];
    [properties
        setObject:[NSURL URLWithString:@"https://example.invalid/source"]
           forKey:(__bridge NSString*)kLSQuarantineDataURLKey];
    [properties
        setObject:[NSURL URLWithString:@"https://example.invalid/origin"]
           forKey:(__bridge NSString*)kLSQuarantineOriginURLKey];
    Check(chromium_legacy::SetQuarantineProperties(file, properties, &error),
          "update quarantine through the OS API");
    char attribute[1024] = {};
    ssize_t length = getxattr(filename, "com.apple.quarantine", attribute,
                              sizeof(attribute) - 1, 0, 0);
    Check(length > 0, "quarantine attribute remains present");
    unsigned long flags = std::strtoul(attribute, nullptr, 16);
    Check((flags & 1) == 1, "metadata update never clears the quarantine flag");
    value = nil;
    Check(chromium_legacy::GetQuarantineProperties(file, &value, &error) &&
              [value isKindOfClass:NSDictionary.class],
          "read updated quarantine");
    NSDictionary* updated = value;
    Check([[updated objectForKey:(__bridge NSString*)kLSQuarantineTimeStampKey]
              isEqual:original_time],
          "original quarantine timestamp survives");
    if (original_agent) {
      Check(
          [[updated objectForKey:(__bridge NSString*)kLSQuarantineAgentNameKey]
              isEqual:original_agent],
          "original quarantine agent survives");
    }
    // Newer macOS deliberately stops storing URL metadata. Catalina still
    // stores it, so assert the actual round trip where the OS supports it.
    if (@available(macOS 12.4, *)) {
    } else {
      id data_url =
          [updated objectForKey:(__bridge NSString*)kLSQuarantineDataURLKey];
      id origin_url =
          [updated objectForKey:(__bridge NSString*)kLSQuarantineOriginURLKey];
      bool data_matches =
          [data_url isKindOfClass:NSURL.class] &&
          [[data_url absoluteString] isEqual:@"https://example.invalid/source"];
      bool origin_matches = [origin_url isKindOfClass:NSURL.class] &&
                            [[origin_url absoluteString]
                                isEqual:@"https://example.invalid/origin"];
      if (!data_matches || !origin_matches) {
        std::fprintf(stderr, "URL values: data=%s (%s), origin=%s (%s)\n",
                     [data_url description].UTF8String,
                     NSStringFromClass([data_url class]).UTF8String,
                     [origin_url description].UTF8String,
                     NSStringFromClass([origin_url class]).UTF8String);
      }
      Check(data_matches, "data URL round trip");
      Check(origin_matches, "origin URL round trip");
    }
    unlink(filename);
    // NSURL caches resource values. Production also constructs a fresh file
    // URL for each query, so use a fresh URL for the missing-file check.
    file = [NSURL fileURLWithPath:[NSString stringWithUTF8String:filename]];
    value = nil;
    error = nil;
    Check(!chromium_legacy::GetQuarantineProperties(file, &value, &error) &&
              error,
          "missing file reports an error");
  }
  std::printf("%d quarantine checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
