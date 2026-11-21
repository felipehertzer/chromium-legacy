// Copyright 2021 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/apple/backup_util.h"

#import <Foundation/Foundation.h>

#include "build/build_config.h"
#if BUILDFLAG(IS_MAC)
#include <CoreServices/CoreServices.h>
#endif

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "base/threading/scoped_blocking_call.h"

namespace base::apple {
namespace {
bool IsReachable(NSURL* url) {
  if (@available(macOS 10.10, iOS 8.0, *)) {
    return [url checkPromisedItemIsReachableAndReturnError:nil];
  }
  return [url checkResourceIsReachableAndReturnError:nil];
}
}  // namespace

bool GetBackupExclusion(const FilePath& file_path) {
  base::ScopedBlockingCall scoped_blocking_call(FROM_HERE,
                                                base::BlockingType::MAY_BLOCK);

  NSURL* file_url = apple::FilePathToNSURL(file_path);
  DCHECK(IsReachable(file_url));

#if BUILDFLAG(IS_MAC)
  if (@available(macOS 10.8, *)) {
  } else {
    return CSBackupIsItemExcluded((__bridge CFURLRef)file_url, nullptr);
  }
#endif
  if (@available(macOS 10.8, iOS 5.0, *)) {
    NSError* error = nil;
    NSNumber* value = nil;
    BOOL success = [file_url getResourceValue:&value
                                       forKey:NSURLIsExcludedFromBackupKey
                                        error:&error];
    if (!success) {
      LOG(ERROR) << base::SysNSStringToUTF8(error.description);
      return false;
    }

    return value && value.boolValue;
  }
  return false;
}

namespace {

bool SetBackupState(const FilePath& file_path, bool excluded) {
  base::ScopedBlockingCall scoped_blocking_call(FROM_HERE,
                                                base::BlockingType::MAY_BLOCK);

  NSURL* file_url = apple::FilePathToNSURL(file_path);
  DCHECK(IsReachable(file_url));

#if BUILDFLAG(IS_MAC)
  if (@available(macOS 10.8, *)) {
  } else {
    return CSBackupSetItemExcluded((__bridge CFURLRef)file_url, excluded,
                                   false) == noErr;
  }
#endif
  if (@available(macOS 10.8, iOS 5.0, *)) {
    NSError* error = nil;
    BOOL success = [file_url setResourceValue:@(excluded)
                                       forKey:NSURLIsExcludedFromBackupKey
                                        error:&error];
    LOG_IF(WARNING, !success) << base::SysNSStringToUTF8(error.description);
    return success;
  }
  return false;
}

}  // namespace

bool SetBackupExclusion(const FilePath& file_path) {
  return SetBackupState(file_path, true);
}

bool ClearBackupExclusion(const FilePath& file_path) {
  return SetBackupState(file_path, false);
}

}  // namespace base::apple
