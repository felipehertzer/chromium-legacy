// Copyright 2012 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/icon_loader.h"

#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/threading/thread.h"
#include "legacy/apple/file_type.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_util_mac.h"

// static
IconLoader::IconGroup IconLoader::GroupForFilepath(
    const base::FilePath& file_path) {
  // The best option is to get the type directly from the file. The next best
  // option is to pull the extension from the file and get the type from that.
  // The last and worst option is to fall back to `public.content` which will
  // give a generic file icon.

  NSString* identifier =
      chromium_legacy::FileTypeForURL(base::apple::FilePathToNSURL(file_path));
  if (identifier) {
    return base::SysNSStringToUTF8(identifier);
  }

  std::string extension_string = file_path.FinalExtension();
  if (!extension_string.empty()) {
    // Remove the leading dot.
    extension_string.erase(extension_string.begin());

    identifier = chromium_legacy::FileTypeForExtension(
        base::SysUTF8ToNSString(extension_string));
    if (identifier) {
      return base::SysNSStringToUTF8(identifier);
    }
  }

  return base::SysNSStringToUTF8(base::apple::CFToNSPtrCast(kUTTypeContent));
}

// static
scoped_refptr<base::TaskRunner> IconLoader::GetReadIconTaskRunner() {
  // NSWorkspace is thread-safe.
  return base::ThreadPool::CreateTaskRunner(traits());
}

void IconLoader::ReadIcon() {
  NSString* identifier = base::SysUTF8ToNSString(group_);
  NSImage* icon;
  if (@available(macOS 11.0, *)) {
    icon = [NSWorkspace.sharedWorkspace
        iconForContentType:[UTType typeWithIdentifier:identifier]];
  } else {
    icon = [NSWorkspace.sharedWorkspace iconForFileType:identifier];
  }

  gfx::Image image;
  if (icon_size_ == ALL) {
    // The NSImage already has all sizes.
    image = gfx::Image(icon);
  } else {
    NSSize size = NSZeroSize;
    switch (icon_size_) {
      case IconLoader::SMALL:
        size = NSMakeSize(16, 16);
        break;
      case IconLoader::NORMAL:
        size = NSMakeSize(32, 32);
        break;
      default:
        NOTREACHED();
    }

    gfx::ImageSkia image_skia = gfx::ImageSkiaFromResizedNSImage(icon, size);
    if (!image_skia.isNull()) {
      image_skia.MakeThreadSafe();
      image = gfx::Image(image_skia);
    }
  }

  target_task_runner_->PostTask(
      FROM_HERE,
      base::BindOnce(std::move(callback_), std::move(image), group_));
  delete this;
}
