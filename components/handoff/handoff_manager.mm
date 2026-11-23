// Copyright 2014 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "components/handoff/handoff_manager.h"

#include "base/check.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "build/build_config.h"
#include "legacy/apple/user_activity.h"
#include "net/base/apple/url_conversions.h"

#if BUILDFLAG(IS_IOS)
#include "components/handoff/pref_names_ios.h"
#include "components/pref_registry/pref_registry_syncable.h"  // nogncheck
#endif

#if BUILDFLAG(IS_MAC)
#include "base/mac/mac_util.h"
#endif

@interface HandoffManager ()

// The active user activity.
@property(nonatomic, strong) NSObject* userActivity;

// Whether the URL of the current tab should be exposed for Handoff.
- (BOOL)shouldUseActiveURL;

// Updates the active NSUserActivity.
- (void)updateUserActivity API_AVAILABLE(macos(10.10));

@end

@implementation HandoffManager {
  GURL _activeURL;
}

@synthesize userActivity = _userActivity;

#if BUILDFLAG(IS_IOS)
+ (void)registerBrowserStatePrefs:(user_prefs::PrefRegistrySyncable*)registry {
  registry->RegisterBooleanPref(
      prefs::kIosHandoffToOtherDevices, true,
      user_prefs::PrefRegistrySyncable::SYNCABLE_PREF);
}
#endif

- (instancetype)init {
  return [super init];
}

- (void)updateActiveURL:(const GURL&)url {
  _activeURL = url;
  if (@available(macOS 10.10, *)) {
    [self updateUserActivity];
  }
}

- (void)updateActiveTitle:(const std::u16string&)title {
  // Assume the activity has already been created since the page navigation
  // will complete before the page title loads. No need to re-create it, just
  // set the title. If the activity has not been created, ignore the update.
  if (@available(macOS 10.10, *)) {
    [(NSUserActivity*)self.userActivity
        setTitle:base::SysUTF16ToNSString(title)];
  }
}

- (BOOL)shouldUseActiveURL {
  return _activeURL.SchemeIsHTTPOrHTTPS();
}

- (void)updateUserActivity {
  NSUserActivity* activity = (NSUserActivity*)self.userActivity;
  // Clear the user activity.
  if (![self shouldUseActiveURL]) {
    [activity invalidate];
    self.userActivity = nil;
    return;
  }
  const GURL activityURL = net::GURLWithNSURL(activity.webpageURL);
  if (activityURL == _activeURL) {
    return;
  }
  [activity invalidate];
  NSString* type = chromium_legacy::BrowsingWebActivityType();
  if (!type) {
    self.userActivity = nil;
    return;
  }
  activity = [[NSUserActivity alloc] initWithActivityType:type];
  activity.webpageURL = net::NSURLWithGURL(_activeURL);
  self.userActivity = activity;
  [activity becomeCurrent];
}

@end

#if BUILDFLAG(IS_IOS)
@implementation HandoffManager (TestingOnly)

- (NSURL*)userActivityWebpageURL {
  return ((NSUserActivity*)self.userActivity).webpageURL;
}

- (NSString*)userActivityTitle {
  return ((NSUserActivity*)self.userActivity).title;
}

@end
#endif
