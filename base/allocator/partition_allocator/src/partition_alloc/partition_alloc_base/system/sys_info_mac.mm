// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "partition_alloc/partition_alloc_base/system/sys_info.h"

#import <Foundation/Foundation.h>

#include "partition_alloc/partition_alloc_base/check.h"
#include "partition_alloc/partition_alloc_base/numerics/safe_conversions.h"

namespace partition_alloc::internal::base {

// static
void SysInfo::OperatingSystemVersionNumbers(int32_t* major_version,
                                            int32_t* minor_version,
                                            int32_t* bugfix_version) {
  if (@available(macOS 10.10, *)) {
    NSOperatingSystemVersion version =
        NSProcessInfo.processInfo.operatingSystemVersion;
    *major_version = saturated_cast<int32_t>(version.majorVersion);
    *minor_version = saturated_cast<int32_t>(version.minorVersion);
    *bugfix_version = saturated_cast<int32_t>(version.patchVersion);
    return;
  }

  // PartitionAlloc is standalone and cannot depend on //base's Mac helper.
  @autoreleasepool {
    NSData* data =
        [NSData dataWithContentsOfFile:
                    @"/System/Library/CoreServices/SystemVersion.plist"
                               options:0
                                 error:nil];
    PA_BASE_CHECK(data);
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:nil
                                                           error:nil];
    PA_BASE_CHECK([plist isKindOfClass:[NSDictionary class]]);
    id version = [plist objectForKey:@"ProductVersion"];
    PA_BASE_CHECK([version isKindOfClass:[NSString class]]);
    NSArray<NSString*>* parts = [version componentsSeparatedByString:@"."];
    PA_BASE_CHECK(parts.count >= 2 && parts.count <= 3);
    *major_version =
        saturated_cast<int32_t>([[parts objectAtIndex:0] longLongValue]);
    *minor_version =
        saturated_cast<int32_t>([[parts objectAtIndex:1] longLongValue]);
    *bugfix_version =
        parts.count == 3
            ? saturated_cast<int32_t>([[parts objectAtIndex:2] longLongValue])
            : 0;
  }
}

}  // namespace partition_alloc::internal::base
