// Copyright 2020 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/base/cocoa/permissions_utils.h"

#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/feature_list.h"
#include "base/logging.h"
#include "base/mac/mac_util.h"
#include "base/task/thread_pool.h"

namespace ui {
namespace {

// Catalina exposes foreign window names only when screen-recording access is
// granted. This checks metadata without requesting access or capturing pixels.
bool IsScreenCaptureAllowedForWindowList(NSArray* windows, pid_t current_pid) {
  for (NSDictionary* window in windows) {
    NSNumber* owner =
        [window objectForKey:base::apple::CFToNSPtrCast(kCGWindowOwnerPID)];
    if (!owner || owner.intValue == current_pid) {
      continue;
    }
    NSString* name =
        [window objectForKey:base::apple::CFToNSPtrCast(kCGWindowName)];
    NSNumber* layer =
        [window objectForKey:base::apple::CFToNSPtrCast(kCGWindowLayer)];
    if (!name || !layer) {
      continue;
    }
    const NSInteger level = layer.integerValue;
    if (level == CGWindowLevelForKey(kCGNormalWindowLevelKey) ||
        level == CGWindowLevelForKey(kCGDockWindowLevelKey)) {
      return true;
    }
  }
  return false;
}

BASE_FEATURE(kWarmScreenCaptureSonoma, base::FEATURE_ENABLED_BY_DEFAULT);

BASE_FEATURE(kWarmScreenCaptureSequoia, base::FEATURE_DISABLED_BY_DEFAULT);

bool ShouldWarmScreenCapture() {
  const int macos_version = base::mac::MacOSVersion();
  // On macOS < 14, we're using CGWindowListCreateImage to capture a screenshot.
  // Starting in macOS 14, CGWindowListCreateImage causes a "your screen is
  // being captured" chip to show in the menu bar while an app is capturing the
  // screen, and if it's a one-time image capture, it shows for ten seconds.
  if (macos_version < 14'00'00) {
    return true;
  }

  // Kill switch, Sonoma.
  if (macos_version < 15'00'00 &&
      !base::FeatureList::IsEnabled(kWarmScreenCaptureSonoma)) {
    return false;
  }

  // Feature disabled by default for Sequoia unless explicitly enabled.
  if (macos_version >= 15'00'00 &&
      !base::FeatureList::IsEnabled(kWarmScreenCaptureSequoia)) {
    return false;
  }

  // On macOS >= 14, Apple introduced SCScreenshotManager that can be used to
  // capture a screenshot without any notification shown to the user. There's a
  // bug in this API that was fixed in 14.4.
  if (macos_version >= 14'04'00) {
    return true;
  }

  // macOS 14-14.3.
  return false;
}

// Capture a screenshot and throw away the result.
void CaptureScreenshot() {
  if (@available(macOS 14.0, *)) {
    CHECK(base::FeatureList::IsEnabled(kWarmScreenCaptureSonoma));
    // Capturing a screenshot using SCK involves three asynchronous steps:
    //   1. Request shareable contents (getShareableContent...),
    //   2. Instruct SCScreenshotManager to take a screenshot (captureImage...),
    //   3. Receive a callback with the actual image.
    auto shareable_content_handler = ^(SCShareableContent* content,
                                       NSError* error) {
      if (!content.displays.count || error) {
        LOG(WARNING)
            << "Failed to get shareable content during WarmScreenCapture.";
        return;
      }

      SCDisplay* first_display = content.displays.firstObject;
      SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];
      // Set the size to something small to make it clear to anyone reading the
      // code that the screenshot contains no real information.
      config.width = 16;
      config.height = 10;
      auto screenshot_handler = ^(CGImageRef sampleBuffer, NSError* sc_error) {
        // Do nothing.
      };

      SCContentFilter* filter =
          [[SCContentFilter alloc] initWithDisplay:first_display
                                  excludingWindows:@[]];
      [SCScreenshotManager captureImageWithFilter:filter
                                    configuration:config
                                completionHandler:screenshot_handler];
    };
    [SCShareableContent
        getShareableContentExcludingDesktopWindows:true
                               onScreenWindowsOnly:true
                                 completionHandler:shareable_content_handler];
  } else {
    base::apple::ScopedCFTypeRef<CGImageRef>(
        CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly,
                                kCGNullWindowID, kCGWindowImageDefault));
  }
}

}  // namespace

bool IsScreenCaptureAllowed() {
  // The SDK incorrectly marks these APIs as 10.15: they are missing there.
  // Apple r.72786842: https://developer.apple.com/forums/thread/683860
  if (@available(macOS 11.0, *)) {
    return CGPreflightScreenCaptureAccess();
  } else if (@available(macOS 10.15, *)) {
    NSArray* windows = base::apple::CFToNSOwnershipCast(
        CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    return IsScreenCaptureAllowedForWindowList(
        windows, NSProcessInfo.processInfo.processIdentifier);
  }
  // The screen-recording TCC permission was introduced in Catalina.
  // Earlier systems still enforce their normal WindowServer access rules.
  return true;
}

bool TryPromptUserForScreenCapture() {
  if (@available(macOS 11.0, *)) {
    return CGRequestScreenCaptureAccess();
  } else if (@available(macOS 10.15, *)) {
    // Creating, but not starting, a one-pixel stream requests Catalina's native
    // permission. A refusal still fails; never substitute a positive result.
    base::apple::ScopedCFTypeRef<CGDisplayStreamRef> stream(
        CGDisplayStreamCreate(CGMainDisplayID(), 1, 1, 'BGRA', nullptr,
                              ^(CGDisplayStreamFrameStatus, uint64_t,
                                IOSurfaceRef, CGDisplayStreamUpdateRef){
                              }));
    return stream.get() != nullptr;
  }
  return true;
}

void WarmScreenCapture() {
  if (!ShouldWarmScreenCapture()) {
    return;
  }

  // WarmScreenCapture() is meant to be called during early startup. Since the
  // calls to warm the cache may block, execute them off the main thread so we
  // don't hold up startup. To be effective these calls need to run before
  // Chrome is updated. Running them off the main thread technically opens us
  // to a race condition, however updating happens way later so this is not a
  // concern.
  base::ThreadPool::PostTask(
      FROM_HERE,
      // Checking screen capture access hits the TCC.db and reads Chrome's
      // code signature from disk, marking as MayBlock.
      {base::MayBlock(), base::TaskShutdownBehavior::CONTINUE_ON_SHUTDOWN},
      base::BindOnce([] {
        if (IsScreenCaptureAllowed()) {
          CaptureScreenshot();
        }
      }));
}

}  // namespace ui
