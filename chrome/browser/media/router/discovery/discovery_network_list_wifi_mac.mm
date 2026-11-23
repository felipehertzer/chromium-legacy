// Copyright 2017 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/media/router/discovery/discovery_network_list_wifi.h"

#include <CoreWLAN/CoreWLAN.h>

#include <optional>
#include <string>
#include <string_view>

#include "base/check.h"
#include "base/strings/sys_string_conversions.h"

namespace media_router {
namespace {

std::optional<std::string> GetWifiSSID(CWInterface* interface) {
  CHECK(interface);
  std::string ssid(base::SysNSStringToUTF8(interface.ssid));
  if (ssid.empty()) {
    return std::nullopt;
  }
  return ssid;
}

}  // namespace

std::optional<std::string> MaybeGetWifiSSID(std::string_view if_name) {
  NSString* ns_ifname = base::SysUTF8ToNSString(if_name);
  if (!ns_ifname.length)
    return std::nullopt;
  NSArray<CWInterface*>* all_interfaces = nil;
  if (@available(macOS 10.10, *)) {
    all_interfaces = [[CWWiFiClient sharedWiFiClient] interfaces];
  } else {
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000
    CWInterface* interface = [CWInterface interfaceWithName:ns_ifname];
    return interface ? GetWifiSSID(interface) : std::nullopt;
#endif
  }
  if (all_interfaces == nil) {
    return std::nullopt;
  }
  for (CWInterface* interface in all_interfaces) {
    if (interface && [interface.interfaceName isEqualToString:ns_ifname]) {
      return GetWifiSSID(interface);
    }
  }
  return std::nullopt;
}

}  // namespace media_router
