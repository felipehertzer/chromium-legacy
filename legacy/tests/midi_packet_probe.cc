// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <array>
#include <iostream>
#include <string_view>
#include <vector>

#include "base/at_exit.h"
#include "media/midi/core_midi_util.h"
#include "media/midi/ump_message_util.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, std::string_view name) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << name << '\n';
  }
}

struct Capture {
  std::vector<uint8_t> bytes;
  std::vector<MIDITimeStamp> timestamps;
  std::vector<size_t> lengths;
  void Receive(const MIDIPacketList* list) {
    midi::internal::DispatchMidiPacketList(
        *list, [this](base::span<const uint8_t> data, MIDITimeStamp timestamp) {
          bytes.insert(bytes.end(), data.begin(), data.end());
          timestamps.push_back(timestamp);
          lengths.push_back(data.size());
        });
  }
};
}  // namespace

int main() {
  base::AtExitManager at_exit;
  alignas(MIDIPacketList) std::array<uint8_t, 65552> allocation;
  allocation.fill(0xa5);
  auto storage = base::span(allocation).first(65536u);
  constexpr MIDITimeStamp kTimestamp = 0x123456789abcdef0;
  auto pack = [&](base::span<const uint8_t> data, bool sysex,
                  Capture& capture) {
    return midi::internal::SendMidi1Message(
        data, sysex, kTimestamp, storage,
        [&](const MIDIPacketList* list) { capture.Receive(list); });
  };

  Capture empty;
  Check(pack({}, false, empty) && empty.bytes.empty() && empty.lengths.empty(),
        "empty messages do not send packets");

  const std::array<uint8_t, 10> mixed = {0x90, 60,   100, 0xc0, 45,
                                         0xf8, 0xf0, 1,   2,    0xf7};
  const auto messages = midi::ParseMidiMessages(mixed);
  Check(messages.size() == 4, "current MIDI validator separates message types");
  Capture ordinary;
  bool ok = true;
  for (const auto& message : messages) {
    ok &= pack(message.GetData(), message.is_sysex, ordinary);
  }
  Check(
      ok && ordinary.bytes == std::vector<uint8_t>(mixed.begin(), mixed.end()),
      "channel, realtime and SysEx bytes survive native packet packing");
  Check(ordinary.lengths == std::vector<size_t>({3, 2, 1, 4}),
        "non-SysEx messages stay complete and separate");
  Check(std::ranges::all_of(ordinary.timestamps,
                            [](auto value) { return value == kTimestamp; }),
        "all outgoing packets retain the full 64-bit timestamp");

  std::vector<uint8_t> sysex(200003, 0x35);
  sysex.front() = 0xf0;
  sysex.back() = 0xf7;
  const auto long_messages = midi::ParseMidiMessages(sysex);
  Check(long_messages.size() == 1 && long_messages.front().is_sysex,
        "large SysEx remains one validated message");
  Capture large;
  Check(pack(sysex, true, large) && large.bytes == sysex,
        "large SysEx survives several CoreMIDI packet lists");
  Check(large.lengths.size() > 3 &&
            std::ranges::all_of(
                large.lengths,
                [](auto length) { return length > 0 && length <= 65535; }),
        "packet lengths fit the native UInt16 field");
  Check(std::ranges::all_of(large.timestamps,
                            [](auto value) { return value == kTimestamp; }),
        "fragment timestamps remain unchanged");
  Check(std::ranges::all_of(base::span(allocation).subspan(65536u),
                            [](auto value) { return value == 0xa5; }),
        "native packet packing preserves the buffer canary");

  Capture oversized;
  Check(!pack(sysex, false, oversized) && oversized.lengths.empty(),
        "oversized non-SysEx messages are rejected without partial sends");
  const std::array<uint8_t, 3> note = {0x90, 60, 100};
  Capture invalid;
  auto sender = [&](const MIDIPacketList* list) { invalid.Receive(list); };
  Check(!midi::internal::SendMidi1Message(note, false, kTimestamp,
                                          storage.first(4u), sender) &&
            invalid.lengths.empty(),
        "undersized packet storage fails safely");
  Check(!midi::internal::SendMidi1Message(note, false, kTimestamp,
                                          storage.subspan(1u), sender) &&
            invalid.lengths.empty(),
        "misaligned packet storage fails safely");

  alignas(MIDIPacketList) std::array<uint8_t, 2048> input_storage{};
  // SAFETY: The aligned, owned storage exceeds the SDK packet-list size.
  auto* input =
      UNSAFE_BUFFERS(reinterpret_cast<MIDIPacketList*>(input_storage.data()));
  MIDIPacket* packet = MIDIPacketListInit(input);
  const std::array<uint8_t, 3> beginning = {0xf0, 1, 2};
  const std::array<uint8_t, 2> ending = {3, 0xf7};
  packet = MIDIPacketListAdd(input, input_storage.size(), packet, 100,
                             beginning.size(), beginning.data());
  packet = MIDIPacketListAdd(input, input_storage.size(), packet, 200,
                             ending.size(), ending.data());
  packet = MIDIPacketListAdd(input, input_storage.size(), packet, 300,
                             note.size(), note.data());
  Check(packet && input->numPackets == 3,
        "SDK constructs a variable-length input list");
  Capture incoming;
  incoming.Receive(input);
  Check(incoming.bytes ==
                std::vector<uint8_t>({0xf0, 1, 2, 3, 0xf7, 0x90, 60, 100}) &&
            incoming.lengths == std::vector<size_t>({3, 2, 3}) &&
            incoming.timestamps == std::vector<MIDITimeStamp>({100, 200, 300}),
        "input dispatch retains SysEx fragments, packet order and individual "
        "timestamps");
  input->numPackets = 0;
  Capture no_input;
  no_input.Receive(input);
  Check(no_input.bytes.empty() && no_input.timestamps.empty(),
        "empty native input lists do not dispatch");

  std::cout << checks << " CoreMIDI packet checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}
