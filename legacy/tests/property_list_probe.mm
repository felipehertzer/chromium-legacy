// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>

#include <iostream>
#include <string_view>

#include "base/apple/foundation_util.h"
#include "base/apple/property_list_util.h"
#include "base/at_exit.h"
#include "base/files/scoped_temp_dir.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, std::string_view name) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << name << '\n';
  }
}
}  // namespace

int main() {
  base::AtExitManager at_exit;
  @autoreleasepool {
    base::ScopedTempDir temporary;
    if (!temporary.CreateUniqueTempDir()) {
      return 1;
    }
    NSURL* root = base::apple::FilePathToNSURL(temporary.GetPath());
    NSURL* file = [root URLByAppendingPathComponent:@"owned.plist"];
    NSDictionary* original = @{
      @"title" : @"Açúcar — 日本語",
      @"enabled" : @YES,
      @"count" : @42,
      @"data" : [@"owned bytes" dataUsingEncoding:NSUTF8StringEncoding],
      @"nested" : @{@"key" : @"value"}
    };
    NSError* error = nil;
    Check(base::apple::WritePropertyListDictionary(original, file, &error) &&
              !error,
          "XML dictionary write succeeds");
    Check([base::apple::ReadPropertyListDictionary(file)
              isEqualToDictionary:original],
          "Unicode, booleans, binary data and nested values round-trip");
    Check([[NSDictionary dictionaryWithContentsOfURL:file]
              isEqualToDictionary:original],
          "output matches the original Foundation dictionary reader");
    NSPropertyListFormat format;
    [NSPropertyListSerialization
        propertyListWithData:[NSData dataWithContentsOfURL:file]
                     options:NSPropertyListImmutable
                      format:&format
                       error:nil];
    Check(format == NSPropertyListXMLFormat_v1_0,
          "output retains the dictionary API XML format");

    NSDictionary* replacement = @{@"replacement" : @"complete"};
    Check(base::apple::WritePropertyListDictionary(replacement, file) &&
              [base::apple::ReadPropertyListDictionary(file)
                  isEqualToDictionary:replacement],
          "atomic replacement yields the complete new dictionary");
    NSDictionary* invalid = @{@"not a plist value" : [[NSObject alloc] init]};
    error = nil;
    Check(!base::apple::WritePropertyListDictionary(invalid, file, &error) &&
              error,
          "invalid property values report an error");
    Check([base::apple::ReadPropertyListDictionary(file)
              isEqualToDictionary:replacement],
          "failed serialization preserves the existing file");

    error = nil;
    Check(
        !base::apple::WritePropertyListDictionary(nil, file, &error) && !error,
        "nil dictionary retains the original no-op failure behavior");
    Check(base::apple::WritePropertyListDictionary(@{}, file) &&
              base::apple::ReadPropertyListDictionary(file).count == 0,
          "empty dictionaries remain valid property lists");

    NSData* binary = [NSPropertyListSerialization
        dataWithPropertyList:original
                      format:NSPropertyListBinaryFormat_v1_0
                     options:0
                       error:nil];
    Check([binary writeToURL:file options:NSDataWritingAtomic error:nil] &&
              [base::apple::ReadPropertyListDictionary(file)
                  isEqualToDictionary:original],
          "binary plists remain readable");
    NSMutableDictionary* mutable_dictionary =
        base::apple::ReadMutablePropertyListDictionary(file);
    [mutable_dictionary setValue:nil forKey:@"title"];
    [mutable_dictionary setValue:@"new" forKey:@"other"];
    Check(![mutable_dictionary objectForKey:@"title"] &&
              [[mutable_dictionary objectForKey:@"other"] isEqual:@"new"] &&
              [original objectForKey:@"title"],
          "mutable reads own their root and dictionary nil writes remove keys");

    NSURL* missing = [root URLByAppendingPathComponent:@"missing.plist"];
    error = nil;
    Check(!base::apple::ReadPropertyListDictionary(missing, &error) && error,
          "missing-file errors propagate");
    NSURL* unavailable = [[root URLByAppendingPathComponent:@"missing-parent"]
        URLByAppendingPathComponent:@"file.plist"];
    error = nil;
    Check(!base::apple::WritePropertyListDictionary(original, unavailable,
                                                    &error) &&
              error,
          "write errors propagate without creating parent directories");

    NSData* malformed =
        [@"not a property list" dataUsingEncoding:NSUTF8StringEncoding];
    [malformed writeToURL:file options:NSDataWritingAtomic error:nil];
    error = nil;
    Check(!base::apple::ReadPropertyListDictionary(file, &error) && error,
          "malformed input is rejected with the parser error");
    NSData* array = [NSPropertyListSerialization
        dataWithPropertyList:@[ @"wrong root type" ]
                      format:NSPropertyListXMLFormat_v1_0
                     options:0
                       error:nil];
    [array writeToURL:file options:NSDataWritingAtomic error:nil];
    error = nil;
    Check(!base::apple::ReadPropertyListDictionary(file, &error) &&
              [error.domain isEqual:NSCocoaErrorDomain] &&
              error.code == NSPropertyListReadCorruptError,
          "non-dictionary roots fail the typed dictionary contract");
    Check(!base::apple::ReadMutablePropertyListDictionary(file),
          "mutable reads also reject non-dictionary roots");

    base::apple::WritePropertyListDictionary(original, file);
    NSFileManager* files = NSFileManager.defaultManager;
    [files setAttributes:@{
      NSFilePosixPermissions : @0000
    }
            ofItemAtPath:file.path
                   error:nil];
    error = nil;
    NSDictionary* unreadable =
        base::apple::ReadPropertyListDictionary(file, &error);
    const bool permission_preserved =
        !unreadable && error && [error.domain isEqual:NSCocoaErrorDomain] &&
        error.code == NSFileReadNoPermissionError;
    [files setAttributes:@{
      NSFilePosixPermissions : @0600
    }
            ofItemAtPath:file.path
                   error:nil];
    Check(permission_preserved,
          "access-denied classification is preserved for policy readers");
    Check([base::apple::ReadPropertyListDictionary(file)
              isEqualToDictionary:original],
          "permission fixture restoration leaves the owned file intact");
  }
  std::cout << checks << " property-list checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}
