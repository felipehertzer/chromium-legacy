// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "printing/backend/cups_deleters.h"
#include "base/check.h"
#include "build/build_config.h"

namespace printing {

void HttpDeleter::operator()(http_t* http) const {
  httpClose(http);
}

void DestinationDeleter::operator()(cups_dest_t* dest) const {
  cupsFreeDests(1, dest);
}

void DestInfoDeleter::operator()(cups_dinfo_t* info) const {
#if BUILDFLAG(IS_MAC)
  if (__builtin_available(macOS 10.8, *)) {
    cupsFreeDestInfo(info);
    return;
  }
  CHECK(!info);  // Native destination-info objects cannot be created on Lion.
#else
  cupsFreeDestInfo(info);
#endif
}

void OptionDeleter::operator()(cups_option_t* option) const {
  // Frees the name and value buffers then the struct itself
  cupsFreeOptions(1, option);
}

}  // namespace printing
