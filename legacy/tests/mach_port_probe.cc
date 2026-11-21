// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <stdint.h>
#include <stdio.h>

#include "base/apple/legacy_mach_port.h"

namespace {
int checks = 0;
int failures = 0;

void Check(bool condition, const char* name) {
  ++checks;
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", name);
    ++failures;
  }
}

mach_port_msgcount_t QueueLimit(mach_port_t port) {
  mach_port_limits_t limits{};
  mach_msg_type_number_t count = MACH_PORT_LIMITS_INFO_COUNT;
  Check(mach_port_get_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO,
                                 reinterpret_cast<mach_port_info_t>(&limits),
                                 &count) == KERN_SUCCESS,
        "read queue limit");
  return limits.mpl_qlimit;
}

void ReleasePort(mach_port_t port, bool has_send_right) {
  if (has_send_right) {
    Check(mach_port_deallocate(mach_task_self(), port) == KERN_SUCCESS,
          "release send right");
  }
  Check(mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE,
                           -1) == KERN_SUCCESS,
        "release receive right");
}

mach_msg_type_number_t PortCount() {
  mach_port_name_array_t names = nullptr;
  mach_port_type_array_t types = nullptr;
  mach_msg_type_number_t names_count = 0;
  mach_msg_type_number_t types_count = 0;
  kern_return_t result = mach_port_names(mach_task_self(), &names, &names_count,
                                         &types, &types_count);
  Check(result == KERN_SUCCESS, "count Mach names");
  if (names) {
    vm_deallocate(mach_task_self(), reinterpret_cast<vm_address_t>(names),
                  names_count * sizeof(*names));
  }
  if (types) {
    vm_deallocate(mach_task_self(), reinterpret_cast<vm_address_t>(types),
                  types_count * sizeof(*types));
  }
  return names_count;
}
}  // namespace

int main() {
  using base::apple::internal::CreateLegacyMachPort;
  mach_port_t port = MACH_PORT_NULL;
  Check(CreateLegacyMachPort(mach_task_self(), false, nullptr, &port) ==
            KERN_SUCCESS,
        "create receive-only port");
  mach_port_type_t type = 0;
  Check(mach_port_type(mach_task_self(), port, &type) == KERN_SUCCESS,
        "inspect receive-only port");
  Check((type & MACH_PORT_TYPE_RECEIVE) && !(type & MACH_PORT_TYPE_SEND),
        "receive-only port has no send right");
  Check(QueueLimit(port) == MACH_PORT_QLIMIT_DEFAULT, "default queue limit");
  ReleasePort(port, false);

  mach_port_msgcount_t limit = 1;
  Check(CreateLegacyMachPort(mach_task_self(), true, &limit, &port) ==
            KERN_SUCCESS,
        "create receive-and-send port");
  Check(mach_port_type(mach_task_self(), port, &type) == KERN_SUCCESS,
        "inspect receive-and-send port");
  Check((type & MACH_PORT_TYPE_RECEIVE) && (type & MACH_PORT_TYPE_SEND),
        "receive-and-send rights share one name");
  Check(QueueLimit(port) == limit, "custom queue limit");
  struct Message {
    mach_msg_header_t header;
    uint32_t value;
  } message{};
  message.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  message.header.msgh_size = sizeof(message);
  message.header.msgh_remote_port = port;
  message.header.msgh_id = 42;
  message.value = 0x12345678;
  Check(mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                 sizeof(message), 0, MACH_PORT_NULL, 0,
                 MACH_PORT_NULL) == MACH_MSG_SUCCESS,
        "send Mach message");
  Check(mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                 sizeof(message), 0, MACH_PORT_NULL, 0,
                 MACH_PORT_NULL) == MACH_SEND_TIMED_OUT,
        "queue limit enforced");
  struct ReceiveBuffer {
    Message message;
    mach_msg_trailer_t trailer;
  } received{};
  Check(mach_msg(&received.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                 sizeof(received), port, 0, MACH_PORT_NULL) == MACH_MSG_SUCCESS,
        "receive Mach message");
  Check(received.message.value == 0x12345678, "message payload preserved");
  ReleasePort(port, true);

  Check(CreateLegacyMachPort(mach_task_self(), true, nullptr, nullptr) ==
            KERN_INVALID_ARGUMENT,
        "reject missing output");
  port = 123;
  Check(CreateLegacyMachPort(MACH_PORT_NULL, true, nullptr, &port) !=
            KERN_SUCCESS,
        "invalid task fails");
  Check(port == MACH_PORT_NULL, "failure clears output");

  if (mach_port_construct) {
    mach_port_options_t options{};
    options.flags = MPO_INSERT_SEND_RIGHT | MPO_QLIMIT;
    options.mpl.mpl_qlimit = 1;
    Check(mach_port_construct(mach_task_self(), &options, 0, &port) ==
              KERN_SUCCESS,
          "modern constructor remains callable through weak import");
    Check(QueueLimit(port) == 1, "modern constructor queue matches fallback");
    ReleasePort(port, true);
  }

  PortCount();
  mach_msg_type_number_t before = PortCount();
  limit = ~mach_port_msgcount_t{0};
  for (int i = 0; i < 100; ++i) {
    port = MACH_PORT_NULL;
    kern_return_t result =
        CreateLegacyMachPort(mach_task_self(), true, &limit, &port);
    if (result == KERN_SUCCESS) {
      // Kernel versions may clamp or reject an out-of-range queue limit.
      Check(port != MACH_PORT_NULL, "successful extreme limit has a port");
      ReleasePort(port, true);
    } else {
      Check(port == MACH_PORT_NULL, "queue failure clears output");
    }
  }
  Check(PortCount() == before,
        "repeated creation/failure does not leak Mach names");
  printf("%d Mach compatibility checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
