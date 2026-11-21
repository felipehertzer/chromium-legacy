// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef BASE_APPLE_LEGACY_MACH_PORT_H_
#define BASE_APPLE_LEGACY_MACH_PORT_H_

#include <mach/mach.h>

#include "base/base_export.h"

// Mach's MIG headers do not consistently annotate introduction versions.
// An explicit weak import keeps Lion's dyld from requiring this newer symbol.
extern "C" kern_return_t mach_port_construct(ipc_space_t task,
                                             mach_port_options_ptr_t options,
                                             mach_port_context_t context,
                                             mach_port_name_t* name)
    __attribute__((weak_import));

namespace base::apple::internal {

// Equivalent to the receive/send-right and queue-limit subset of
// mach_port_construct used by CreateMachPort, using pre-Mavericks APIs.
// On failure, out_port is MACH_PORT_NULL and intermediate rights are released.
BASE_EXPORT kern_return_t
CreateLegacyMachPort(mach_port_t task,
                     bool insert_send_right,
                     const mach_port_msgcount_t* queue_limit,
                     mach_port_t* out_port);

}  // namespace base::apple::internal

#endif  // BASE_APPLE_LEGACY_MACH_PORT_H_
