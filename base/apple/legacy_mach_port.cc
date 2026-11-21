// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/apple/legacy_mach_port.h"

namespace base::apple::internal {

kern_return_t CreateLegacyMachPort(mach_port_t task,
                                   bool insert_send_right,
                                   const mach_port_msgcount_t* queue_limit,
                                   mach_port_t* out_port) {
  if (!out_port) {
    return KERN_INVALID_ARGUMENT;
  }
  *out_port = MACH_PORT_NULL;

  mach_port_t port = MACH_PORT_NULL;
  kern_return_t result =
      mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &port);
  if (result != KERN_SUCCESS) {
    return result;
  }

  if (queue_limit) {
    mach_port_limits_t limits{};
    limits.mpl_qlimit = *queue_limit;
    result =
        mach_port_set_attributes(task, port, MACH_PORT_LIMITS_INFO,
                                 reinterpret_cast<mach_port_info_t>(&limits),
                                 MACH_PORT_LIMITS_INFO_COUNT);
    if (result != KERN_SUCCESS) {
      mach_port_mod_refs(task, port, MACH_PORT_RIGHT_RECEIVE, -1);
      return result;
    }
  }

  if (insert_send_right) {
    result = mach_port_insert_right(task, port, port, MACH_MSG_TYPE_MAKE_SEND);
    if (result != KERN_SUCCESS) {
      mach_port_mod_refs(task, port, MACH_PORT_RIGHT_RECEIVE, -1);
      return result;
    }
  }

  *out_port = port;
  return KERN_SUCCESS;
}

}  // namespace base::apple::internal
