// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef MEDIA_MIDI_CORE_MIDI_UTIL_H_
#define MEDIA_MIDI_CORE_MIDI_UTIL_H_

#include <CoreMIDI/MIDIServices.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>

#include "base/compiler_specific.h"
#include "base/containers/span.h"

namespace midi::internal {

// CoreMIDI owns the callback packet list and guarantees the variable-length
// packet storage. Keep its timestamps and SysEx fragments intact.
template <class Receiver>
void DispatchMidiPacketList(const MIDIPacketList& list, Receiver receive) {
  const MIDIPacket* packet = &list.packet[0];
  for (UInt32 index = 0; index < list.numPackets; ++index) {
    // SAFETY: These are the data and length supplied by CoreMIDI for this
    // variable-length packet, not the fixed-size placeholder in the SDK.
    receive(UNSAFE_BUFFERS(base::span(packet->data, packet->length)),
            packet->timeStamp);
    packet = MIDIPacketNext(packet);
  }
}

// `message` comes from the current ParseMidiMessages() validator. CoreMIDI
// permits only SysEx messages to span packets; other messages stay complete.
// The sender is injectable so packing can be tested without MIDI devices.
template <class Sender>
bool SendMidi1Message(base::span<const uint8_t> message,
                      bool is_sysex,
                      MIDITimeStamp timestamp,
                      base::span<uint8_t> storage,
                      Sender send) {
  if (message.empty()) {
    return true;
  }
  if (storage.size() < sizeof(MIDIPacketList) ||
      reinterpret_cast<uintptr_t>(storage.data()) % alignof(MIDIPacketList)) {
    return false;
  }
  constexpr size_t kHeader =
      offsetof(MIDIPacketList, packet) + offsetof(MIDIPacket, data);
  // Reserve the padding that MIDIPacketNext uses on aligned architectures.
  const size_t capacity = std::min<size_t>(storage.size() - kHeader - 3,
                                           std::numeric_limits<UInt16>::max());
  if (!is_sysex && message.size() > capacity) {
    return false;
  }
  auto* list = reinterpret_cast<MIDIPacketList*>(storage.data());
  while (!message.empty()) {
    const auto bytes = message.first(std::min(capacity, message.size()));
    MIDIPacket* packet = MIDIPacketListInit(list);
    if (!MIDIPacketListAdd(list, storage.size(), packet, timestamp,
                           bytes.size(), bytes.data())) {
      return false;
    }
    send(list);
    message = message.subspan(bytes.size());
  }
  return true;
}

}  // namespace midi::internal

#endif  // MEDIA_MIDI_CORE_MIDI_UTIL_H_
